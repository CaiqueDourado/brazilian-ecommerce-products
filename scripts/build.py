"""Build the published catalog from the raw export (D:\\catalogo_raw, written by export_sqlserver.py).

Rule of this dataset: flag, don't delete. Every cleaning step keeps the original value in a *_raw
column or explains itself in a *_flag column, so anyone can undo or redo a decision.

Output (in --out, default data/):
    plataformas.parquet       e-commerce platforms (13)
    lojas.parquet             stores with name repair, platform and product count
    caracteristicas.parquet   spec-sheet keys and the question used on the sites
    grupos.parquet            product groups with size, stores, brands and quality flags
    produtos/                 one row per collected offer (partitioned Parquet files)
    ficha/                    spec sheet, one row per key/value
    eans/                     one row per identifier, split and classified (GTIN, NCM, SKU…)
    categorias/               breadcrumb pieces with origin and noise flags
    build_stats.json          counts used by validate.py and the README

Needs: python -m pip install --user duckdb ftfy pyarrow
Usage:  python scripts\\build.py --raw D:\\catalogo_raw --out D:\\catalogo_build
"""

from __future__ import annotations

import argparse
import html
import json
import re
import time
import unicodedata
from pathlib import Path

import duckdb
import pandas as pd

# ---------------------------------------------------------------- decisions (see docs/methodology.md)

PRICE_INACTIVE = 99999  # the crawler wrote 99999.99 for inactive products; >= this is not a real price
BIG_GROUP = 1000        # groups above this many offers are flagged as chained merges ("supergrupos")
MANY_BRANDS = 10        # groups with more distinct brands than this are flagged too
FIXED_GROUP_DATE = "2022-04-04 00:03:14.763"  # bulk UPDATE that stamped ~437k groups with the same date
UNRELIABLE_AVAILABILITY_STORES = (1, 2, 3)    # B2W crawl path saved OutOfStock as InStock

# Brands that asked to have their customer-service contacts removed from the sites. Their SAC rows
# are dropped from the spec sheet (the only deletion in this build, by request of the brands).
REMOVED_BRANDS = [
    "getech", "g-tech", "sunglider", "herval", "incoterm", "bel fix", "umbro", "aurora", "pro-bass",
    "r3p", "thunderx3", "aerocool", "fortrek", "highmed", "edez", "mundial records",
]
SAC_KEY_PATTERN = r"(?i)(\bsac\b|atendimento|telefone|e-?mail|contato)"

AVAILABILITY = {
    "in stock": "disponivel", "http://schema.org/instock": "disponivel", "in_stock": "disponivel",
    "disponível": "disponivel", "disponivel": "disponivel", "disponível,in stock": "disponivel",
    "out of stock": "indisponivel", "out_of_stock": "indisponivel", "indisponível": "indisponivel",
    "indisponivel": "indisponivel", "indisponível,out of stock": "indisponivel",
    "http://schema.org/outofstock": "indisponivel",
}

CATEGORY_NOISE = r"^(coll-|skuoriginal-|extcod)|-intg$|^[0-9 ./-]+$|^no magalu$"


# ---------------------------------------------------------------- text helpers

MOJIBAKE = re.compile(r"[ÃÂ][^A-Za-zÀ-ÿ0-9\s]|â€")  # Ã© Ã§ Âº… (uppercase "SÃO" is left alone)
ENTITY = re.compile(r"&(?:#\d+|#x[0-9a-f]+|[a-z]+);", re.I)


def repair(text: str | None) -> str | None:
    """Fix text read with the wrong encoding at collection time (Ã© → é) and HTML entities."""
    if text is None:
        return None
    from ftfy import fix_text

    fixed = fix_text(text, normalization="NFC") if MOJIBAKE.search(text) else text
    fixed = html.unescape(fixed) if ENTITY.search(fixed) else fixed
    return re.sub(r"\s+", " ", fixed).strip()


def slugify(text: str | None) -> str | None:
    """Accent-insensitive slug. Unlike the old T-SQL Slugify, digits are kept ('²' no longer eats '2')
    and colliding slugs are not "fixed" by incrementing a trailing number (iphone-11 → iphone-12)."""
    if not text:
        return None
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text.lower()).strip("-")
    return text or None


# ---------------------------------------------------------------- build steps

def step(name: str):
    print(f"== {name}", flush=True)
    return time.time()


def done(began: float, con, table: str | None = None):
    extra = f", {con.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]:,} rows" if table else ""
    print(f"   {time.time() - began:,.0f} s{extra}", flush=True)


def build(raw: Path, out: Path, threads: int, memory: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / "_tmp"
    tmp.mkdir(exist_ok=True)
    con = duckdb.connect(str(tmp / "build.duckdb"))
    con.execute(f"SET threads = {threads}; SET memory_limit = '{memory}'; SET temp_directory = '{tmp.as_posix()}'")
    con.execute("SET preserve_insertion_order = false")

    def src(table: str) -> str:
        return f"read_parquet('{(raw / table).as_posix()}/part-*.parquet')"

    stats: dict[str, object] = {}

    # ---- platforms and stores
    t = step("plataformas e lojas")
    con.execute(f"CREATE OR REPLACE TABLE plataformas AS SELECT id, name FROM {src('plataformas')}")
    con.execute(f"""
        CREATE OR REPLACE TABLE loja_plataforma AS
        SELECT store_id, arg_max(platform_id, n) AS platform_id
        FROM (SELECT store_id, platform_id, COUNT(*) AS n FROM {src('feeds')}
              WHERE platform_id IS NOT NULL GROUP BY ALL)
        GROUP BY store_id""")
    lojas = con.execute(f"SELECT * FROM {src('lojas')} WHERE source_type_id = 1").df()
    lojas["name_raw"] = lojas["name"]
    lojas["name"] = lojas["name"].map(repair)
    lojas["name_flag"] = "ok"
    needs = lojas["name_raw"].fillna("").str.contains(MOJIBAKE.pattern + "|" + ENTITY.pattern, regex=True, case=False)
    lojas.loc[needs & (lojas["name"] != lojas["name_raw"].str.strip()), "name_flag"] = "reparado"
    lojas.loc[lojas["name"].fillna("").str.contains("\ufffd"), "name_flag"] = "caractere_perdido"
    lojas["slug_raw"] = lojas["slug"]
    lojas["slug"] = lojas["name"].map(slugify)
    con.register("lojas_df", lojas)
    con.execute("""
        CREATE OR REPLACE TABLE lojas AS
        SELECT l.id, l.name, l.name_flag, l.name_raw, l.url, l.slug, l.slug_raw, l.active,
               l.creation_date AS created_at, lp.platform_id
        FROM lojas_df l LEFT JOIN loja_plataforma lp ON lp.store_id = l.id""")
    con.unregister("lojas_df")
    done(t, con, "lojas")

    # ---- spec-sheet keys
    t = step("caracteristicas")
    con.execute(f"CREATE OR REPLACE TABLE caracteristicas AS SELECT id, key, question FROM {src('caracteristicas')}")
    done(t, con, "caracteristicas")

    # ---- products (one pass: names that need repair are fixed first, then joined in)
    t = step("produtos")
    print("   1/3 procurando nomes com texto embaralhado ou códigos HTML…", flush=True)
    broken = con.execute(f"""SELECT id, name AS name_raw FROM {src('produtos')}
                             WHERE regexp_matches(name, '[ÃÂ][^A-Za-zÀ-ÿ0-9\\s]|â€|&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);')""").df()
    print(f"   2/3 reparando {len(broken):,} nomes…", flush=True)
    broken["name"] = broken["name_raw"].map(repair)
    con.register("broken_df", broken[["id", "name"]])
    con.execute("CREATE OR REPLACE TABLE nomes_reparados AS SELECT * FROM broken_df")
    con.unregister("broken_df")
    print("   3/3 gravando a tabela de produtos (114 mi linhas; é a etapa mais longa)…", flush=True)
    con.execute(f"CREATE OR REPLACE MACRO norm_avail(a) AS map_extract(MAP {{{', '.join(f'{k!r}: {v!r}' for k, v in AVAILABILITY.items())}}}, lower(trim(a)))[1]")
    con.execute(f"""
        CREATE OR REPLACE TABLE produtos AS
        SELECT p.id, p.store_id, p.collected_at,
               COALESCE(r.name, p.name) AS name,
               CASE WHEN r.id IS NOT NULL AND r.name <> p.name THEN 'reparado'
                    WHEN contains(p.name, chr(65533)) THEN 'caractere_perdido' ELSE 'ok' END AS name_flag,
               p.name AS name_raw, p.url, p.brand,
               p.availability AS availability_raw,
               norm_avail(p.availability) AS availability,
               p.store_id NOT IN {UNRELIABLE_AVAILABILITY_STORES} AS availability_reliable,
               p.price AS price_raw,
               CASE WHEN p.price IS NULL OR p.price = 0 OR p.price >= {PRICE_INACTIVE} THEN NULL ELSE p.price END AS price,
               CASE WHEN p.price IS NULL THEN 'vazio' WHEN p.price = 0 THEN 'zero'
                    WHEN p.price >= {PRICE_INACTIVE} THEN 'inativo_99999' ELSE 'ok' END AS price_flag,
               p.group_id, p.group_rule, p.group_rule_original,
               p.image_hash, p.image_width, p.image_height, p.image_is_generic
        FROM {src('produtos')} p
        LEFT JOIN nomes_reparados r ON r.id = p.id
        WHERE p.store_id IN (SELECT id FROM lojas)""")
    stats["produtos_nomes_reparados"] = len(broken)
    done(t, con, "produtos")

    # ---- groups
    t = step("grupos")
    con.execute(f"""
        CREATE OR REPLACE TABLE grupo_stats AS
        SELECT group_id, COUNT(*) AS offers, COUNT(DISTINCT store_id) AS stores,
               COUNT(DISTINCT lower(trim(brand))) FILTER (WHERE trim(brand) <> '') AS brands
        FROM produtos WHERE group_id IS NOT NULL GROUP BY group_id""")
    con.execute(f"""
        CREATE OR REPLACE TABLE grupos AS
        SELECT g.id, g.short_name, g.long_name, g.creation_date AS created_at,
               g.last_change, g.last_change = TIMESTAMP '{FIXED_GROUP_DATE}' AS last_change_is_bulk_date,
               g.active,
               COALESCE(s.offers, 0) AS offers, COALESCE(s.stores, 0) AS stores, COALESCE(s.brands, 0) AS brands,
               CASE WHEN s.offers > {BIG_GROUP} THEN 'grande_demais'
                    WHEN s.brands > {MANY_BRANDS} THEN 'muitas_marcas'
                    WHEN s.offers IS NULL THEN 'sem_ofertas' ELSE 'ok' END AS group_flag
        FROM {src('grupos')} g LEFT JOIN grupo_stats s ON s.group_id = g.id""")
    done(t, con, "grupos")

    # ---- spec sheet
    t = step("ficha")
    removed = ", ".join(f"'{b}'" for b in REMOVED_BRANDS)
    con.execute(f"""
        CREATE OR REPLACE TABLE ficha AS
        SELECT f.id, f.product_id, f.position, f.key,
               CASE WHEN lower(trim(f.value)) IN ('', 'null', 'nulo', '-', 'n/a', 'na', 'none') THEN NULL
                    ELSE f.value END AS value,
               f.value AS value_raw
        FROM {src('ficha')} f
        LEFT JOIN produtos p ON p.id = f.product_id
        WHERE NOT (regexp_matches(f.key, '{SAC_KEY_PATTERN}')
                   AND lower(trim(COALESCE(p.brand, ''))) IN ({removed}))""")
    stats["ficha_linhas_removidas_por_pedido_das_marcas"] = con.execute(
        f"SELECT COUNT(*) FROM {src('ficha')}").fetchone()[0] - con.execute("SELECT COUNT(*) FROM ficha").fetchone()[0]
    done(t, con, "ficha")

    # ---- identifiers (EAN, ISBN, SKU…): one row per code, classified
    t = step("eans")
    con.execute("""
        CREATE OR REPLACE MACRO gtin_ok(s) AS
        (10 - (list_sum(list_transform(range(1, 14),
               i -> CAST(substr(lpad(s, 14, '0'), i, 1) AS INTEGER) * CASE WHEN i % 2 = 1 THEN 3 ELSE 1 END)) % 10)) % 10
        = CAST(substr(lpad(s, 14, '0'), 14, 1) AS INTEGER)""")
    con.execute(f"""
        CREATE OR REPLACE TABLE eans AS
        WITH split AS (
            SELECT e.id, e.product_id, e.value AS value_raw, e.ignored_in_grouping,
                   trim(u.code) AS code, u.idx AS code_index
            FROM {src('eans')} e,
                 LATERAL (SELECT unnest(string_split(COALESCE(e.value, ''), ',')) AS code,
                                 generate_subscripts(string_split(COALESCE(e.value, ''), ','), 1) AS idx) u)
        SELECT id, product_id, code_index, code, value_raw, ignored_in_grouping,
               CASE
                 WHEN code = '' OR lower(code) IN ('null', 'sem gtin', '-') THEN 'vazio'
                 WHEN regexp_matches(code, '^[0-9]+([.,][0-9]+)?[eE]\\+[0-9]{{1,2}}$|^[0-9][.,][0-9]+[eE][0-9]{{1,2}}$') THEN 'notacao_cientifica'
                 WHEN regexp_matches(code, '^[0-9]+$') AND length(code) IN (8, 12, 13, 14)
                      THEN CASE WHEN gtin_ok(code) THEN 'gtin_valido' ELSE 'gtin_digito_errado' END
                 WHEN regexp_matches(code, '^[0-9]+$') AND length(code) < 8 THEN 'numero_curto'
                 WHEN regexp_matches(code, '^[0-9]+$') THEN 'numero_outro_tamanho'
                 WHEN regexp_matches(code, '[A-Za-zÀ-ú]{{3,}}\\s+[A-Za-zÀ-ú]') THEN 'texto'
                 ELSE 'codigo_alfanumerico'
               END AS code_type
        FROM split""")
    # where the code came from: the spec-sheet key holding the same value for the same product
    con.execute("""
        CREATE OR REPLACE TABLE eans AS
        SELECT e.*, k.key AS source_key
        FROM eans e
        LEFT JOIN (SELECT product_id, trim(value) AS code, min(key) AS key FROM ficha
                   WHERE regexp_matches(key, '(?i)(c[oó]digo de barras|isbn|ean|gtin|upc)')
                   GROUP BY ALL) k
          ON k.product_id = e.product_id AND k.code = e.code""")
    done(t, con, "eans")

    # ---- categories
    t = step("categorias")
    con.execute(f"""
        CREATE OR REPLACE TABLE categorias AS
        SELECT c.id, c.product_id, c.level, c.category, c.category_normalized,
               CASE WHEN c.category_normalized IS NOT NULL THEN 'limpa_2020' ELSE 'original' END AS category_origin,
               CASE WHEN c.level > 10 THEN 'nivel_alto'
                    WHEN regexp_matches(lower(trim(c.category)), '{CATEGORY_NOISE}') THEN 'codigo_ou_ruido'
                    WHEN length(trim(c.category)) <= 1 THEN 'curta_demais'
                    ELSE 'ok' END AS category_flag
        FROM {src('categorias')} c""")
    done(t, con, "categorias")

    # ---- write
    t = step("gravando Parquet")
    small = ["plataformas", "lojas", "caracteristicas", "grupos"]
    for name in small:
        con.execute(f"COPY {name} TO '{(out / name).as_posix()}.parquet' (FORMAT parquet, COMPRESSION zstd)")
    order = {"produtos": "id", "ficha": "product_id, position", "eans": "product_id, code_index",
             "categorias": "product_id, level"}
    for name, key in order.items():
        target = out / name
        if target.exists():
            for old in target.glob("*.parquet"):
                old.unlink()
        con.execute(f"""COPY (SELECT * FROM {name} ORDER BY {key}) TO '{target.as_posix()}'
                        (FORMAT parquet, COMPRESSION zstd, PER_THREAD_OUTPUT true, OVERWRITE_OR_IGNORE true)""")
    done(t, con)

    # ---- stats for validate.py and the README
    q = lambda sql: con.execute(sql).fetchall()
    for name in small + list(order):
        stats[f"linhas_{name}"] = q(f"SELECT COUNT(*) FROM {name}")[0][0]
    stats["price_flag"] = dict(q("SELECT price_flag, COUNT(*) FROM produtos GROUP BY 1"))
    stats["availability"] = dict(q("SELECT COALESCE(availability, 'vazio'), COUNT(*) FROM produtos GROUP BY 1"))
    stats["name_flag"] = dict(q("SELECT name_flag, COUNT(*) FROM produtos GROUP BY 1"))
    stats["group_flag"] = dict(q("SELECT group_flag, COUNT(*) FROM grupos GROUP BY 1"))
    stats["code_type"] = dict(q("SELECT code_type, COUNT(*) FROM eans GROUP BY 1"))
    stats["category_origin"] = dict(q("SELECT category_origin, COUNT(*) FROM categorias GROUP BY 1"))
    stats["category_flag"] = dict(q("SELECT category_flag, COUNT(*) FROM categorias GROUP BY 1"))
    stats["lojas_name_flag"] = dict(q("SELECT name_flag, COUNT(*) FROM lojas GROUP BY 1"))
    stats["lojas_com_plataforma"] = q("SELECT COUNT(*) FROM lojas WHERE platform_id IS NOT NULL")[0][0]
    (out / "build_stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    con.close()
    print(json.dumps(stats, ensure_ascii=False, indent=2, default=str))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", required=True, type=Path)
    parser.add_argument("--out", default=Path("data"), type=Path)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--memory", default="8GB", help="DuckDB memory limit (it spills to disk above this)")
    args = parser.parse_args()
    began = time.time()
    build(args.raw, args.out, args.threads, args.memory)
    print(f"Done in {(time.time() - began) / 60:,.1f} min. Delete {args.out / '_tmp'} afterwards to free disk.")


if __name__ == "__main__":
    main()

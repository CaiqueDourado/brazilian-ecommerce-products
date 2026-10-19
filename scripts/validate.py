"""Check the built catalog (output of build.py) before publishing. Exits with code 1 on any failure.

Usage:  python scripts\\validate.py --data D:\\catalogo_build
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import duckdb

FAILS: list[str] = []


def check(ok: bool, message: str) -> None:
    print(("OK   " if ok else "FAIL ") + message)
    if not ok:
        FAILS.append(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--sample", action="store_true", help="check the GitHub sample (CSV) instead of the full build")
    args = parser.parse_args()
    d = args.data.as_posix()
    stats = None if args.sample else json.loads((args.data / "build_stats.json").read_text(encoding="utf-8"))
    con = duckdb.connect()

    def one(sql: str):
        return con.execute(sql).fetchone()[0]

    def t(name: str) -> str:
        if args.sample:
            return f"read_csv_auto('{d}/{name}.csv', header=true)"
        p = args.data / name
        return f"read_parquet('{d}/{name}/*.parquet')" if p.is_dir() else f"read_parquet('{d}/{name}.parquet')"

    # row counts match the build
    for name in ["plataformas", "lojas", "caracteristicas", "grupos", "produtos", "ficha", "eans", "categorias"]:
        n = one(f"SELECT COUNT(*) FROM {t(name)}")
        check(n > 0 if args.sample else n == stats[f"linhas_{name}"], f"{name}: {n:,} linhas")

    # keys
    for name in ["plataformas", "lojas", "grupos", "produtos", "caracteristicas"]:
        check(one(f"SELECT COUNT(*) - COUNT(DISTINCT id) FROM {t(name)}") == 0, f"{name}.id único")
    check(one(f"SELECT COUNT(*) FROM {t('produtos')} p LEFT JOIN {t('lojas')} l ON l.id = p.store_id WHERE l.id IS NULL") == 0,
          "toda oferta aponta para uma loja existente")
    check(one(f"SELECT COUNT(*) FROM {t('lojas')} l LEFT JOIN {t('plataformas')} p ON p.id = l.platform_id "
              "WHERE l.platform_id IS NOT NULL AND p.id IS NULL") == 0, "plataforma das lojas existe")
    orphans = one(f"SELECT COUNT(*) FROM {t('produtos')} p LEFT JOIN {t('grupos')} g ON g.id = p.group_id "
                  "WHERE p.group_id IS NOT NULL AND g.id IS NULL")
    check(orphans == 0, f"group_id das ofertas existe em grupos ({orphans:,} órfãos)")

    # cleaning rules
    check(one(f"SELECT COUNT(*) FROM {t('produtos')} WHERE price = 0 OR price >= 99999") == 0,
          "price sem zero e sem 99999")
    check(one(f"SELECT COUNT(*) FROM {t('produtos')} WHERE price_flag <> 'ok' AND price IS NOT NULL") == 0,
          "price vazio sempre que price_flag <> ok")
    check(one(f"SELECT COUNT(*) FROM {t('produtos')} WHERE availability NOT IN ('disponivel', 'indisponivel')") == 0,
          "availability só disponivel/indisponivel/vazio")
    check(one(f"SELECT COUNT(*) FROM {t('produtos')} WHERE name IS NULL AND name_raw IS NOT NULL") == 0,
          "reparo de nome nunca apaga nome")
    check(one(f"SELECT COUNT(*) FROM {t('ficha')} WHERE lower(trim(value)) IN ('', 'null')") == 0,
          "ficha sem '' nem 'Null'")
    check(one(f"SELECT COUNT(*) FROM {t('eans')} WHERE code_type = 'gtin_valido' AND NOT regexp_matches(code, '^[0-9]{{8,14}}$')") == 0,
          "gtin_valido só com dígitos")
    check(one(f"SELECT COUNT(*) FROM {t('categorias')} WHERE category_origin NOT IN ('limpa_2020', 'original')") == 0,
          "category_origin com valores conhecidos")

    # nothing private leaked into stores or feeds
    check(one(f"SELECT COUNT(*) FROM {t('lojas')} WHERE regexp_matches(COALESCE(url, ''), '(?i)connectid|awinaffid|affid=')") == 0,
          "URLs de lojas sem IDs de afiliado")

    # sanity of proportions (catch a broken step, not exact numbers)
    if args.sample:
        print(f"\n{len(FAILS)} falha(s)")
        sys.exit(1 if FAILS else 0)
    total = stats["linhas_produtos"]
    check(stats["price_flag"]["ok"] / total > 0.6, "mais de 60% das ofertas com preço")
    check(stats["code_type"]["gtin_valido"] / stats["linhas_eans"] > 0.7, "mais de 70% dos códigos são GTIN válidos")
    check(stats["name_flag"].get("reparado", 0) / total < 0.02, "menos de 2% dos nomes reparados")


    print(f"\n{len(FAILS)} falha(s)")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()

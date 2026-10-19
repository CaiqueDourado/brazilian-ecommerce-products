"""Profile the raw export (the Parquet files written by export_sqlserver.py) without loading it all.

Reads each table file by file, only the needed columns, and writes small CSV summaries to
<raw>/_perfil/. Those CSVs are what guide the cleaning rules in build.py and the numbers in the
data dictionary; they are small enough to send around (a few MB in total).

Usage (Windows, PowerShell):
    python scripts\\profile_raw.py --raw D:\\catalogo_raw
    python scripts\\profile_raw.py --raw D:\\catalogo_raw --tables eans categorias
"""

from __future__ import annotations

import argparse
import time
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

EMPTY = {"", "null", "nulo", "-", "n/a", "na", "none", "não informado", "nao informado"}


def files(raw: Path, table: str) -> list[Path]:
    return sorted((raw / table).glob("part-*.parquet"))


def read(path: Path, columns: list[str]) -> pd.DataFrame:
    return pq.read_table(path, columns=columns).to_pandas()


def save(out: Path, name: str, frame: pd.DataFrame) -> None:
    frame.to_csv(out / name, index=False, encoding="utf-8")
    print(f"   _perfil/{name}: {len(frame):,} rows")


def counter_frame(counter: Counter, key: str, top: int | None = None) -> pd.DataFrame:
    items = counter.most_common(top)
    return pd.DataFrame(items, columns=[key, "rows"])


# ---------- GTIN check digit (vectorized) ----------

def gtin_class(values: pd.Series) -> pd.Series:
    """Classify identifier strings: valid GTIN (8/12/13/14 digits with a correct check digit),
    wrong check digit, scientific notation (spreadsheet damage), short number, alphanumeric code,
    free text or empty."""
    s = values.fillna("").astype(str).str.strip()
    out = pd.Series("codigo_alfanumerico", index=s.index, dtype=object)
    out[s.str.lower().isin(EMPTY)] = "vazio"
    out[s.str.fullmatch(r"\d+([.,]\d+)?[eE]\+?\d+")] = "notacao_cientifica"
    out[s.str.contains(r"[A-Za-zÀ-ú]{3,}\s+[A-Za-zÀ-ú]", regex=True)] = "texto"
    digits = s.str.fullmatch(r"\d+")
    length = s.str.len()
    out[digits & (length < 8)] = "numero_curto"
    out[digits & (length > 14)] = "numero_longo"
    candidate = digits & length.isin([8, 12, 13, 14])
    out[digits & (length.between(8, 14)) & ~candidate] = "numero_8_a_14_sem_padrao"
    if candidate.any():
        padded = s[candidate].str.zfill(14)
        matrix = np.frombuffer("".join(padded).encode("ascii"), dtype=np.uint8).reshape(-1, 14) - 48
        weights = np.array([3, 1] * 6 + [3], dtype=np.int64)  # positions 1..13 of a GTIN-14
        check = (10 - (matrix[:, :13] @ weights) % 10) % 10
        ok = check == matrix[:, 13]
        out[candidate] = np.where(ok, "gtin_valido", "gtin_digito_errado")
    return out


# ---------- tables ----------

def produtos(raw: Path, out: Path) -> None:
    by_store, by_year, rules, rules_original, availability = Counter(), Counter(), Counter(), Counter(), Counter()
    group_sizes = np.zeros(1, dtype=np.int64)
    totals = Counter()
    for path in files(raw, "produtos"):
        df = read(path, ["store_id", "collected_at", "name", "brand", "availability", "price", "group_id",
                         "group_rule", "group_rule_original", "image_hash", "image_is_generic"])
        totals["rows"] += len(df)
        price = df["price"]
        totals["price_null"] += int(price.isna().sum())
        totals["price_zero"] += int((price == 0).sum())
        totals["price_99999_or_more"] += int((price >= 99999).sum())
        totals["brand_filled"] += int(df["brand"].fillna("").str.strip().ne("").sum())
        totals["image_hash_filled"] += int(df["image_hash"].notna().sum())
        totals["image_is_generic"] += int(df["image_is_generic"].fillna(False).sum())
        totals["name_mojibake"] += int(df["name"].str.contains("Ã|Â", regex=True, na=False).sum())
        totals["name_replacement_char"] += int(df["name"].str.contains("\ufffd", na=False).sum())
        totals["name_html_entity"] += int(df["name"].str.contains(r"&[a-zA-Z]+;|&#\d+;", regex=True, na=False).sum())
        totals["group_null"] += int(df["group_id"].isna().sum())
        by_store.update(df["store_id"].value_counts().to_dict())
        by_year.update(df["collected_at"].dt.year.value_counts().to_dict())
        rules.update(df["group_rule"].fillna("(vazio)").value_counts().to_dict())
        rules_original.update(df["group_rule_original"].fillna("(vazio)").value_counts().to_dict())
        availability.update(df["availability"].fillna("(vazio)").value_counts().head(200).to_dict())
        ids = df["group_id"].dropna().astype(np.int64).to_numpy()
        if len(ids):
            counts = np.bincount(ids)
            if len(counts) > len(group_sizes):
                group_sizes = np.pad(group_sizes, (0, len(counts) - len(group_sizes)))
            group_sizes[: len(counts)] += counts
        print(f"   produtos {totals['rows']:,}", end="\r", flush=True)
    print()
    save(out, "produtos_totais.csv", pd.DataFrame(sorted(totals.items()), columns=["metrica", "valor"]))
    save(out, "produtos_por_loja.csv", counter_frame(by_store, "store_id"))
    save(out, "produtos_por_ano.csv", pd.DataFrame(sorted(by_year.items()), columns=["ano", "rows"]))
    save(out, "produtos_regras.csv", pd.concat([
        counter_frame(rules, "regra").assign(campo="group_rule"),
        counter_frame(rules_original, "regra").assign(campo="group_rule_original")]))
    save(out, "produtos_disponibilidade.csv", counter_frame(availability, "availability", 200))
    sizes = group_sizes[group_sizes > 0]
    bins = [1, 2, 3, 6, 11, 51, 101, 501, 1001, 5001, 10**12]
    labels = ["1", "2", "3-5", "6-10", "11-50", "51-100", "101-500", "501-1000", "1001-5000", "5001+"]
    dist = pd.cut(pd.Series(sizes), bins=bins, labels=labels, right=False).value_counts().reindex(labels)
    save(out, "grupos_tamanho.csv", pd.DataFrame({"produtos_no_grupo": labels, "grupos": dist.values}))
    top = np.argsort(group_sizes)[::-1][:300]
    save(out, "grupos_maiores.csv", pd.DataFrame({"group_id": top, "produtos": group_sizes[top]}))


def ficha(raw: Path, out: Path) -> None:
    keys, empty_by_key = Counter(), Counter()
    barcode_classes, totals = Counter(), Counter()
    for path in files(raw, "ficha"):
        df = read(path, ["product_id", "key", "value"])
        totals["rows"] += len(df)
        totals["products_in_file"] += df["product_id"].nunique()  # files split by id, so this sums well
        empty = df["value"].fillna("").str.strip().str.lower().isin(EMPTY)
        totals["empty_values"] += int(empty.sum())
        keys.update(df["key"].value_counts().to_dict())
        empty_by_key.update(df.loc[empty, "key"].value_counts().to_dict())
        barcode = df["key"].isin(["Código de Barras", "EAN", "Ean", "GTIN", "Isbn", "ISBN"])
        barcode_classes.update(gtin_class(df.loc[barcode, "value"]).value_counts().to_dict())
        print(f"   ficha {totals['rows']:,}", end="\r", flush=True)
    print()
    save(out, "ficha_totais.csv", pd.DataFrame(sorted(totals.items()), columns=["metrica", "valor"]))
    frame = counter_frame(keys, "key")
    frame["vazios"] = frame["key"].map(empty_by_key).fillna(0).astype(int)
    save(out, "ficha_chaves.csv", frame)
    save(out, "ficha_codigo_barras_classes.csv", counter_frame(barcode_classes, "classe"))


def eans(raw: Path, out: Path) -> None:
    keys, classes, ignored, totals = Counter(), Counter(), Counter(), Counter()
    examples: dict[str, list[str]] = {}
    for path in files(raw, "eans"):
        df = read(path, ["key", "value", "ignored_in_grouping"])
        totals["rows"] += len(df)
        keys.update(df["key"].fillna("(vazio)").value_counts().to_dict())
        ignored.update(df["ignored_in_grouping"].map({True: "sim", False: "nao"}).fillna("(vazio)").value_counts().to_dict())
        kind = gtin_class(df["value"])
        classes.update(kind.value_counts().to_dict())
        for name, group in df["value"].groupby(kind):
            bucket = examples.setdefault(name, [])
            if len(bucket) < 30:
                bucket += group.sample(min(5, len(group)), random_state=0).tolist()
        print(f"   eans {totals['rows']:,}", end="\r", flush=True)
    print()
    save(out, "eans_chaves.csv", counter_frame(keys, "key"))
    save(out, "eans_ignorados.csv", counter_frame(ignored, "ignored_in_grouping"))
    frame = counter_frame(classes, "classe")
    frame["exemplos"] = frame["classe"].map(lambda c: " | ".join(map(str, examples.get(c, [])[:15])))
    save(out, "eans_classes.csv", frame)


def categorias(raw: Path, out: Path) -> None:
    levels, names, per_file, depth = Counter(), Counter(), [], Counter()
    for path in files(raw, "categorias"):
        df = read(path, ["id", "product_id", "level", "category", "category_normalized"])
        levels.update(df["level"].value_counts().to_dict())
        names.update(df["category"].value_counts().head(5000).to_dict())
        depth.update(df.groupby("product_id")["level"].max().value_counts().to_dict())
        per_file.append({"primeiro_id": int(df["id"].min()), "ultimo_id": int(df["id"].max()),
                         "produto_min": int(df["product_id"].min()), "produto_max": int(df["product_id"].max()),
                         "linhas": len(df), "normalizadas": int(df["category_normalized"].notna().sum()),
                         "produtos": int(df["product_id"].nunique())})
        print(f"   categorias {sum(p['linhas'] for p in per_file):,}", end="\r", flush=True)
    print()
    save(out, "categorias_niveis.csv", pd.DataFrame(sorted(levels.items()), columns=["level", "rows"]))
    save(out, "categorias_profundidade.csv", pd.DataFrame(sorted(depth.items()), columns=["nivel_maximo", "produtos"]))
    save(out, "categorias_top.csv", counter_frame(names, "category", 20000))
    save(out, "categorias_por_arquivo.csv", pd.DataFrame(per_file))


TABLES = {"produtos": produtos, "ficha": ficha, "eans": eans, "categorias": categorias}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", required=True, type=Path)
    parser.add_argument("--tables", nargs="*", default=list(TABLES), choices=list(TABLES))
    args = parser.parse_args()
    out = args.raw / "_perfil"
    out.mkdir(exist_ok=True)
    for name in args.tables:
        began = time.time()
        print(f"== {name}")
        TABLES[name](args.raw, out)
        print(f"   {time.time() - began:,.0f} s")


if __name__ == "__main__":
    main()

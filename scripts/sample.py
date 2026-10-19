"""Make the small sample that goes to GitHub (the full catalog goes to Kaggle).

The sample is coherent: it picks whole product groups, then takes every offer of those groups and
all their spec-sheet rows, codes and categories, so joins work exactly as in the full data.
Small tables (plataformas, lojas, caracteristicas) go complete.

Groups are drawn in three slices so the sample shows the interesting cases:
    ordinary groups with 2+ stores, groups flagged 'grande_demais'/'muitas_marcas' (capped), and
    single-offer groups.

Usage:  python scripts\\sample.py --data D:\\catalogo_build --out sample
"""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--out", default=Path("sample"), type=Path)
    parser.add_argument("--groups", type=int, default=3000, help="ordinary groups with 2+ stores")
    parser.add_argument("--seed", type=float, default=0.42)
    args = parser.parse_args()
    d, out = args.data.as_posix(), args.out
    out.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    con.execute(f"SELECT setseed({args.seed})")

    def t(name: str) -> str:
        return f"read_parquet('{d}/{name}/*.parquet')" if (args.data / name).is_dir() else f"read_parquet('{d}/{name}.parquet')"

    con.execute(f"""
        CREATE TABLE chosen AS
        (SELECT id FROM {t('grupos')} WHERE group_flag = 'ok' AND stores >= 2 AND offers <= 50
         ORDER BY random() LIMIT {args.groups})
        UNION
        (SELECT id FROM {t('grupos')} WHERE group_flag IN ('muitas_marcas') ORDER BY random() LIMIT 30)
        UNION
        (SELECT id FROM {t('grupos')} WHERE group_flag = 'ok' AND offers = 1 ORDER BY random() LIMIT {args.groups // 3})""")
    con.execute(f"CREATE TABLE offers AS SELECT p.* FROM {t('produtos')} p JOIN chosen c ON c.id = p.group_id")

    for name in ["plataformas", "lojas", "caracteristicas"]:
        con.execute(f"COPY (SELECT * FROM {t(name)}) TO '{(out / name).as_posix()}.csv' (HEADER, DELIMITER ',')")
    con.execute(f"COPY (SELECT g.* FROM {t('grupos')} g JOIN chosen c ON c.id = g.id ORDER BY g.id) "
                f"TO '{(out / 'grupos').as_posix()}.csv' (HEADER)")
    con.execute(f"COPY (SELECT * FROM offers ORDER BY id) TO '{(out / 'produtos').as_posix()}.csv' (HEADER)")
    for name, key in [("ficha", "product_id, position"), ("eans", "product_id, code_index"), ("categorias", "product_id, level")]:
        con.execute(f"COPY (SELECT x.* FROM {t(name)} x JOIN offers o ON o.id = x.product_id ORDER BY {key}) "
                    f"TO '{(out / name).as_posix()}.csv' (HEADER)")

    for f in sorted(out.glob("*.csv")):
        rows = con.execute(f"SELECT COUNT(*) FROM read_csv_auto('{f.as_posix()}')").fetchone()[0]
        print(f"{f.name:22} {rows:>10,} linhas {f.stat().st_size / 1e6:8.1f} MB")


if __name__ == "__main__":
    main()

"""Export the product catalog from the author's SQL Server into Parquet files (raw layer).

Runs on the machine that has the database. Reads each table in id order, in blocks
(keyset pagination: WHERE id > last ORDER BY id), and writes one Parquet file per block:

    <out>/<table>/part-<first id>-<last id>.parquet

The export can be stopped at any time (Ctrl+C) and resumed: the next run starts after the
highest id already written. Cleaning (empty prices, noise in categories, new slugs...) is NOT
done here; it happens later in scripts/build.py, so this layer stays a faithful copy.

Usage (Windows, PowerShell):
    python -m pip install --user pyodbc pyarrow
    python scripts\\export_sqlserver.py --out D:\\catalogo_raw                 # every table
    python scripts\\export_sqlserver.py --out D:\\catalogo_raw --tables lojas grupos
    python scripts\\export_sqlserver.py --out D:\\catalogo_raw --status        # progress only

Connection: Windows authentication (no password in the script). Change --server if the
SQL Server is not "localhost" (for example .\\SQLEXPRESS).
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

DL = "nlp_data_lake.dbo"
CAT = "nlp_data_lake_CrawlerNewProductDetailCategoria.dbo"
MGMT = "nlp_management.dbo"


@dataclass
class Table:
    name: str
    source: str              # schema-qualified table
    columns: list[tuple[str, str, pa.DataType]]  # (SQL expression, output name, Arrow type)
    block: int = 500_000

    @property
    def select(self) -> str:
        return ", ".join(f"{expr} AS [{name}]" for expr, name, _ in self.columns)

    @property
    def schema(self) -> pa.Schema:
        return pa.schema([(name, kind) for _, name, kind in self.columns])


S, I, B, F, T = pa.string(), pa.int64(), pa.bool_(), pa.float64(), pa.timestamp("ms")

TABLES = [
    Table("lojas", f"{MGMT}.Source", [
        ("id", "id", I), ("name", "name", S), ("url", "url", S), ("shortName", "short_name", S),
        ("active", "active", B), ("slug", "slug", S), ("creationDate", "creation_date", T),
        ("idSourceType", "source_type_id", I),
    ]),
    Table("caracteristicas", f"{DL}.CrawlerNewProductDetailCaracteristicaTitulo", [
        ("id", "id", I), ("caracteristica", "key", S), ("titulo", "question", S),
        ("titulo_wiki2buy", "question_template", S),
    ]),
    Table("grupos", f"{DL}.ProductGroup", [
        ("id", "id", I), ("shortName", "short_name", S), ("longName", "long_name", S),
        ("creationDate", "creation_date", T), ("lastPriceInsertedOrProductChanged", "last_change", T),
        ("active", "active", B),
    ]),
    Table("produtos", f"{DL}.CrawlerNewProductDetail", [
        ("id", "id", I), ("sourceId", "store_id", I), ("creationDate", "collected_at", T),
        ("productName", "name", S), ("productUrl", "url", S), ("feed_brand", "brand", S),
        ("feed_availability", "availability", S), ("CAST(productPrice AS float)", "price", F),
        ("productGroupId", "group_id", I), ("productGroupRelationType", "group_rule", S),
        ("productGroupRelationValue", "group_rule_value", S),
        ("productGroupRelationTypeOriginal", "group_rule_original", S),
        ("productImage_hash_Imagio_ComputeHash", "image_hash", S),
        ("productImage_width", "image_width", I), ("productImage_height", "image_height", I),
        ("productImage_sem_imagem_desconsiderar", "image_is_generic", B),
    ]),
    Table("ficha", f"{DL}.CrawlerNewProductDetailCaracteristica", [
        ("id", "id", I), ("idCrawlerNewProductDetail", "product_id", I), ("pos", "position", I),
        ("chave", "key", S), ("valor", "value", S),
    ], block=2_000_000),
    Table("eans", f"{DL}.CrawlerNewProductDetailEAN", [
        ("id", "id", I), ("idCrawlerNewProductDetail", "product_id", I), ("chave", "key", S),
        ("valor", "value", S), ("desconsiderar_nos_agrupamentos", "ignored_in_grouping", B),
    ], block=2_000_000),
    Table("categorias", f"{CAT}.CrawlerNewProductDetailCategoria", [
        ("id", "id", I), ("idCrawlerNewProductDetail", "product_id", I), ("pos", "level", I),
        ("categoria", "category", S), ("categoria_normalizada", "category_normalized", S),
    ], block=2_000_000),
    # Second round (18/10/2026): platform map and the matches the grouping refused.
    Table("plataformas", f"{MGMT}.Platform", [
        ("id", "id", I), ("name", "name", S),
    ]),
    # The feed URL is left out on purpose: affiliate feeds carry the account id (connectid) in it.
    Table("feeds", f"{DL}.CrawlerFeed", [
        ("id", "id", I), ("sourceId", "store_id", I), ("platformId", "platform_id", I),
        ("active", "active", B), ("creationDate", "creation_date", T), ("protocol", "protocol", S),
        ("charset", "charset", S), ("lastCheck", "last_check", T),
        ("lastCheckNumProdutos", "last_check_products", I), ("checkStatus", "check_status", S),
    ], block=2_000_000),
    Table("agrupamentos_recusados", f"{DL}.temp_agrupamentos_ignorados", [
        ("id", "id", I), ("productName_origem", "name_a", S),
        ("productName_tokenizada_origem", "name_a_tokens", S), ("productName", "name_b", S),
        ("productName_tokenizada", "name_b_tokens", S), ("tipo", "rule", S), ("valor", "rule_value", S),
        ("creationDate", "created_at", T),
    ], block=2_000_000),
]
BY_NAME = {t.name: t for t in TABLES}


BROKEN_TEXT = {"values": 0}


def decode_utf16(raw: bytes | None) -> str | None:
    """nvarchar comes as UTF-16. Some scraped texts hold half of an emoji (a lone surrogate), which
    is invalid UTF-16 and makes pyodbc fail; those characters become U+FFFD and are counted."""
    if raw is None:
        return None
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        BROKEN_TEXT["values"] += 1
        return raw.decode("utf-16-le", errors="replace")


def connect(server: str):
    import pyodbc

    connection = pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};Trusted_Connection=yes",
        autocommit=True,
    )
    for sql_type in (pyodbc.SQL_WVARCHAR, pyodbc.SQL_WCHAR, pyodbc.SQL_WLONGVARCHAR):
        connection.add_output_converter(sql_type, decode_utf16)
    return connection


def last_id(folder: Path) -> int:
    """Highest id already exported, read from the file names (part-<first>-<last>.parquet)."""
    ends = [int(p.stem.rsplit("-", 1)[1]) for p in folder.glob("part-*.parquet")]
    return max(ends, default=0)


def estimated_rows(cursor, table: Table) -> int:
    """Row count from catalog metadata: instant, unlike COUNT(*) on hundreds of millions of rows."""
    db, schema, name = table.source.split(".")
    cursor.execute(
        f"SELECT SUM(p.rows) FROM {db}.sys.partitions p JOIN {db}.sys.objects o ON o.object_id = p.object_id "
        f"WHERE o.name = ? AND p.index_id IN (0, 1)", name)
    return int(cursor.fetchone()[0] or 0)


def to_arrow(rows: list, table: Table) -> pa.Table:
    columns = list(zip(*rows)) if rows else [[] for _ in table.columns]
    arrays = [pa.array(list(values), type=kind) for values, (_, _, kind) in zip(columns, table.columns)]
    return pa.Table.from_arrays(arrays, schema=table.schema)


def export(cursor, table: Table, out: Path) -> None:
    folder = out / table.name
    folder.mkdir(parents=True, exist_ok=True)
    start = last_id(folder)
    total = estimated_rows(cursor, table)
    done = sum(pq.ParquetFile(p).metadata.num_rows for p in folder.glob("part-*.parquet"))
    print(f"== {table.name}: about {total:,} rows, {done:,} already exported, resuming after id {start:,}")
    query = (f"SELECT TOP ({table.block}) {table.select} FROM {table.source} WITH (NOLOCK) "
             f"WHERE id > ? ORDER BY id")
    began = time.time()
    exported = 0
    while True:
        cursor.execute(query, start)
        rows = cursor.fetchall()
        if not rows:
            break
        first, last = rows[0][0], rows[-1][0]
        target = folder / f"part-{first:012d}-{last:012d}.parquet"
        temporary = target.with_suffix(".tmp")
        pq.write_table(to_arrow(rows, table), temporary, compression="zstd")
        temporary.replace(target)  # a block is either fully written or absent
        start = last
        exported += len(rows)
        done += len(rows)
        rate = exported / max(time.time() - began, 1)
        left = max(total - done, 0) / rate if rate else 0
        print(f"   {done:,}/{total:,} rows  ({rate:,.0f}/s, about {left / 60:,.0f} min left)", flush=True)
        if len(rows) < table.block:
            break
    print(f"   {table.name} finished: {done:,} rows in {folder}")
    if BROKEN_TEXT["values"]:
        print(f"   {BROKEN_TEXT['values']:,} text values had broken characters (half emojis), replaced by U+FFFD")
        BROKEN_TEXT["values"] = 0


def status(out: Path) -> None:
    for table in TABLES:
        files = list((out / table.name).glob("part-*.parquet"))
        rows = sum(pq.ParquetFile(p).metadata.num_rows for p in files)
        size = sum(p.stat().st_size for p in files) / 1e9
        print(f"{table.name:16} {len(files):5} files {rows:15,} rows {size:8.2f} GB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, type=Path, help="folder for the Parquet files (needs ~40 GB free)")
    parser.add_argument("--tables", nargs="*", default=[t.name for t in TABLES], choices=list(BY_NAME))
    parser.add_argument("--server", default="localhost")
    parser.add_argument("--status", action="store_true", help="show what was exported and stop")
    args = parser.parse_args()
    if args.status:
        status(args.out)
        return
    cursor = connect(args.server).cursor()
    try:
        for name in args.tables:
            export(cursor, BY_NAME[name], args.out)
    except KeyboardInterrupt:
        print("\nStopped. Run the same command again to resume.", file=sys.stderr)


if __name__ == "__main__":
    main()

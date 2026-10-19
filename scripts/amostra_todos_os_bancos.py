"""Inventory of every database on the SQL Server: tables, columns, row counts, dates, 10 sample rows
per table, and the source code of procedures, functions and views.

The goal is to know what each table holds without reading code. Nothing is changed on the server:
every query is a SELECT with NOLOCK.

Output (in --out):
    inventario_tabelas.csv     one line per table: database, table, rows, size, columns, created, modified
    inventario_modulos.csv     one line per procedure/function/view: database, name, type, created, modified
    amostras/<db>/<table>.csv  up to 10 rows of each table (long texts cut, binary columns skipped)
    modulos/<db>/<name>.sql    source code of each procedure, function and view
    log.txt                    tables that failed and why
At the end everything is zipped into <out>.zip.

Personal data: e-mails, phone numbers, CPF and CNPJ in sample values are masked by default
(--sem-mascara turns that off). The samples are only for analysis, not for publishing.

Usage (Windows, PowerShell):
    python scripts\\amostra_todos_os_bancos.py --out D:\\inventario_sql
    python scripts\\amostra_todos_os_bancos.py --out D:\\inventario_sql --bancos nlp_data_lake lojas
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import sys
import time
from pathlib import Path

SYSTEM_DBS = {"master", "tempdb", "model", "msdb", "ReportServer", "ReportServerTempDB", "SSISDB", "distribution"}
SKIP_TYPES = {"image", "varbinary", "binary", "timestamp", "rowversion", "geography", "geometry", "hierarchyid", "sql_variant", "xml"}
MAX_TEXT = 300

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
CPF_CNPJ = re.compile(r"(?<!\d)(?:\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}|\d{3}\.\d{3}\.\d{3}-\d{2}|\d{14}|\d{11})(?!\d)")
PHONE = re.compile(r"(?<!\d)(?:\+?55[\s-]?)?(?:\(\d{2}\)|\d{2})[\s-]?9?\d{4}[-\s]\d{4}(?!\d)|(?<!\d)\d{10}(?!\d)")


def decode_utf16(raw):
    if raw is None:
        return None
    return raw.decode("utf-16-le", errors="replace")


def connect(server: str):
    import pyodbc

    conn = pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};Trusted_Connection=yes",
        autocommit=True,
    )
    for sql_type in (pyodbc.SQL_WVARCHAR, pyodbc.SQL_WCHAR, pyodbc.SQL_WLONGVARCHAR):
        conn.add_output_converter(sql_type, decode_utf16)
    conn.timeout = 120  # seconds per query
    return conn


def mask(text: str) -> str:
    text = EMAIL.sub("<email>", text)
    text = CPF_CNPJ.sub("<documento>", text)
    return PHONE.sub("<telefone>", text)


def clean(value, masking: bool):
    if value is None:
        return ""
    text = str(value).replace("\r", " ").replace("\n", " ").replace("\t", " ")
    if len(text) > MAX_TEXT:
        text = text[:MAX_TEXT] + "…"
    return mask(text) if masking else text


def safe_name(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "_", name)


def databases(cur, only: list[str] | None) -> list[str]:
    cur.execute("SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name")
    names = [r[0] for r in cur.fetchall() if r[0] not in SYSTEM_DBS]
    return [n for n in names if not only or n in only]


def tables(cur, db: str) -> list[tuple]:
    cur.execute(f"""
        SELECT s.name, t.name, t.create_date, t.modify_date,
               SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END),
               SUM(a.total_pages) * 8 / 1024.0
        FROM [{db}].sys.tables t
        JOIN [{db}].sys.schemas s ON s.schema_id = t.schema_id
        JOIN [{db}].sys.partitions p ON p.object_id = t.object_id
        JOIN [{db}].sys.allocation_units a ON a.container_id = p.partition_id
        GROUP BY s.name, t.name, t.create_date, t.modify_date
        ORDER BY s.name, t.name""")
    return cur.fetchall()


def columns(cur, db: str, schema: str, table: str) -> list[tuple]:
    cur.execute(f"""
        SELECT c.name, ty.name, c.max_length
        FROM [{db}].sys.columns c
        JOIN [{db}].sys.types ty ON ty.user_type_id = c.user_type_id
        JOIN [{db}].sys.tables t ON t.object_id = c.object_id
        JOIN [{db}].sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = ? AND t.name = ?
        ORDER BY c.column_id""", schema, table)
    return cur.fetchall()


def modules(cur, db: str) -> list[tuple]:
    cur.execute(f"""
        SELECT s.name, o.name, o.type_desc, o.create_date, o.modify_date, m.definition
        FROM [{db}].sys.sql_modules m
        JOIN [{db}].sys.objects o ON o.object_id = m.object_id
        JOIN [{db}].sys.schemas s ON s.schema_id = o.schema_id
        ORDER BY o.type_desc, o.name""")
    return cur.fetchall()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--server", default="localhost")
    parser.add_argument("--bancos", nargs="*", help="only these databases (default: all)")
    parser.add_argument("--linhas", type=int, default=10, help="sample rows per table")
    parser.add_argument("--sem-mascara", action="store_true", help="do not mask e-mails, phones, CPF/CNPJ")
    args = parser.parse_args()

    out = args.out
    (out / "amostras").mkdir(parents=True, exist_ok=True)
    (out / "modulos").mkdir(exist_ok=True)
    log = open(out / "log.txt", "a", encoding="utf-8")
    conn = connect(args.server)
    cur = conn.cursor()
    masking = not args.sem_mascara

    tab_csv = open(out / "inventario_tabelas.csv", "w", newline="", encoding="utf-8-sig")
    mod_csv = open(out / "inventario_modulos.csv", "w", newline="", encoding="utf-8-sig")
    tab_w, mod_w = csv.writer(tab_csv), csv.writer(mod_csv)
    tab_w.writerow(["banco", "schema", "tabela", "linhas", "tamanho_mb", "criada", "alterada", "num_colunas", "colunas"])
    mod_w.writerow(["banco", "schema", "nome", "tipo", "criado", "alterado", "linhas_de_codigo"])

    began = time.time()
    for db in databases(cur, args.bancos):
        print(f"== {db}", flush=True)
        try:
            found = tables(cur, db)
        except Exception as error:  # no permission, offline, etc.
            log.write(f"{db}\t(lista de tabelas)\t{error}\n")
            continue
        for schema, table, created, modified, rows, size_mb in found:
            try:
                cols = columns(cur, db, schema, table)
                tab_w.writerow([db, schema, table, rows, round(size_mb or 0, 1), created, modified, len(cols),
                                "; ".join(f"{c} {t}" for c, t, _ in cols)])
                readable = [c for c, t, _ in cols if t not in SKIP_TYPES]
                if not readable or not rows:
                    continue
                select = ", ".join(f"[{c}]" for c in readable)
                cur.execute(f"SELECT TOP ({args.linhas}) {select} FROM [{db}].[{schema}].[{table}] WITH (NOLOCK)")
                sample = cur.fetchall()
                folder = out / "amostras" / safe_name(db)
                folder.mkdir(exist_ok=True)
                with open(folder / f"{safe_name(schema)}.{safe_name(table)}.csv", "w", newline="", encoding="utf-8-sig") as f:
                    w = csv.writer(f)
                    w.writerow(readable)
                    w.writerows([[clean(v, masking) for v in row] for row in sample])
            except Exception as error:
                log.write(f"{db}\t{schema}.{table}\t{error}\n")
        tab_csv.flush()
        try:
            for schema, name, kind, created, modified, definition in modules(cur, db):
                code = definition or ""
                mod_w.writerow([db, schema, name, kind, created, modified, code.count("\n") + 1])
                folder = out / "modulos" / safe_name(db)
                folder.mkdir(exist_ok=True)
                (folder / f"{safe_name(schema)}.{safe_name(name)}.sql").write_text(code, encoding="utf-8")
        except Exception as error:
            log.write(f"{db}\t(módulos)\t{error}\n")
        mod_csv.flush()
        print(f"   {len(found)} tables ({time.time() - began:,.0f} s so far)", flush=True)

    tab_csv.close(); mod_csv.close(); log.close()
    archive = shutil.make_archive(str(out), "zip", root_dir=out)
    print(f"Done in {time.time() - began:,.0f} s. Send this file: {archive}")


if __name__ == "__main__":
    sys.exit(main())

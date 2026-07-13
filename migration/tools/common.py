"""Shared helpers for the DB2 -> PostgreSQL migration tooling.

All database access is done through the `db2` CLI and `psql` inside the two Docker
containers, so no local database drivers are required.  Connection settings can be
overridden via environment variables.
"""

import os
import subprocess

DB2_CONTAINER = os.environ.get("DB2_CONTAINER", "db2")
DB2_DBNAME = os.environ.get("DB2_DBNAME", "STOCKTRD")
PG_CONTAINER = os.environ.get("PG_CONTAINER", "postgres")
PG_DBNAME = os.environ.get("PG_DBNAME", "stocktrader")
PG_USER = os.environ.get("PG_USER", "postgres")

NULL = "<NULL>"  # marker for NULL column values in delimited query output


def db2_query(sql):
    """Run a query on DB2 and return raw output lines (db2 -x: no headers)."""
    cmd = [
        "docker", "exec", DB2_CONTAINER, "su", "-", "db2inst1", "-c",
        f'db2 connect to {DB2_DBNAME} > /dev/null && db2 -x "{sql}"',
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode not in (0, 1):  # 1 = empty result set
        raise RuntimeError(f"db2 query failed ({result.returncode}): {result.stderr or result.stdout}")
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if len(lines) == 1 and "SQL0100W" in lines[0]:
        return []
    return lines


def db2_rows(select_list_exprs, from_clause):
    """Query DB2 returning '|'-delimited rows with NULLs marked, split into lists."""
    parts = " || '|' || ".join(f"COALESCE({e}, '{NULL}')" for e in select_list_exprs)
    lines = db2_query(f"SELECT {parts} FROM {from_clause}")
    return [[None if f == NULL else f for f in line.split("|")] for line in lines]


def pg_execute(sql):
    """Execute SQL on PostgreSQL (single transaction, errors fatal)."""
    cmd = ["docker", "exec", "-i", PG_CONTAINER, "psql",
           "-v", "ON_ERROR_STOP=1", "-U", PG_USER, "-d", PG_DBNAME, "-q"]
    result = subprocess.run(cmd, input=sql, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"psql failed: {result.stderr}")
    return result.stdout


def pg_query(sql):
    """Run a query on PostgreSQL and return rows as lists of strings (None for NULL)."""
    cmd = ["docker", "exec", PG_CONTAINER, "psql", "-U", PG_USER, "-d", PG_DBNAME,
           "-At", "-P", f"null={NULL}", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"psql query failed: {result.stderr}")
    lines = [line for line in result.stdout.splitlines() if line]
    return [[None if f == NULL else f for f in line.split("|")] for line in lines]


def sqlq(value):
    """Quote a value as a SQL literal."""
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def num(value):
    """Normalize a DB2/PG numeric string (handles DB2 scientific notation)."""
    if value is None:
        return None
    return float(value)

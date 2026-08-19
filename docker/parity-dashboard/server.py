#!/usr/bin/env python3
"""Side-by-side DB2 vs PostgreSQL parity dashboard for the portfolio microservice.

    python3 docker/parity-dashboard/server.py        # then open http://localhost:8090

The dashboard drives one identical scenario (create -> buy across loyalty tiers -> fetch ->
sell -> delete) against two instances of the *same* portfolio build:

    port 9081   JDBC_KIND=db2       USE_STORED_PROCS=true    legacy DB2 stored procedure path
    port 9082   JDBC_KIND=postgres  USE_STORED_PROCS=false   lifted Java rules path

Every step's HTTP response is compared field by field, and the run finishes with a row-level
reconciliation straight out of both databases (db2 CLP / psql).  A "negative control" run
tampers with one PostgreSQL row first, which must light up as MISMATCH.
"""

import base64
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8090"))

DB2_APP = os.environ.get("DB2_APP", "http://localhost:9081/portfolio")
PG_APP = os.environ.get("PG_APP", "http://localhost:9082/portfolio")
APP_USER = os.environ.get("APP_USER", "stock")
APP_PASSWORD = os.environ.get("APP_PASSWORD", "trader")

DB2_CONTAINER = os.environ.get("DB2_CONTAINER", "parity-db2")
PG_CONTAINER = os.environ.get("PG_CONTAINER", "parity-postgres")
DB = os.environ.get("DB", "trader")

OWNER = os.environ.get("PARITY_OWNER", "parity_demo")

#   Quotes come from the deterministic stub, so both backends price the same trade identically:
#   IBM 500, AAPL 150, MSFT 400, GOOG 100, AMZN 200, NVDA 1000, T 20.
#   The share counts walk the portfolio total up through every loyalty tier, and the last buy is a
#   block trade above the 250k threshold so the extra basis-point commission is exercised too.
SCENARIO = [
    {"id": "create", "label": "Create portfolio", "method": "POST", "path": "/{owner}",
     "query": {"accountID": "parity-0001"},
     "note": "loyalty starts at Basic with a 50.00 balance"},
    {"id": "buy-bronze", "label": "Buy 40 T (-> Bronze)", "method": "PUT", "path": "/{owner}",
     "query": {"symbol": "T", "shares": "40", "commission": "0"},
     "note": "total 800 -> still Basic, commission 9.99"},
    {"id": "buy-silver", "label": "Buy 150 IBM (-> Silver)", "method": "PUT", "path": "/{owner}",
     "query": {"symbol": "IBM", "shares": "150", "commission": "0"},
     "note": "total 75 800 -> Silver, commission charged at the pre-trade tier"},
    {"id": "buy-gold", "label": "Buy 800 MSFT (-> Gold)", "method": "PUT", "path": "/{owner}",
     "query": {"symbol": "MSFT", "shares": "800", "commission": "0"},
     "note": "total 395 800 -> Gold, block trade > 250k adds tradeValue * 0.00005"},
    {"id": "buy-platinum", "label": "Buy 900 NVDA (-> Platinum)", "method": "PUT", "path": "/{owner}",
     "query": {"symbol": "NVDA", "shares": "900", "commission": "0"},
     "note": "total 1 295 800 -> Platinum, block trade surcharge again"},
    {"id": "fetch", "label": "Fetch portfolio + returns", "method": "GET", "path": "/{owner}",
     "query": {},
     "note": "recomputes total, loyalty and the stock list"},
    {"id": "sell", "label": "Sell 400 MSFT", "method": "PUT", "path": "/{owner}",
     "query": {"symbol": "MSFT", "shares": "-400", "commission": "0"},
     "note": "loyalty is re-evaluated downwards after the sale"},
    {"id": "fetch-after-sell", "label": "Fetch after sell", "method": "GET", "path": "/{owner}",
     "query": {},
     "note": "post-sale totals, loyalty and commissions"},
    {"id": "delete", "label": "Delete portfolio", "method": "DELETE", "path": "/{owner}",
     "query": {},
     "note": "cascades to the Stock rows via the FK"},
]

RECONCILE_SQL_PG = (
    "SELECT owner, ROUND(total::numeric, 4), COALESCE(accountID, ''), COALESCE(loyalty, ''), "
    "ROUND(balance::numeric, 4), ROUND(commissions::numeric, 4) FROM Portfolio ORDER BY owner"
)
#   The DB2 CLP pads and right-aligns its output columns, so each DB2 row is concatenated into one
#   pipe-delimited string - the same shape psql -tAF'|' produces - and split on the client side.
RECONCILE_SQL_DB2 = (
    "SELECT TRIM(owner) || '|' || TRIM(CHAR(DECIMAL(COALESCE(total, 0), 20, 4))) || '|' || "
    "TRIM(COALESCE(accountID, '')) || '|' || TRIM(COALESCE(loyalty, '')) || '|' || "
    "TRIM(CHAR(DECIMAL(COALESCE(balance, 0), 20, 4))) || '|' || "
    "TRIM(CHAR(DECIMAL(COALESCE(commissions, 0), 20, 4))) FROM Portfolio ORDER BY owner"
)
STOCK_SQL_PG = (
    "SELECT owner, symbol, shares, ROUND(price::numeric, 4), ROUND(total::numeric, 4), "
    "dateQuoted, ROUND(commission::numeric, 4) FROM Stock ORDER BY owner, symbol"
)
STOCK_SQL_DB2 = (
    "SELECT TRIM(owner) || '|' || TRIM(symbol) || '|' || TRIM(CHAR(COALESCE(shares, 0))) || '|' || "
    "TRIM(CHAR(DECIMAL(COALESCE(price, 0), 20, 4))) || '|' || "
    "TRIM(CHAR(DECIMAL(COALESCE(total, 0), 20, 4))) || '|' || TRIM(COALESCE(dateQuoted, '')) || '|' || "
    "TRIM(CHAR(DECIMAL(COALESCE(commission, 0), 20, 4))) FROM Stock ORDER BY owner, symbol"
)


#  ----------------------------------------------------------------- app calls

def call_app(base, step):
    url = base + step["path"].format(owner=OWNER)
    if step["query"]:
        url += "?" + urllib.parse.urlencode(step["query"])

    request = urllib.request.Request(url, method=step["method"])
    credentials = f"{APP_USER}:{APP_PASSWORD}".encode()
    request.add_header("Authorization", "Basic " + base64.b64encode(credentials).decode())
    request.add_header("Accept", "application/json")

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read().decode() or ""
            status = response.status
    except urllib.error.HTTPError as error:
        body = error.read().decode() or ""
        status = error.code
    except Exception as error:  # connection refused, timeout, ...
        return {"url": url, "status": 0, "body": {"error": str(error)}}

    try:
        parsed = json.loads(body) if body.strip() else None
    except json.JSONDecodeError:
        parsed = body

    return {"url": url, "status": status, "body": parsed}


def normalize(value):
    """Round floats so the two engines' round-tripping of DOUBLE PRECISION doesn't show up as a
    difference, and drop the stock list ordering."""
    if isinstance(value, float):
        return round(value, 4)
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in sorted(value.items())}
    if isinstance(value, list):
        return sorted((normalize(item) for item in value), key=lambda item: json.dumps(item, sort_keys=True))
    return value


def diff_fields(left, right, prefix=""):
    """Field-level differences between two response bodies."""
    if isinstance(left, dict) and isinstance(right, dict):
        differences = []
        for key in sorted(set(left) | set(right)):
            differences += diff_fields(left.get(key), right.get(key), f"{prefix}{key}.")
        return differences
    if normalize(left) != normalize(right):
        return [{"field": prefix.rstrip("."), "db2": left, "postgres": right}]
    return []


#  ----------------------------------------------------------------- database access

def psql(sql):
    output = subprocess.run(
        ["docker", "exec", PG_CONTAINER, "psql", "-U", "postgres", "-d", DB, "-tAF", "|", "-c", sql],
        capture_output=True, text=True, check=True).stdout
    return [line.split("|") for line in output.strip().splitlines() if line.strip()]


def db2(sql):
    script = f"CONNECT TO {DB};\n{sql};\n"
    subprocess.run(["docker", "exec", "-i", DB2_CONTAINER, "sh", "-c", "cat > /tmp/dash.sql"],
                   input=script, text=True, check=True)
    output = subprocess.run(
        ["docker", "exec", DB2_CONTAINER, "su", "-", "db2inst1", "-c", "db2 -x -tf /tmp/dash.sql"],
        capture_output=True, text=True).stdout

    rows = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith(("Database Connection", "SQL", "DB2", "Database server",
                                        "SQL authorization", "Local database")):
            continue
        rows.append(line.split("|"))
    return rows


def cell(value):
    """DB2 renders DOUBLE as +1.23E+003 and pads CHAR columns; make both engines comparable."""
    value = (value or "").strip()
    try:
        return f"{round(float(value), 4):.4f}"
    except ValueError:
        return value


def reconcile():
    tables = []
    for name, db2_sql, pg_sql, columns in (
        ("Portfolio", RECONCILE_SQL_DB2, RECONCILE_SQL_PG,
         ["owner", "total", "accountID", "loyalty", "balance", "commissions"]),
        ("Stock", STOCK_SQL_DB2, STOCK_SQL_PG,
         ["owner", "symbol", "shares", "price", "total", "dateQuoted", "commission"]),
    ):
        db2_rows = {row[0]: [cell(value) for value in row] for row in db2(db2_sql) if row}
        pg_rows = {row[0]: [cell(value) for value in row] for row in psql(pg_sql) if row}
        if name == "Stock":
            db2_rows = {f"{row[0]}|{row[1]}": row for row in db2_rows.values()}
            pg_rows = {f"{row[0]}|{row[1]}": row for row in pg_rows.values()}

        rows = []
        for key in sorted(set(db2_rows) | set(pg_rows)):
            left, right = db2_rows.get(key), pg_rows.get(key)
            rows.append({"key": key, "db2": left, "postgres": right, "match": left == right})
        tables.append({"table": name, "columns": columns, "rows": rows,
                       "match": all(row["match"] for row in rows)})
    return tables


def cleanup():
    for base in (DB2_APP, PG_APP):
        call_app(base, {"method": "DELETE", "path": "/{owner}", "query": {}})


def tamper():
    """Negative control: nudge one PostgreSQL row so the reconciliation must flag it."""
    sql = ("UPDATE Portfolio SET commissions = COALESCE(commissions, 0) + 1.11, "
           "loyalty = 'Bronze' WHERE owner = 'seed_platinum'")
    psql(sql)
    return sql


def untamper():
    psql("UPDATE Portfolio SET commissions = 0.0, loyalty = 'Platinum' WHERE owner = 'seed_platinum'")


#  ----------------------------------------------------------------- run

def run_scenario(negative_control=False):
    cleanup()
    untamper()

    steps = []
    for step in SCENARIO:
        db2_result = call_app(DB2_APP, step)
        pg_result = call_app(PG_APP, step)
        differences = diff_fields(db2_result["body"], pg_result["body"])
        steps.append({
            "id": step["id"], "label": step["label"], "note": step["note"],
            "method": step["method"], "path": step["path"].format(owner=OWNER),
            "query": step["query"],
            "db2": db2_result, "postgres": pg_result,
            "match": db2_result["status"] == pg_result["status"] and not differences,
            "diff": differences,
        })

    tampered_sql = tamper() if negative_control else None
    tables = reconcile()
    if negative_control:
        untamper()

    return {
        "owner": OWNER,
        "negativeControl": negative_control,
        "tamperedSql": tampered_sql,
        "steps": steps,
        "reconciliation": tables,
        "summary": {
            "steps": len(steps),
            "stepsMatched": sum(1 for step in steps if step["match"]),
            "rows": sum(len(table["rows"]) for table in tables),
            "rowsMatched": sum(1 for table in tables for row in table["rows"] if row["match"]),
        },
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[dashboard] {fmt % args}")

    def _send(self, status, content_type, payload):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(path.query)

        if path.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as page:
                self._send(200, "text/html; charset=utf-8", page.read())
        elif path.path == "/api/run":
            negative = query.get("negativeControl", ["false"])[0] == "true"
            try:
                payload = json.dumps(run_scenario(negative)).encode()
            except Exception as error:
                payload = json.dumps({"error": str(error)}).encode()
            self._send(200, "application/json", payload)
        else:
            self._send(404, "text/plain", b"not found")


if __name__ == "__main__":
    print(f"parity dashboard on http://localhost:{PORT}  (db2 app {DB2_APP}, postgres app {PG_APP})")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

"""DB2 vs PostgreSQL parity dashboard for the portfolio microservice migration.

Drives the SAME application scenario against two live portfolio instances --
one backed by DB2 (legacy stored-procedure path) and one backed by PostgreSQL
(new lifted TradePolicy path) -- and diffs every response, plus a row-level
reconciliation of both databases and a tamper-based negative control.

Run on the host (needs `docker` for the reconciliation queries):
    pip install flask requests
    python3 app.py          ->  http://localhost:8080
"""
import json
import subprocess

import requests
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__, static_folder="static")

DB2_APP = "http://localhost:9081/portfolio"
PG_APP = "http://localhost:9082/portfolio"
AUTH = ("stock", "trader")
OWNER = "Parity"

DB2_CONTAINER = "migration-db2"
PG_CONTAINER = "migration-postgres"

SCENARIO = [
    ("Create portfolio", "POST", f"/{OWNER}?accountID=acct-parity"),
    ("Buy 100 IBM @150 (Basic commission 9.99 -> Bronze)", "PUT", f"/{OWNER}?symbol=IBM&shares=100"),
    ("Buy 150 MSFT @400 (Bronze commission 8.99 -> Silver)", "PUT", f"/{OWNER}?symbol=MSFT&shares=150"),
    ("Buy 500 AAPL @250 (Silver commission 7.99 -> Gold)", "PUT", f"/{OWNER}?symbol=AAPL&shares=500"),
    ("Buy 300 NVDA @3000 (Gold 6.99 + block-trade surcharge 45.00 -> Platinum)", "PUT", f"/{OWNER}?symbol=NVDA&shares=300"),
    ("Fetch portfolio / returns", "GET", f"/{OWNER}"),
    ("Sell 100 IBM (position closed)", "PUT", f"/{OWNER}?symbol=IBM&shares=-100"),
    ("Delete portfolio", "DELETE", f"/{OWNER}"),
]


def normalize(payload):
    """Stable, key-sorted rendering so responses can be compared structurally."""
    if isinstance(payload, dict):
        return {k: normalize(v) for k, v in sorted(payload.items())}
    if isinstance(payload, list):
        return [normalize(v) for v in payload]
    return payload


def call(base, method, path):
    try:
        r = requests.request(method, base + path, auth=AUTH, timeout=30)
        try:
            body = normalize(r.json())
        except ValueError:
            body = r.text
        return {"status": r.status_code, "body": body}
    except Exception as e:  # noqa: BLE001 - surfaced in the UI
        return {"status": "ERROR", "body": str(e)}


@app.post("/api/run")
def run_scenario():
    steps = []
    for name, method, path in SCENARIO:
        db2 = call(DB2_APP, method, path)
        pg = call(PG_APP, method, path)
        steps.append({
            "name": name,
            "request": f"{method} {path}",
            "db2": db2,
            "postgres": pg,
            "match": json.dumps(db2, sort_keys=True) == json.dumps(pg, sort_keys=True),
        })
    return jsonify({"steps": steps})


def sh(cmd, stdin=None):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120,
                          input=stdin).stdout


def db2_rows(query):
    # A db2 CLP invocation from a non-interactive shell gets its own backend, so the
    # CONNECT must be in the same script as the query; the script is piped over stdin
    # to avoid any shell quoting of the SQL itself.
    script = f"CONNECT TO trader;\n{query};\n"
    out = sh(f"docker exec -i {DB2_CONTAINER} su - db2inst1 -c "
             f"'cat > /tmp/dashq.sql && db2 -x -tf /tmp/dashq.sql'", stdin=script)
    return [line.strip() for line in out.splitlines() if "|" in line]


def pg_rows(query):
    out = sh(f"docker exec {PG_CONTAINER} psql -U postgres -d trader -t -A -c \"{query}\"")
    return [line.strip() for line in out.splitlines() if line.strip()]


def parse_row(line, numeric_idx):
    parts = line.split("|")
    return [round(float(p), 6) if i in numeric_idx and p not in ("", None) else (p or "")
            for i, p in enumerate(parts)]


PORTFOLIO_DB2 = ("SELECT TRIM(owner)||'|'||COALESCE(CHAR(total),'')||'|'||COALESCE(TRIM(accountID),'')||'|'||"
                 "COALESCE(TRIM(loyalty),'')||'|'||COALESCE(CHAR(balance),'')||'|'||COALESCE(CHAR(commissions),'') "
                 "FROM Portfolio ORDER BY owner")
PORTFOLIO_PG = ("SELECT owner||'|'||COALESCE(total::text,'')||'|'||COALESCE(accountID,'')||'|'||"
                "COALESCE(loyalty,'')||'|'||COALESCE(balance::text,'')||'|'||COALESCE(commissions::text,'') "
                "FROM Portfolio ORDER BY owner")
STOCK_DB2 = ("SELECT TRIM(owner)||'|'||TRIM(symbol)||'|'||COALESCE(CHAR(shares),'')||'|'||COALESCE(CHAR(price),'')||'|'||"
             "COALESCE(CHAR(total),'')||'|'||COALESCE(TRIM(dateQuoted),'')||'|'||COALESCE(CHAR(commission),'') "
             "FROM Stock ORDER BY owner, symbol")
STOCK_PG = ("SELECT owner||'|'||symbol||'|'||COALESCE(shares::text,'')||'|'||COALESCE(price::text,'')||'|'||"
            "COALESCE(total::text,'')||'|'||COALESCE(dateQuoted,'')||'|'||COALESCE(commission::text,'') "
            "FROM Stock ORDER BY owner, symbol")


def reconcile_table(name, db2_query, pg_query, numeric_idx, columns):
    d_rows = {r[0]: r for r in (parse_row(line, numeric_idx) for line in db2_rows(db2_query))}
    p_rows = {r[0]: r for r in (parse_row(line, numeric_idx) for line in pg_rows(pg_query))}
    keys = sorted(set(d_rows) | set(p_rows))
    rows = []
    for k in keys:
        d, p = d_rows.get(k), p_rows.get(k)
        rows.append({"key": k, "db2": d, "postgres": p, "match": d == p})
    return {"table": name, "columns": columns, "rows": rows,
            "match": all(r["match"] for r in rows)}


@app.get("/api/reconcile")
def reconcile():
    portfolio = reconcile_table(
        "Portfolio", PORTFOLIO_DB2, PORTFOLIO_PG, {1, 4, 5},
        ["owner", "total", "accountID", "loyalty", "balance", "commissions"])
    # Stock keys are composite (owner, symbol) -- fold symbol into the key
    stock = reconcile_table(
        "Stock",
        STOCK_DB2.replace("TRIM(owner)||'|'||TRIM(symbol)", "TRIM(owner)||' / '||TRIM(symbol)||'|'||TRIM(symbol)"),
        STOCK_PG.replace("owner||'|'||symbol", "owner||' / '||symbol||'|'||symbol"),
        {2, 3, 4, 6},
        ["owner / symbol", "symbol", "shares", "price", "total", "dateQuoted", "commission"])
    return jsonify({"tables": [portfolio, stock]})


@app.post("/api/tamper")
def tamper():
    """Negative control: corrupt one PostgreSQL row so the reconciliation must flag it."""
    pg_rows("UPDATE Portfolio SET commissions = commissions + 1.0 WHERE owner = 'SeedGold'")
    return jsonify({"tampered": True, "sql": "UPDATE Portfolio SET commissions = commissions + 1.0 WHERE owner = 'SeedGold' (PostgreSQL only)"})


@app.post("/api/untamper")
def untamper():
    pg_rows("UPDATE Portfolio SET commissions = commissions - 1.0 WHERE owner = 'SeedGold'")
    return jsonify({"tampered": False})


@app.get("/")
def index():
    return send_from_directory("static", "index.html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

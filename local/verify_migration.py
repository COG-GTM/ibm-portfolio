#!/usr/bin/env python3
"""Side-by-side DB2 vs PostgreSQL verification harness.

Runs the same representative OLTP statements (the ones the portfolio
microservice issues via JPA) against BOTH databases started by
local/docker-compose.yml, compares the results, prints a colorized PASS/FAIL
table, and writes an HTML parity report to docs/migration-report.html.

Usage:  python3 local/verify_migration.py
"""

import html
import subprocess
import sys
import time
from pathlib import Path

DB2_CONTAINER = "stocktrader-db2"
PG_CONTAINER = "stocktrader-postgres"

GREEN, RED, YELLOW, CYAN, BOLD, DIM, RESET = (
    "\033[92m", "\033[91m", "\033[93m", "\033[96m", "\033[1m", "\033[2m", "\033[0m")


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120)


def db2_sql(sql):
    """Run one SQL statement inside the DB2 container, return raw row text."""
    shell = ("db2 connect to trader > /dev/null && "
             f"db2 -x \"{sql}\"; rc=$?; db2 terminate > /dev/null; exit $rc")
    r = run(["docker", "exec", DB2_CONTAINER, "su", "-", "db2inst1", "-c", shell])
    out = r.stdout.strip()
    if r.returncode not in (0, 1):  # rc 1 = empty result set for db2 -x
        raise RuntimeError(f"DB2 error ({r.returncode}): {out} {r.stderr.strip()}")
    return "" if r.returncode == 1 else out


def pg_sql(sql):
    """Run one SQL statement inside the Postgres container, return raw row text."""
    r = run(["docker", "exec", PG_CONTAINER, "psql", "-U", "db2inst1", "-d", "trader",
             "-tA", "-F", " ", "-c", sql])
    if r.returncode != 0:
        raise RuntimeError(f"Postgres error: {r.stderr.strip()}")
    return r.stdout.strip()


def normalize(text):
    """Collapse whitespace and normalize numeric formatting for comparison."""
    rows = []
    for line in text.splitlines():
        cells = []
        for tok in line.split():
            try:
                f = float(tok)
                cells.append(f"{f:.2f}")
            except ValueError:
                cells.append(tok)
        if cells:
            rows.append(" ".join(cells))
    return sorted(rows)


# (name, sql, is_query) — identical statements executed on both engines
STATEMENTS = [
    ("Cleanup any prior test data",
     "DELETE FROM Portfolio WHERE owner IN ('DemoUser', 'DemoUser2')", False),
    ("INSERT portfolio DemoUser",
     "INSERT INTO Portfolio (owner, total, accountID) VALUES ('DemoUser', 0.0, 'acct-001')", False),
    ("INSERT portfolio DemoUser2",
     "INSERT INTO Portfolio (owner, total, accountID) VALUES ('DemoUser2', 0.0, 'acct-002')", False),
    ("INSERT stock IBM for DemoUser",
     "INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) "
     "VALUES ('DemoUser', 'IBM', 123, 155.45, 19120.35, '2026-07-12', 9.99)", False),
    ("INSERT stock AAPL for DemoUser",
     "INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) "
     "VALUES ('DemoUser', 'AAPL', 50, 210.10, 10505.00, '2026-07-12', 9.99)", False),
    ("SELECT stocks for DemoUser",
     "SELECT owner, symbol, shares, price FROM Stock WHERE owner = 'DemoUser' ORDER BY symbol", True),
    ("UPDATE shares of IBM",
     "UPDATE Stock SET shares = 200, commission = 19.98 WHERE owner = 'DemoUser' AND symbol = 'IBM'", False),
    ("SELECT updated IBM row",
     "SELECT owner, symbol, shares, commission FROM Stock WHERE owner = 'DemoUser' AND symbol = 'IBM'", True),
    ("UPDATE portfolio total",
     "UPDATE Portfolio SET total = 29625.35 WHERE owner = 'DemoUser'", False),
    ("SELECT portfolio totals",
     "SELECT owner, total FROM Portfolio WHERE owner LIKE 'DemoUser%' ORDER BY owner", True),
    ("Aggregate: SUM shares per owner",
     "SELECT owner, SUM(shares) FROM Stock WHERE owner LIKE 'DemoUser%' GROUP BY owner ORDER BY owner", True),
    ("Row counts (Portfolio)",
     "SELECT COUNT(*) FROM Portfolio WHERE owner LIKE 'DemoUser%'", True),
    ("Row counts (Stock)",
     "SELECT COUNT(*) FROM Stock WHERE owner LIKE 'DemoUser%'", True),
    ("DELETE portfolio (cascade to Stock)",
     "DELETE FROM Portfolio WHERE owner = 'DemoUser'", False),
    ("Verify cascade delete removed stocks",
     "SELECT COUNT(*) FROM Stock WHERE owner = 'DemoUser'", True),
    ("Cleanup",
     "DELETE FROM Portfolio WHERE owner = 'DemoUser2'", False),
]


def main():
    print(f"{BOLD}{CYAN}================================================================{RESET}")
    print(f"{BOLD}{CYAN}  DB2 -> PostgreSQL Migration Verification (side-by-side OLTP) {RESET}")
    print(f"{BOLD}{CYAN}================================================================{RESET}")
    print(f"{DIM}DB2:        {DB2_CONTAINER} (icr.io/db2_community/db2, database TRADER){RESET}")
    print(f"{DIM}PostgreSQL: {PG_CONTAINER} (postgres:16, database trader){RESET}\n")

    results = []
    failures = 0
    for name, sql, is_query in STATEMENTS:
        t0 = time.time()
        try:
            out_db2 = db2_sql(sql)
            out_pg = pg_sql(sql)
            if is_query:
                ok = normalize(out_db2) == normalize(out_pg)
                detail_db2, detail_pg = out_db2 or "(0 rows)", out_pg or "(0 rows)"
            else:
                ok = True
                detail_db2 = detail_pg = "OK"
        except Exception as e:  # noqa: BLE001
            ok, detail_db2, detail_pg = False, str(e), str(e)
        ms = int((time.time() - t0) * 1000)
        results.append((name, sql, ok, detail_db2, detail_pg, ms))
        if not ok:
            failures += 1
        status = f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}"
        print(f"  [{status}] {name:<42} {DIM}{ms:>5} ms{RESET}")
        if is_query:
            print(f"         {DIM}DB2: {detail_db2.replace(chr(10), ' | ')}{RESET}")
            print(f"         {DIM}PG : {detail_pg.replace(chr(10), ' | ')}{RESET}")

    total = len(results)
    passed = total - failures
    print(f"\n{BOLD}{'='*64}{RESET}")
    color = GREEN if failures == 0 else RED
    print(f"{BOLD}  RESULT: {color}{passed}/{total} statements produced identical behavior{RESET}")
    if failures == 0:
        print(f"{BOLD}{GREEN}  DATA PARITY VERIFIED — PostgreSQL is a drop-in replacement{RESET}")
    print(f"{BOLD}{'='*64}{RESET}")

    write_report(results, passed, total)
    print(f"\nHTML report: docs/migration-report.html")
    sys.exit(1 if failures else 0)


def write_report(results, passed, total):
    rows = ""
    for name, sql, ok, d2, dp, ms in results:
        badge = ('<span class="pass">PASS</span>' if ok
                 else '<span class="fail">FAIL</span>')
        rows += f"""<tr><td>{badge}</td><td>{html.escape(name)}</td>
        <td><code>{html.escape(sql)}</code></td>
        <td><pre>{html.escape(d2)}</pre></td><td><pre>{html.escape(dp)}</pre></td>
        <td>{ms} ms</td></tr>\n"""
    verdict = ("DATA PARITY VERIFIED" if passed == total
               else f"{total - passed} MISMATCH(ES) FOUND")
    verdict_cls = "ok" if passed == total else "bad"
    doc = f"""<!DOCTYPE html><html><head><meta charset="utf-8">
<title>DB2 → PostgreSQL Migration Report</title><style>
 body {{ font-family: 'Segoe UI', system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:2rem; }}
 h1 {{ color:#58a6ff; }} .sub {{ color:#8b949e; }}
 .verdict {{ font-size:1.4rem; font-weight:700; padding:.8rem 1.2rem; border-radius:8px; display:inline-block; margin:1rem 0; }}
 .verdict.ok {{ background:#0f2e18; color:#3fb950; border:1px solid #3fb950; }}
 .verdict.bad {{ background:#3d1215; color:#f85149; border:1px solid #f85149; }}
 table {{ border-collapse:collapse; width:100%; }}
 th,td {{ border:1px solid #30363d; padding:.5rem .7rem; text-align:left; vertical-align:top; }}
 th {{ background:#161b22; color:#58a6ff; }}
 tr:nth-child(even) {{ background:#161b22; }}
 code,pre {{ font-family:ui-monospace,monospace; font-size:.85rem; white-space:pre-wrap; margin:0; }}
 .pass {{ background:#0f2e18; color:#3fb950; padding:2px 10px; border-radius:12px; font-weight:700; }}
 .fail {{ background:#3d1215; color:#f85149; padding:2px 10px; border-radius:12px; font-weight:700; }}
</style></head><body>
<h1>DB2 &rarr; PostgreSQL Migration Verification Report</h1>
<p class="sub">IBM Stock Trader &mdash; portfolio microservice &middot; identical OLTP statements executed
against IBM DB2 (icr.io/db2_community/db2) and PostgreSQL 16 &middot; generated {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}</p>
<div class="verdict {verdict_cls}">{passed}/{total} statements identical &mdash; {verdict}</div>
<table><tr><th>Status</th><th>Test</th><th>SQL</th><th>DB2 result</th><th>PostgreSQL result</th><th>Time</th></tr>
{rows}</table></body></html>"""
    out = Path(__file__).resolve().parent.parent / "docs" / "migration-report.html"
    out.write_text(doc)


if __name__ == "__main__":
    main()

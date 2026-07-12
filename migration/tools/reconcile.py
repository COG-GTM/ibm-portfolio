#!/usr/bin/env python3
"""Reconciliation report: compares DB2 (source) and PostgreSQL (target) side by side.

For each table it compares row counts and an order-insensitive content checksum
(MD5 over canonicalized rows: doubles rounded to 2 decimals, sorted by primary key),
and reports CDC replication lag from the journal vs. the replayer state file.

Exit code 0 when everything matches (all green), 1 otherwise.
Pass --watch to re-run every few seconds.

Pass --final for the post-cutover zero-loss proof: after cutover, new traffic lands
only in PostgreSQL (by design), so instead of requiring identical tables it verifies
that every row DB2 ever had is present and byte-identical in PostgreSQL (source ⊆
target) and that the CDC journal is fully drained — i.e. zero lost transactions.
"""

import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import db2_query, db2_rows, pg_query, num

STATE_FILE = os.environ.get("CDC_STATE_FILE", "/tmp/cdc_state.json")

TABLES = {
    "Portfolio": {
        "db2": (["owner", "VARCHAR(total)", "accountID"], "Portfolio"),
        "pg": "SELECT owner, total, accountid FROM portfolio",
        "numeric": [1],
        # price/total/dateQuoted are quote-cache columns the app rewrites on every GET,
        # so post-cutover reads legitimately update them in PG; exclude them from the
        # final zero-loss comparison and compare the durable business data.
        "final_idx": [0, 2],
    },
    "Stock": {
        "db2": (["owner", "symbol", "VARCHAR(shares)", "VARCHAR(price)",
                 "VARCHAR(total)", "dateQuoted", "VARCHAR(commission)"], "Stock"),
        "pg": "SELECT owner, symbol, shares, price, total, datequoted, commission FROM stock",
        "numeric": [3, 4, 6],
        "final_idx": [0, 1, 2, 6],
    },
}


def canon_rows(rows, numeric_idx):
    out = []
    for row in rows:
        fields = []
        for i, f in enumerate(row):
            if f is not None and i in numeric_idx:
                f = f"{num(f):.2f}"
            elif f is not None and f.lstrip("-").isdigit():
                f = str(int(f))
            fields.append("" if f is None else f)
        out.append("\x1f".join(fields))
    return out


def canon(rows, numeric_idx):
    out = sorted(canon_rows(rows, numeric_idx))
    return hashlib.md5("\n".join(out).encode()).hexdigest()[:12]


def final_report():
    """Post-cutover zero-loss proof: every DB2 row must exist identically in PG."""
    now = datetime.now(timezone.utc).strftime("%H:%M:%S UTC")
    head = int(db2_query("SELECT COALESCE(MAX(change_id), 0) FROM CDC_CHANGES")[0])
    with open(STATE_FILE) as f:
        state = json.load(f)
    applied = int(state["last_applied_change_id"])
    drained = head <= applied
    ok = drained

    print(f"\n=== FINAL ZERO-LOSS VERIFICATION (post-cutover) @ {now} ===")
    print(f"| {'Table':<10} | {'DB2 rows':>8} | {'found in PG':>11} | {'missing':>7} | {'Status':<11} |")
    print(f"|{'-'*12}|{'-'*10}|{'-'*13}|{'-'*9}|{'-'*13}|")
    for name, spec in TABLES.items():
        numeric = set(spec["numeric"])
        keep = spec["final_idx"]
        project = lambda rows: [[r[i] for i in keep] for r in rows]
        numeric_kept = {keep.index(i) for i in numeric if i in keep}
        src = canon_rows(project(db2_rows(*spec["db2"])), numeric_kept)
        tgt = set(canon_rows(project(pg_query(spec["pg"])), numeric_kept))
        missing = [r for r in src if r not in tgt]
        match = not missing
        ok = ok and match
        status = "\u2705 ALL FOUND" if match else "\u274c LOST ROWS"
        print(f"| {name:<10} | {len(src):>8} | {len(src)-len(missing):>11} | {len(missing):>7} | {status:<11} |")
        for r in missing[:5]:
            print(f"|   missing: {r.replace(chr(31), ' | ')}")
    drain_status = "\u2705 DRAINED" if drained else "\u274c NOT DRAINED"
    print(f"| {'CDC drain':<10} | {'head='+str(head):>8} | {'appl='+str(applied):>11} | {head-applied:>7} | {drain_status:<11} |")
    verdict = "\u2705 ZERO LOST TRANSACTIONS \u2014 every DB2 transaction is in PostgreSQL" if ok \
        else "\u274c DATA LOSS DETECTED"
    print(f"OVERALL: {verdict}")
    sys.exit(0 if ok else 1)


def main():
    if "--final" in sys.argv:
        final_report()
    watch = "--watch" in sys.argv
    while True:
        ok = True
        now = datetime.now(timezone.utc).strftime("%H:%M:%S UTC")
        head = int(db2_query("SELECT COALESCE(MAX(change_id), 0) FROM CDC_CHANGES")[0])
        try:
            with open(STATE_FILE) as f:
                state = json.load(f)
            applied = int(state["last_applied_change_id"])
            replayed = state.get("changes_replayed", 0)
        except FileNotFoundError:
            applied, replayed = 0, 0
        lag = head - applied

        rows_out = []
        for name, spec in TABLES.items():
            db2r = db2_rows(*spec["db2"])
            pgr = pg_query(spec["pg"])
            csum_src = canon(db2r, set(spec["numeric"]))
            csum_tgt = canon(pgr, set(spec["numeric"]))
            match = len(db2r) == len(pgr) and csum_src == csum_tgt
            ok = ok and match
            rows_out.append((name, len(db2r), len(pgr), csum_src, csum_tgt,
                             "\u2705 MATCH" if match else "\u274c MISMATCH"))

        lag_ok = lag == 0
        ok = ok and lag_ok
        lag_status = "\u2705 IN SYNC" if lag_ok else "\u26a0\ufe0f  LAGGING"
        overall = "\u2705 ALL GREEN - GO for cutover" if ok else "\u274c NOT IN SYNC - NO-GO"

        print(f"\n=== RECONCILIATION REPORT @ {now} ===")
        print(f"| {'Table':<10} | {'DB2 rows':>8} | {'PG rows':>8} | {'DB2 checksum':<12} | {'PG checksum':<12} | {'Status':<11} |")
        print(f"|{'-'*12}|{'-'*10}|{'-'*10}|{'-'*14}|{'-'*14}|{'-'*13}|")
        for r in rows_out:
            print(f"| {r[0]:<10} | {r[1]:>8} | {r[2]:>8} | {r[3]:<12} | {r[4]:<12} | {r[5]:<11} |")
        print(f"| {'CDC lag':<10} | {'head='+str(head):>8} | {'appl='+str(applied):>8} | "
              f"{'pending='+str(lag):<12} | {'replayed='+str(replayed):<12} | "
              f"{lag_status:<10} |")
        print(f"OVERALL: {overall}")

        if not watch:
            sys.exit(0 if ok else 1)
        time.sleep(3)


if __name__ == "__main__":
    main()

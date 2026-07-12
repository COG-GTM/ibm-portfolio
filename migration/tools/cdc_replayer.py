#!/usr/bin/env python3
"""CDC replayer daemon: streams changes from the DB2 CDC_CHANGES journal to PostgreSQL.

Anchored at the bulk-load snapshot point (state file written by bulk_load.py), it polls
the journal and applies every change with change_id > last_applied, in change_id order,
inside a single PostgreSQL transaction per batch.  All operations are idempotent
(upserts / deletes), so overlap with the bulk load or a crash-restart is safe.

This trigger-journal approach stands in for log-based CDC (Q-Replication / Debezium).
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import db2_query, db2_rows, pg_execute, sqlq, num

STATE_FILE = os.environ.get("CDC_STATE_FILE", "/tmp/cdc_state.json")
POLL_SECONDS = float(os.environ.get("CDC_POLL_SECONDS", "2"))

CHANGE_COLS = ["VARCHAR(change_id)", "table_name", "op", "owner", "symbol",
               "VARCHAR(p_total)", "accountid", "VARCHAR(shares)", "VARCHAR(price)",
               "VARCHAR(s_total)", "datequoted", "VARCHAR(commission)", "VARCHAR(changed_at)"]


def to_sql(change):
    (_, table, op, owner, symbol, p_total, accountid,
     shares, price, s_total, datequoted, commission, _) = change
    if table == "PORTFOLIO":
        if op in ("I", "U"):
            return (f"INSERT INTO portfolio(owner, total, accountid) "
                    f"VALUES ({sqlq(owner)}, {sqlq(num(p_total))}, {sqlq(accountid)}) "
                    f"ON CONFLICT (owner) DO UPDATE SET total = EXCLUDED.total, accountid = EXCLUDED.accountid;")
        return f"DELETE FROM portfolio WHERE owner = {sqlq(owner)};"  # cascades to stock
    else:  # STOCK
        if op in ("I", "U"):
            return (f"INSERT INTO stock(owner, symbol, shares, price, total, datequoted, commission) "
                    f"VALUES ({sqlq(owner)}, {sqlq(symbol)}, {sqlq(shares)}, {sqlq(num(price))}, "
                    f"{sqlq(num(s_total))}, {sqlq(datequoted)}, {sqlq(num(commission))}) "
                    f"ON CONFLICT (owner, symbol) DO UPDATE SET shares = EXCLUDED.shares, price = EXCLUDED.price, "
                    f"total = EXCLUDED.total, datequoted = EXCLUDED.datequoted, commission = EXCLUDED.commission;")
        return f"DELETE FROM stock WHERE owner = {sqlq(owner)} AND symbol = {sqlq(symbol)};"


def main():
    with open(STATE_FILE) as f:
        state = json.load(f)
    last = int(state["last_applied_change_id"])
    print(f"[cdc] starting replayer from change_id={last} (poll every {POLL_SECONDS}s)", flush=True)

    while True:
        head = int(db2_query("SELECT COALESCE(MAX(change_id), 0) FROM CDC_CHANGES")[0])
        pending = head - last
        if pending > 0:
            changes = db2_rows(
                CHANGE_COLS,
                f"CDC_CHANGES WHERE change_id > {last} ORDER BY change_id")
            batch = ["BEGIN;"] + [to_sql(c) for c in changes] + ["COMMIT;"]
            pg_execute("\n".join(batch))
            last = int(changes[-1][0])
            state["last_applied_change_id"] = last
            state["changes_replayed"] = state.get("changes_replayed", 0) + len(changes)
            state["last_replay_at"] = datetime.now(timezone.utc).isoformat()
            with open(STATE_FILE, "w") as f:
                json.dump(state, f, indent=2)
            print(f"[cdc] applied {len(changes):3d} changes -> Postgres  "
                  f"(journal head={head}, applied through={last}, lag=0)", flush=True)
        else:
            print(f"[cdc] in sync (journal head={head}, applied through={last}, lag=0)", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Phase 1 of the migration: bulk-load historical data from DB2 into PostgreSQL.

Safe to run while live traffic is hitting DB2: the CDC anchor (MAX(change_id) in the
CDC_CHANGES journal) is recorded BEFORE the table snapshot is taken, so any change that
races with the snapshot is also captured by CDC and re-applied idempotently by the
replayer.  Writes the replayer state file with the anchor.
"""

import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import db2_query, db2_rows, pg_execute, sqlq, num

STATE_FILE = os.environ.get("CDC_STATE_FILE", "/tmp/cdc_state.json")


def main():
    started = datetime.now(timezone.utc)

    # 1. Record the CDC anchor BEFORE snapshotting, so no concurrent change is lost.
    anchor = int(db2_query("SELECT COALESCE(MAX(change_id), 0) FROM CDC_CHANGES")[0])
    print(f"[bulk-load] CDC anchor (snapshot point): change_id={anchor}")

    # 2. Snapshot both tables from DB2.
    portfolios = db2_rows(
        ["owner", "VARCHAR(total)", "accountID"], "Portfolio")
    stocks = db2_rows(
        ["owner", "symbol", "VARCHAR(shares)", "VARCHAR(price)",
         "VARCHAR(total)", "dateQuoted", "VARCHAR(commission)"], "Stock")
    print(f"[bulk-load] snapshotted {len(portfolios)} portfolios, {len(stocks)} stocks from DB2")

    # 3. Bulk-insert into PostgreSQL (idempotent: overlapping CDC replays win later).
    stmts = ["BEGIN;"]
    for owner, total, accountid in portfolios:
        stmts.append(
            f"INSERT INTO portfolio(owner, total, accountid) "
            f"VALUES ({sqlq(owner)}, {sqlq(num(total))}, {sqlq(accountid)}) "
            f"ON CONFLICT (owner) DO UPDATE SET total = EXCLUDED.total, accountid = EXCLUDED.accountid;")
    for owner, symbol, shares, price, total, datequoted, commission in stocks:
        stmts.append(
            f"INSERT INTO stock(owner, symbol, shares, price, total, datequoted, commission) "
            f"VALUES ({sqlq(owner)}, {sqlq(symbol)}, {sqlq(shares)}, {sqlq(num(price))}, "
            f"{sqlq(num(total))}, {sqlq(datequoted)}, {sqlq(num(commission))}) "
            f"ON CONFLICT (owner, symbol) DO UPDATE SET shares = EXCLUDED.shares, price = EXCLUDED.price, "
            f"total = EXCLUDED.total, datequoted = EXCLUDED.datequoted, commission = EXCLUDED.commission;")
    stmts.append("COMMIT;")
    pg_execute("\n".join(stmts))
    print(f"[bulk-load] loaded into PostgreSQL")

    # 4. Persist the anchor so the CDC replayer starts exactly at the snapshot point.
    state = {
        "last_applied_change_id": anchor,
        "snapshot_anchor": anchor,
        "snapshot_at": started.isoformat(),
        "portfolios_loaded": len(portfolios),
        "stocks_loaded": len(stocks),
        "changes_replayed": 0,
    }
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    print(f"[bulk-load] wrote state file {STATE_FILE}: {json.dumps(state)}")


if __name__ == "__main__":
    main()

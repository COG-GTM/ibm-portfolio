--   Identical seed data for both engines, loaded after createTables.ddl.
--   Deliberately covers every loyalty tier so the lifted tiering and commission
--   rules are exercised from a non-trivial starting state.
--   Run via "psql -f seed-data.sql" or "db2 -tf seed-data.sql".

INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('seed_basic',    5000.0,  'acct-0001', 'Basic',    50.0, 0.0);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('seed_bronze',  25000.0,  'acct-0002', 'Bronze',   50.0, 0.0);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('seed_silver',  75000.0,  'acct-0003', 'Silver',   50.0, 0.0);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('seed_gold',   500000.0,  'acct-0004', 'Gold',     50.0, 0.0);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('seed_platinum', 2000000.0, 'acct-0005', 'Platinum', 50.0, 0.0);

INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('seed_basic',    'IBM',  10,  500.0,    5000.0, '2026-01-02', 9.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('seed_bronze',   'IBM',  50,  500.0,   25000.0, '2026-01-02', 8.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('seed_silver',   'AAPL', 500, 150.0,   75000.0, '2026-01-02', 7.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('seed_gold',     'MSFT', 1250, 400.0, 500000.0, '2026-01-02', 6.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('seed_platinum', 'GOOG', 20000, 100.0, 2000000.0, '2026-01-02', 5.99);

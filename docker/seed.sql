--   Identical seed data for both engines, loaded after the schema.
--   Deliberately dialect-neutral so the exact same rows land in DB2 and PostgreSQL,
--   giving the parity harness a common baseline to reconcile against.

DELETE FROM Stock;
DELETE FROM Portfolio;

INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedBasic', 5000.0, 'ACCT-1001', 'Basic', 50.0, 0.0);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedBronze', 12500.0, 'ACCT-1002', 'Bronze', 120.0, 9.99);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedSilver', 75000.0, 'ACCT-1003', 'Silver', 250.0, 18.98);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedGold', 150000.0, 'ACCT-1004', 'Gold', 900.0, 26.97);
INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedPlatinum', 1250000.0, 'ACCT-1005', 'Platinum', 5000.0, 35.94);

INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedBasic', 'IBM', 20, 250.0, 5000.0, '2026-01-02', 9.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedBronze', 'IBM', 50, 250.0, 12500.0, '2026-01-02', 9.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedSilver', 'AAPL', 300, 250.0, 75000.0, '2026-01-02', 8.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedGold', 'AAPL', 400, 250.0, 100000.0, '2026-01-02', 7.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedGold', 'GOOG', 100, 500.0, 50000.0, '2026-01-02', 7.99);
INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedPlatinum', 'GOOG', 2500, 500.0, 1250000.0, '2026-01-02', 6.99);

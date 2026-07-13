-- Seed data for the DB2 source database (schema from createTables.ddl)
-- Run via: db2 -tf seed-db2.sql   (after connecting to the PORTFOLIO database)

INSERT INTO Portfolio(owner, total, accountID) VALUES ('Alice',   125000.50, 'ACCT-1001');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Bob',      98432.10, 'ACCT-1002');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Carol',   210987.65, 'ACCT-1003');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('David',    54321.00, 'ACCT-1004');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Emma',    345678.90, 'ACCT-1005');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Frank',    12345.67, 'ACCT-1006');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Grace',    87654.32, 'ACCT-1007');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Henry',   456789.01, 'ACCT-1008');

INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Alice', 'IBM',   100, 245.50, 24550.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Alice', 'AAPL',  200, 210.25, 42050.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Alice', 'MSFT',  120, 487.00, 58440.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Bob',   'GOOG',  150, 182.30, 27345.00, '2026-07-09', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Bob',   'TSLA',  180, 395.00, 71100.00, '2026-07-09', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Carol', 'IBM',   400, 245.50, 98200.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Carol', 'NVDA',  250, 450.75, 112687.50, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('David', 'AMZN',  240, 226.30, 54312.00, '2026-07-08', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Emma',  'META',  300, 715.60, 214680.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Emma',  'NFLX',  100, 1310.00, 131000.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Frank', 'ORCL',   60, 205.75, 12345.00, '2026-07-07', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Grace', 'IBM',   200, 245.50, 49100.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Grace', 'CSCO',  600,  64.25, 38550.00, '2026-07-09', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Henry', 'MSFT',  500, 487.00, 243500.00, '2026-07-10', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Henry', 'AAPL', 1000, 210.25, 210250.00, '2026-07-10', 9.99);

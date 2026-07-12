-- Seed "historical" data for the DB2 source database, representing pre-migration history.
INSERT INTO Portfolio(owner, total, accountID) VALUES ('John',   1234.56, 'acct-1001');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Karri', 12345.67, 'acct-1002');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Ryan',  23456.78, 'acct-1003');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Raunak',98765.43, 'acct-1004');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Greg', 123456.78, 'acct-1005');
INSERT INTO Portfolio(owner, total, accountID) VALUES ('Eric',1234567.89, 'acct-1006');

INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('John',  'IBM',   10, 120.00, 1200.00, '2024-01-02', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('John',  'AAPL',   5, 190.00,  950.00, '2024-01-02', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Karri', 'MSFT',  20, 370.00, 7400.00, '2024-02-14', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Ryan',  'GOOG',  15, 140.00, 2100.00, '2024-03-09', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Raunak','AMZN',  30, 175.00, 5250.00, '2024-04-21', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Greg',  'NVDA',  40, 900.00,36000.00, '2024-05-30', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Eric',  'TSLA', 100, 250.00,25000.00, '2024-06-15', 9.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('Eric',  'META',  50, 480.00,24000.00, '2024-06-15', 9.99);

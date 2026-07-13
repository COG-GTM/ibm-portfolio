-- Identical seed data loaded into BOTH DB2 and PostgreSQL for the parity verification.
-- One pre-existing portfolio per loyalty tier.
INSERT INTO Portfolio(owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedBasic',        500.0, 'acct-basic',    'Basic',    50.0,  9.99);
INSERT INTO Portfolio(owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedBronze',     12000.0, 'acct-bronze',   'Bronze',   41.01, 18.98);
INSERT INTO Portfolio(owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedSilver',     60000.0, 'acct-silver',   'Silver',   33.02, 26.97);
INSERT INTO Portfolio(owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedGold',      150000.0, 'acct-gold',     'Gold',     25.03, 34.96);
INSERT INTO Portfolio(owner, total, accountID, loyalty, balance, commissions) VALUES ('SeedPlatinum', 2000000.0, 'acct-platinum', 'Platinum', 17.04, 42.95);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedBronze', 'IBM',  80, 150.0, 12000.0, '2026-07-10', 8.99);
INSERT INTO Stock(owner, symbol, shares, price, total, dateQuoted, commission) VALUES ('SeedGold',  'MSFT', 375, 400.0, 150000.0, '2026-07-10', 7.99);

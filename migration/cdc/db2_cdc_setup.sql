-- Trigger-based change-data-capture on the DB2 source database.
-- Stands in for log-based CDC (Q-Replication / Debezium-for-DB2): every committed
-- INSERT/UPDATE/DELETE on Portfolio and Stock is appended, in commit order, to a
-- monotonically increasing change journal (CDC_CHANGES).  A replayer daemon applies
-- these changes to PostgreSQL in change_id order.
--
-- Run with:  db2 -td@ -f db2_cdc_setup.sql   (statement terminator is @)

CREATE TABLE CDC_CHANGES (
    change_id   BIGINT GENERATED ALWAYS AS IDENTITY (START WITH 1, INCREMENT BY 1) PRIMARY KEY,
    table_name  VARCHAR(16) NOT NULL,
    op          CHAR(1)     NOT NULL,   -- I / U / D
    owner       VARCHAR(32) NOT NULL,
    symbol      VARCHAR(8),             -- NULL for Portfolio rows
    p_total     DOUBLE,
    accountid   VARCHAR(64),
    shares      INTEGER,
    price       DOUBLE,
    s_total     DOUBLE,
    datequoted  VARCHAR(10),
    commission  DOUBLE,
    changed_at  TIMESTAMP NOT NULL DEFAULT CURRENT TIMESTAMP
)@

CREATE TRIGGER PORTFOLIO_INS AFTER INSERT ON Portfolio REFERENCING NEW AS n FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner, p_total, accountid)
    VALUES ('PORTFOLIO', 'I', n.owner, n.total, n.accountID)@

CREATE TRIGGER PORTFOLIO_UPD AFTER UPDATE ON Portfolio REFERENCING NEW AS n FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner, p_total, accountid)
    VALUES ('PORTFOLIO', 'U', n.owner, n.total, n.accountID)@

CREATE TRIGGER PORTFOLIO_DEL AFTER DELETE ON Portfolio REFERENCING OLD AS o FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner)
    VALUES ('PORTFOLIO', 'D', o.owner)@

CREATE TRIGGER STOCK_INS AFTER INSERT ON Stock REFERENCING NEW AS n FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner, symbol, shares, price, s_total, datequoted, commission)
    VALUES ('STOCK', 'I', n.owner, n.symbol, n.shares, n.price, n.total, n.dateQuoted, n.commission)@

CREATE TRIGGER STOCK_UPD AFTER UPDATE ON Stock REFERENCING NEW AS n FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner, symbol, shares, price, s_total, datequoted, commission)
    VALUES ('STOCK', 'U', n.owner, n.symbol, n.shares, n.price, n.total, n.dateQuoted, n.commission)@

CREATE TRIGGER STOCK_DEL AFTER DELETE ON Stock REFERENCING OLD AS o FOR EACH ROW
    INSERT INTO CDC_CHANGES(table_name, op, owner, symbol)
    VALUES ('STOCK', 'D', o.owner, o.symbol)@

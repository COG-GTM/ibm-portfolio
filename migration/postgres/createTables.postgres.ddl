-- PostgreSQL schema for the Portfolio microservice, converted from createTables.ddl (DB2).
-- Differences from the DB2 original:
--   * identifiers folded to lowercase (PostgreSQL default) to match EclipseLink's unquoted SQL
--   * DOUBLE PRECISION and VARCHAR are identical in both dialects, so column types are unchanged

CREATE TABLE portfolio(
    owner      VARCHAR(32) NOT NULL,
    total      DOUBLE PRECISION,
    accountid  VARCHAR(64),
    PRIMARY KEY(owner)
);

CREATE TABLE stock(
    owner      VARCHAR(32) NOT NULL,
    symbol     VARCHAR(8)  NOT NULL,
    shares     INTEGER,
    price      DOUBLE PRECISION,
    total      DOUBLE PRECISION,
    datequoted VARCHAR(10),
    commission DOUBLE PRECISION,
    FOREIGN KEY (owner) REFERENCES portfolio(owner) ON DELETE CASCADE,
    PRIMARY KEY(owner, symbol)
);

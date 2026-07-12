-- PostgreSQL version of createTables.ddl (converted from DB2).
--
-- Conversion notes (DB2 -> PostgreSQL):
--   * DOUBLE           -> DOUBLE PRECISION (accepted by both engines)
--   * VARCHAR(n)       -> VARCHAR(n)        (identical semantics)
--   * ON DELETE CASCADE and composite PRIMARY KEY syntax are identical
--   * No DB2 tablespace / bufferpool clauses are needed on PostgreSQL

CREATE TABLE Portfolio (
    owner     VARCHAR(32) NOT NULL,
    total     DOUBLE PRECISION,
    accountID VARCHAR(64),
    PRIMARY KEY (owner)
);

CREATE TABLE Stock (
    owner      VARCHAR(32) NOT NULL,
    symbol     VARCHAR(8)  NOT NULL,
    shares     INTEGER,
    price      DOUBLE PRECISION,
    total      DOUBLE PRECISION,
    dateQuoted VARCHAR(10),
    commission DOUBLE PRECISION,
    FOREIGN KEY (owner) REFERENCES Portfolio(owner) ON DELETE CASCADE,
    PRIMARY KEY (owner, symbol)
);

--       Copyright 2017-2021 IBM Corp All Rights Reserved

--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at

--       http://www.apache.org/licenses/LICENSE-2.0

--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.

-- PostgreSQL schema for the portfolio microservice, converted from the DB2 createTables.ddl.
-- Run via: psql -U <user> -d <db> -f createTables-postgres.sql
--
-- Type mappings (DB2 -> PostgreSQL): VARCHAR(n) -> VARCHAR(n), DOUBLE PRECISION -> DOUBLE
-- PRECISION (both IEEE-754 binary64), INTEGER -> INTEGER.  Constraints are identical.
-- Note: no stored procedures are required on PostgreSQL -- the loyalty tiering and commission
-- logic from stored-procs.ddl now lives in the Java service layer (TradePolicy.java).

CREATE TABLE Portfolio(
    owner       VARCHAR(32) NOT NULL,
    total       DOUBLE PRECISION,
    accountID   VARCHAR(64),
    loyalty     VARCHAR(8),
    balance     DOUBLE PRECISION,
    commissions DOUBLE PRECISION,
    PRIMARY KEY(owner)
);

CREATE TABLE Stock(
    owner       VARCHAR(32) NOT NULL,
    symbol      VARCHAR(8) NOT NULL,
    shares      INTEGER,
    price       DOUBLE PRECISION,
    total       DOUBLE PRECISION,
    dateQuoted  VARCHAR(10),
    commission  DOUBLE PRECISION,
    FOREIGN KEY (owner) REFERENCES Portfolio(owner) ON DELETE CASCADE,
    PRIMARY KEY(owner, symbol)
);

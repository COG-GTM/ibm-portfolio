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

--   PostgreSQL schema for the portfolio microservice.
--   Run this via "psql -h <host> -U <user> -d <db> -f createTables.ddl".
--
--   The DB2 schema this was migrated from is kept in createTables-db2.ddl.
--   Unlike DB2, this schema carries no stored procedures: the loyalty tiering and
--   commission rules now live in the Java service layer
--   (portfolio.rules.LoyaltyRules / portfolio.rules.CommissionRules).

CREATE TABLE IF NOT EXISTS Portfolio (
    owner       VARCHAR(32)      NOT NULL,
    total       DOUBLE PRECISION DEFAULT 0.0,
    accountID   VARCHAR(64),
    loyalty     VARCHAR(8)       DEFAULT 'Basic',
    balance     DOUBLE PRECISION DEFAULT 0.0,
    commissions DOUBLE PRECISION DEFAULT 0.0,
    PRIMARY KEY (owner),
    CONSTRAINT portfolio_loyalty_check
        CHECK (loyalty IS NULL OR loyalty IN ('Basic', 'Bronze', 'Silver', 'Gold', 'Platinum'))
);

CREATE TABLE IF NOT EXISTS Stock (
    owner      VARCHAR(32)      NOT NULL,
    symbol     VARCHAR(8)       NOT NULL,
    shares     INTEGER          DEFAULT 0,
    price      DOUBLE PRECISION DEFAULT 0.0,
    total      DOUBLE PRECISION DEFAULT 0.0,
    dateQuoted VARCHAR(10),
    commission DOUBLE PRECISION DEFAULT 0.0,
    PRIMARY KEY (owner, symbol),
    FOREIGN KEY (owner) REFERENCES Portfolio(owner) ON DELETE CASCADE
);

--   DB2 implicitly indexes the foreign key when it enforces ON DELETE CASCADE;
--   PostgreSQL does not, and every "stocks for this owner" query needs it.
CREATE INDEX IF NOT EXISTS stock_owner_idx ON Stock (owner);

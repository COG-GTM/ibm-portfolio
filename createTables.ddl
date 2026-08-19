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

--   Run this via "psql -f createTables.ddl" on PostgreSQL, or via "db2 -tf createTables.ddl" on DB2.
--   The loyalty tiering and commission rules live in the service layer (see
--   com.ibm.hybrid.cloud.sample.stocktrader.portfolio.rules), so no stored procedures are required.

CREATE TABLE Portfolio (
    owner       VARCHAR(32) NOT NULL,
    total       DOUBLE PRECISION,
    accountID   VARCHAR(64),
    loyalty     VARCHAR(8),
    balance     DOUBLE PRECISION,
    commissions DOUBLE PRECISION,
    CONSTRAINT pk_portfolio PRIMARY KEY (owner)
);

CREATE TABLE Stock (
    owner      VARCHAR(32) NOT NULL,
    symbol     VARCHAR(8)  NOT NULL,
    shares     INTEGER,
    price      DOUBLE PRECISION,
    total      DOUBLE PRECISION,
    dateQuoted VARCHAR(10),
    commission DOUBLE PRECISION,
    CONSTRAINT pk_stock PRIMARY KEY (owner, symbol),
    CONSTRAINT fk_stock_owner FOREIGN KEY (owner) REFERENCES Portfolio(owner) ON DELETE CASCADE
);

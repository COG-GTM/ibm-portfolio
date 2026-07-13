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

--   Run this via "db2 -td@ -f stored-procs.ddl" after createTables.ddl.
--   These procedures own the loyalty tiering and commission rules so the
--   same logic is enforced no matter which client updates the tables.

CREATE OR REPLACE PROCEDURE UPDATE_LOYALTY_LEVEL(
    IN P_OWNER VARCHAR(32),
    IN P_TOTAL DOUBLE,
    OUT P_LOYALTY VARCHAR(8))
LANGUAGE SQL
SPECIFIC UPDATE_LOYALTY_LEVEL
BEGIN
    DECLARE V_LOYALTY VARCHAR(8);

    SET V_LOYALTY =
        CASE
            WHEN P_TOTAL >= 1000000.0 THEN 'Platinum'
            WHEN P_TOTAL >=  100000.0 THEN 'Gold'
            WHEN P_TOTAL >=   50000.0 THEN 'Silver'
            WHEN P_TOTAL >=   10000.0 THEN 'Bronze'
            ELSE 'Basic'
        END;

    UPDATE Portfolio
       SET loyalty = V_LOYALTY
     WHERE owner = P_OWNER;

    SET P_LOYALTY = V_LOYALTY;
END
@

CREATE OR REPLACE PROCEDURE CALCULATE_COMMISSION(
    IN P_OWNER VARCHAR(32),
    IN P_TRADE_VALUE DOUBLE,
    OUT P_COMMISSION DOUBLE)
LANGUAGE SQL
SPECIFIC CALCULATE_COMMISSION
BEGIN
    DECLARE V_LOYALTY VARCHAR(8);
    DECLARE V_COMMISSION DOUBLE;

    SELECT COALESCE(loyalty, 'Basic')
      INTO V_LOYALTY
      FROM Portfolio
     WHERE owner = P_OWNER;

    -- Commission schedule is tiered by the client's loyalty level
    IF V_LOYALTY = 'Platinum' THEN
        SET V_COMMISSION = 5.99;
    ELSEIF V_LOYALTY = 'Gold' THEN
        SET V_COMMISSION = 6.99;
    ELSEIF V_LOYALTY = 'Silver' THEN
        SET V_COMMISSION = 7.99;
    ELSEIF V_LOYALTY = 'Bronze' THEN
        SET V_COMMISSION = 8.99;
    ELSE
        SET V_COMMISSION = 9.99;
    END IF;

    -- Large block trades incur an additional half basis point surcharge
    IF P_TRADE_VALUE > 250000.0 THEN
        SET V_COMMISSION = V_COMMISSION + (P_TRADE_VALUE * 0.00005);
    END IF;

    UPDATE Portfolio
       SET commissions = COALESCE(commissions, 0) + V_COMMISSION,
           balance = COALESCE(balance, 0) - V_COMMISSION
     WHERE owner = P_OWNER;

    SET P_COMMISSION = V_COMMISSION;
END
@

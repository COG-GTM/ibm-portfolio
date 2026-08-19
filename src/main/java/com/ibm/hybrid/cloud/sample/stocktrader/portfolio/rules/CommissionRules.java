/*
       Copyright 2017-2021 IBM Corp, All Rights Reserved
       Copyright 2023-2024 Kyndryl, All Rights Reserved

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
 */

package com.ibm.hybrid.cloud.sample.stocktrader.portfolio.rules;

/** Commission rules, lifted out of the DB2 CALCULATE_COMMISSION stored procedure as
 *  part of the PostgreSQL migration.  The procedure also debited the portfolio's
 *  balance; that persistence step now belongs to the caller, leaving this class pure.
 */
public final class CommissionRules {
	public static final double BASIC_COMMISSION    = 9.99;
	public static final double BRONZE_COMMISSION   = 8.99;
	public static final double SILVER_COMMISSION   = 7.99;
	public static final double GOLD_COMMISSION     = 6.99;
	public static final double PLATINUM_COMMISSION = 5.99;

	/** Trades above this value pay an extra half basis point. */
	public static final double BLOCK_TRADE_THRESHOLD = 250000.0;
	public static final double BLOCK_TRADE_RATE      = 0.00005;

	private CommissionRules() {
	}

	/** The commission owed on a trade of the given value by a client at the given loyalty level.
	 *  An unknown or missing loyalty level is treated as Basic, matching the procedure's COALESCE. */
	public static double commissionFor(String loyalty, double tradeValue) {
		double commission = baseCommissionFor(loyalty);

		if (tradeValue > BLOCK_TRADE_THRESHOLD) {
			commission += tradeValue * BLOCK_TRADE_RATE;
		}

		return commission;
	}

	public static double baseCommissionFor(String loyalty) {
		if (LoyaltyRules.PLATINUM.equals(loyalty)) return PLATINUM_COMMISSION;
		if (LoyaltyRules.GOLD.equals(loyalty))     return GOLD_COMMISSION;
		if (LoyaltyRules.SILVER.equals(loyalty))   return SILVER_COMMISSION;
		if (LoyaltyRules.BRONZE.equals(loyalty))   return BRONZE_COMMISSION;
		return BASIC_COMMISSION;
	}
}

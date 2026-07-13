/*
       Copyright 2017-2021 IBM Corp All Rights Reserved

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

package com.ibm.hybrid.cloud.sample.stocktrader.portfolio;

/** Loyalty tiering and commission schedule for portfolios.
 *
 *  These rules were previously enforced by the UPDATE_LOYALTY_LEVEL and CALCULATE_COMMISSION
 *  DB2 stored procedures (see stored-procs.ddl); they live here as plain functions so any
 *  JDBC backend (such as PostgreSQL) can use them without database-side procedures.
 */
public class TradePolicy {
	public static final String BASIC    = "Basic";
	public static final String BRONZE   = "Bronze";
	public static final String SILVER   = "Silver";
	public static final String GOLD     = "Gold";
	public static final String PLATINUM = "Platinum";

	private static final double PLATINUM_THRESHOLD = 1000000.0;
	private static final double GOLD_THRESHOLD     =  100000.0;
	private static final double SILVER_THRESHOLD   =   50000.0;
	private static final double BRONZE_THRESHOLD   =   10000.0;

	private static final double LARGE_TRADE_THRESHOLD = 250000.0;
	private static final double LARGE_TRADE_SURCHARGE_RATE = 0.00005; //half a basis point

	private TradePolicy() {
	}

	/** Determine the loyalty tier for a given overall portfolio value. */
	public static String loyaltyFor(double total) {
		if (total >= PLATINUM_THRESHOLD) return PLATINUM;
		if (total >= GOLD_THRESHOLD)     return GOLD;
		if (total >= SILVER_THRESHOLD)   return SILVER;
		if (total >= BRONZE_THRESHOLD)   return BRONZE;
		return BASIC;
	}

	/** Base per-trade commission for a loyalty tier (null/unknown tiers pay the Basic rate). */
	public static double baseCommission(String loyalty) {
		if (PLATINUM.equals(loyalty)) return 5.99;
		if (GOLD.equals(loyalty))     return 6.99;
		if (SILVER.equals(loyalty))   return 7.99;
		if (BRONZE.equals(loyalty))   return 8.99;
		return 9.99;
	}

	/** Commission for a trade: tiered base rate plus a half-basis-point surcharge on large block trades. */
	public static double commissionFor(String loyalty, double tradeValue) {
		double commission = baseCommission(loyalty);
		if (tradeValue > LARGE_TRADE_THRESHOLD) {
			commission += tradeValue * LARGE_TRADE_SURCHARGE_RATE;
		}
		return commission;
	}
}

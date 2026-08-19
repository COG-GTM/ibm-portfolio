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

/** Loyalty tiering rules, lifted out of the DB2 UPDATE_LOYALTY_LEVEL stored procedure
 *  as part of the PostgreSQL migration.  The thresholds and their ordering are the
 *  contract, so they are asserted directly by LoyaltyRulesTest.
 */
public final class LoyaltyRules {
	public static final String BASIC    = "Basic";
	public static final String BRONZE   = "Bronze";
	public static final String SILVER   = "Silver";
	public static final String GOLD     = "Gold";
	public static final String PLATINUM = "Platinum";

	public static final double BRONZE_THRESHOLD   =   10000.0;
	public static final double SILVER_THRESHOLD   =   50000.0;
	public static final double GOLD_THRESHOLD     =  100000.0;
	public static final double PLATINUM_THRESHOLD = 1000000.0;

	private LoyaltyRules() {
	}

	/** The loyalty level earned by a portfolio worth the given total. */
	public static String levelFor(double total) {
		if (total >= PLATINUM_THRESHOLD) return PLATINUM;
		if (total >= GOLD_THRESHOLD)     return GOLD;
		if (total >= SILVER_THRESHOLD)   return SILVER;
		if (total >= BRONZE_THRESHOLD)   return BRONZE;
		return BASIC;
	}
}

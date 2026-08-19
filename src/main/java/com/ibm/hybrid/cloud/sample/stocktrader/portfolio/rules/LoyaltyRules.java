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

/** Loyalty tiering rules.  These were previously enforced by the UPDATE_LOYALTY_LEVEL
 *  DB2 stored procedure; they now live here so they are database independent.
 */
public final class LoyaltyRules {

	public static final String BASIC    = "Basic";
	public static final String BRONZE   = "Bronze";
	public static final String SILVER   = "Silver";
	public static final String GOLD     = "Gold";
	public static final String PLATINUM = "Platinum";

	public static final double BRONZE_THRESHOLD   =    10000.0;
	public static final double SILVER_THRESHOLD   =    50000.0;
	public static final double GOLD_THRESHOLD     =   100000.0;
	public static final double PLATINUM_THRESHOLD =  1000000.0;

	private LoyaltyRules() {
	}

	/** The loyalty level earned by a portfolio of the given total value. */
	public static String loyaltyFor(double total) {
		if (total >= PLATINUM_THRESHOLD) return PLATINUM;
		if (total >= GOLD_THRESHOLD)     return GOLD;
		if (total >= SILVER_THRESHOLD)   return SILVER;
		if (total >= BRONZE_THRESHOLD)   return BRONZE;
		return BASIC;
	}

	/** Normalizes a loyalty value read from the database, where it may be null. */
	public static String normalize(String loyalty) {
		return (loyalty == null) || loyalty.isEmpty() ? BASIC : loyalty;
	}
}

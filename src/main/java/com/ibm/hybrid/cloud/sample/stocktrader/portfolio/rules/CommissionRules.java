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

/** Tiered commission schedule.  These were previously enforced by the CALCULATE_COMMISSION
 *  DB2 stored procedure; they now live here so they are database independent.
 */
public final class CommissionRules {

	public static final double PLATINUM_COMMISSION = 5.99;
	public static final double GOLD_COMMISSION     = 6.99;
	public static final double SILVER_COMMISSION   = 7.99;
	public static final double BRONZE_COMMISSION   = 8.99;
	public static final double BASIC_COMMISSION    = 9.99;

	/** Trades above this value incur the block trade surcharge. */
	public static final double BLOCK_TRADE_THRESHOLD = 250000.0;

	/** Half a basis point of the trade value. */
	public static final double BLOCK_TRADE_RATE = 0.00005;

	private CommissionRules() {
	}

	/** The base commission for a client at the given loyalty level. */
	public static double baseCommissionFor(String loyalty) {
		switch (LoyaltyRules.normalize(loyalty)) {
			case LoyaltyRules.PLATINUM: return PLATINUM_COMMISSION;
			case LoyaltyRules.GOLD:     return GOLD_COMMISSION;
			case LoyaltyRules.SILVER:   return SILVER_COMMISSION;
			case LoyaltyRules.BRONZE:   return BRONZE_COMMISSION;
			default:                    return BASIC_COMMISSION;
		}
	}

	/** The commission charged for a trade of the given value by a client at the given
	 *  loyalty level, including the block trade surcharge where it applies.
	 */
	public static double commissionFor(String loyalty, double tradeValue) {
		double commission = baseCommissionFor(loyalty);

		if (tradeValue > BLOCK_TRADE_THRESHOLD) {
			commission = commission + (tradeValue * BLOCK_TRADE_RATE);
		}

		return commission;
	}
}

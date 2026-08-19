/*
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

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Verifies the commission schedule lifted out of the CALCULATE_COMMISSION DB2 stored procedure. */
public class CommissionRulesTest {

	private static final double TOLERANCE = 0.000001;

	@Test
	public void baseCommissionPerTier() {
		assertEquals(5.99, CommissionRules.baseCommissionFor("Platinum"), TOLERANCE);
		assertEquals(6.99, CommissionRules.baseCommissionFor("Gold"),     TOLERANCE);
		assertEquals(7.99, CommissionRules.baseCommissionFor("Silver"),   TOLERANCE);
		assertEquals(8.99, CommissionRules.baseCommissionFor("Bronze"),   TOLERANCE);
		assertEquals(9.99, CommissionRules.baseCommissionFor("Basic"),    TOLERANCE);
	}

	@Test
	public void unknownAndNullLoyaltyFallBackToBasic() {
		assertEquals(9.99, CommissionRules.baseCommissionFor(null),       TOLERANCE);
		assertEquals(9.99, CommissionRules.baseCommissionFor(""),         TOLERANCE);
		assertEquals(9.99, CommissionRules.baseCommissionFor("Titanium"), TOLERANCE);
	}

	@Test
	public void smallTradesPayTheBaseCommissionOnly() {
		assertEquals(9.99, CommissionRules.commissionFor("Basic", 0.0),       TOLERANCE);
		assertEquals(6.99, CommissionRules.commissionFor("Gold", 100000.0),   TOLERANCE);
	}

	@Test
	public void blockTradeSurchargeAppliesStrictlyAboveThreshold() {
		//exactly at the threshold: no surcharge
		assertEquals(7.99, CommissionRules.commissionFor("Silver", 250000.0), TOLERANCE);

		//just above: base + half a basis point of the trade value
		assertEquals(7.99 + (250001.0 * 0.00005), CommissionRules.commissionFor("Silver", 250001.0), TOLERANCE);

		//a large platinum block trade
		assertEquals(5.99 + (2000000.0 * 0.00005), CommissionRules.commissionFor("Platinum", 2000000.0), TOLERANCE);
	}

	@Test
	public void surchargeUsesLoyaltyAtTradeStart() {
		//a Basic client placing the trade that will promote them still pays the Basic rate
		assertEquals(9.99 + (1000000.0 * 0.00005), CommissionRules.commissionFor("Basic", 1000000.0), TOLERANCE);
	}
}

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

/** Pins the commission schedule that used to live in the DB2 CALCULATE_COMMISSION procedure. */
public class CommissionRulesTest {
	private static final double DELTA = 0.000001;

	@Test
	public void commissionIsTieredByLoyaltyLevel() {
		assertEquals(5.99, CommissionRules.commissionFor("Platinum", 1000.0), DELTA);
		assertEquals(6.99, CommissionRules.commissionFor("Gold",     1000.0), DELTA);
		assertEquals(7.99, CommissionRules.commissionFor("Silver",   1000.0), DELTA);
		assertEquals(8.99, CommissionRules.commissionFor("Bronze",   1000.0), DELTA);
		assertEquals(9.99, CommissionRules.commissionFor("Basic",    1000.0), DELTA);
	}

	@Test
	public void unknownOrMissingLoyaltyIsChargedAsBasic() {
		assertEquals(9.99, CommissionRules.commissionFor(null,        1000.0), DELTA);
		assertEquals(9.99, CommissionRules.commissionFor("Titanium",  1000.0), DELTA);
		assertEquals(9.99, CommissionRules.commissionFor("platinum",  1000.0), DELTA); //the procedure compared case sensitively
	}

	@Test
	public void blockTradesPayAnExtraHalfBasisPoint() {
		assertEquals(5.99 + 300000.0 * 0.00005, CommissionRules.commissionFor("Platinum", 300000.0), DELTA);
		assertEquals(9.99 + 500000.0 * 0.00005, CommissionRules.commissionFor("Basic",    500000.0), DELTA);
	}

	@Test
	public void blockTradeSurchargeStartsStrictlyAboveTheThreshold() {
		assertEquals(7.99, CommissionRules.commissionFor("Silver", 250000.0), DELTA);
		assertEquals(7.99 + 250000.01 * 0.00005, CommissionRules.commissionFor("Silver", 250000.01), DELTA);
	}

	@Test
	public void baseCommissionIgnoresTradeValue() {
		assertEquals(6.99, CommissionRules.baseCommissionFor("Gold"), DELTA);
	}
}

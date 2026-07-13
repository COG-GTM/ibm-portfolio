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

package com.ibm.hybrid.cloud.sample.stocktrader.portfolio.test;

import static org.junit.Assert.assertEquals;

import com.ibm.hybrid.cloud.sample.stocktrader.portfolio.TradePolicy;

import org.junit.Test;

/** Pins the lifted loyalty/commission logic to the behavior of the legacy DB2 stored
 *  procedures UPDATE_LOYALTY_LEVEL and CALCULATE_COMMISSION (see stored-procs.ddl). */
public class TradePolicyTest {
	private static final double EXACT = 0.0; //double math must match the procs bit-for-bit

	@Test
	public void loyaltyTierBoundaries() {
		assertEquals("Basic",    TradePolicy.loyaltyFor(0.0));
		assertEquals("Basic",    TradePolicy.loyaltyFor(9999.99));
		assertEquals("Bronze",   TradePolicy.loyaltyFor(10000.0));
		assertEquals("Bronze",   TradePolicy.loyaltyFor(49999.99));
		assertEquals("Silver",   TradePolicy.loyaltyFor(50000.0));
		assertEquals("Silver",   TradePolicy.loyaltyFor(99999.99));
		assertEquals("Gold",     TradePolicy.loyaltyFor(100000.0));
		assertEquals("Gold",     TradePolicy.loyaltyFor(999999.99));
		assertEquals("Platinum", TradePolicy.loyaltyFor(1000000.0));
		assertEquals("Platinum", TradePolicy.loyaltyFor(5000000.0));
	}

	@Test
	public void loyaltyForNegativeTotalIsBasic() {
		assertEquals("Basic", TradePolicy.loyaltyFor(-1.0));
	}

	@Test
	public void baseCommissionSchedule() {
		assertEquals(5.99, TradePolicy.baseCommission("Platinum"), EXACT);
		assertEquals(6.99, TradePolicy.baseCommission("Gold"),     EXACT);
		assertEquals(7.99, TradePolicy.baseCommission("Silver"),   EXACT);
		assertEquals(8.99, TradePolicy.baseCommission("Bronze"),   EXACT);
		assertEquals(9.99, TradePolicy.baseCommission("Basic"),    EXACT);
	}

	@Test
	public void unknownOrNullLoyaltyPaysBasicRate() {
		assertEquals(9.99, TradePolicy.baseCommission(null),      EXACT);
		assertEquals(9.99, TradePolicy.baseCommission("Diamond"), EXACT);
	}

	@Test
	public void noSurchargeAtOrBelowThreshold() {
		assertEquals(9.99, TradePolicy.commissionFor("Basic", 250000.0), EXACT);
		assertEquals(6.99, TradePolicy.commissionFor("Gold",  100.0),    EXACT);
	}

	@Test
	public void halfBasisPointSurchargeAboveThreshold() {
		//matches the proc: commission = base + tradeValue * 0.00005 when tradeValue > 250000
		assertEquals(9.99 + 250000.01 * 0.00005, TradePolicy.commissionFor("Basic", 250000.01),  EXACT);
		assertEquals(5.99 + 1000000.0 * 0.00005, TradePolicy.commissionFor("Platinum", 1000000.0), EXACT);
	}
}

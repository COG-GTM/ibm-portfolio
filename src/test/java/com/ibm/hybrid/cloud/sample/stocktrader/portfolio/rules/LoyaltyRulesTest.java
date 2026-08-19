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

/** Verifies the tier table lifted out of the UPDATE_LOYALTY_LEVEL DB2 stored procedure. */
public class LoyaltyRulesTest {

	@Test
	public void basicTier() {
		assertEquals("Basic", LoyaltyRules.loyaltyFor(0.0));
		assertEquals("Basic", LoyaltyRules.loyaltyFor(9999.99));
		assertEquals("Basic", LoyaltyRules.loyaltyFor(-100.0));
	}

	@Test
	public void tierBoundariesAreInclusiveLowerBounds() {
		assertEquals("Bronze",   LoyaltyRules.loyaltyFor(10000.0));
		assertEquals("Basic",    LoyaltyRules.loyaltyFor(9999.999));
		assertEquals("Silver",   LoyaltyRules.loyaltyFor(50000.0));
		assertEquals("Bronze",   LoyaltyRules.loyaltyFor(49999.999));
		assertEquals("Gold",     LoyaltyRules.loyaltyFor(100000.0));
		assertEquals("Silver",   LoyaltyRules.loyaltyFor(99999.999));
		assertEquals("Platinum", LoyaltyRules.loyaltyFor(1000000.0));
		assertEquals("Gold",     LoyaltyRules.loyaltyFor(999999.999));
	}

	@Test
	public void midTierValues() {
		assertEquals("Bronze",   LoyaltyRules.loyaltyFor(25000.0));
		assertEquals("Silver",   LoyaltyRules.loyaltyFor(75000.0));
		assertEquals("Gold",     LoyaltyRules.loyaltyFor(500000.0));
		assertEquals("Platinum", LoyaltyRules.loyaltyFor(12000000.0));
	}

	@Test
	public void normalizeMatchesCoalesceInSql() {
		assertEquals("Basic", LoyaltyRules.normalize(null));
		assertEquals("Basic", LoyaltyRules.normalize(""));
		assertEquals("Gold",  LoyaltyRules.normalize("Gold"));
	}
}

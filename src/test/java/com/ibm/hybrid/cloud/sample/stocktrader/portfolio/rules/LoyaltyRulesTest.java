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

/** Pins the tiering behavior that used to live in the DB2 UPDATE_LOYALTY_LEVEL procedure. */
public class LoyaltyRulesTest {

	@Test
	public void belowBronzeThresholdIsBasic() {
		assertEquals("Basic", LoyaltyRules.levelFor(0.0));
		assertEquals("Basic", LoyaltyRules.levelFor(9999.99));
	}

	@Test
	public void eachThresholdIsInclusive() {
		assertEquals("Bronze",   LoyaltyRules.levelFor(10000.0));
		assertEquals("Silver",   LoyaltyRules.levelFor(50000.0));
		assertEquals("Gold",     LoyaltyRules.levelFor(100000.0));
		assertEquals("Platinum", LoyaltyRules.levelFor(1000000.0));
	}

	@Test
	public void justBelowEachThresholdStaysInTheLowerTier() {
		assertEquals("Basic",  LoyaltyRules.levelFor(9999.999));
		assertEquals("Bronze", LoyaltyRules.levelFor(49999.99));
		assertEquals("Silver", LoyaltyRules.levelFor(99999.99));
		assertEquals("Gold",   LoyaltyRules.levelFor(999999.99));
	}

	@Test
	public void wellAboveTopThresholdStaysPlatinum() {
		assertEquals("Platinum", LoyaltyRules.levelFor(87654321.0));
	}

	@Test
	public void negativeTotalIsBasic() {
		assertEquals("Basic", LoyaltyRules.levelFor(-1.0));
	}
}

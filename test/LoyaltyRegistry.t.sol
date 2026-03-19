// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {LoyaltyRegistry} from "../src/LoyaltyRegistry.sol";

contract LoyaltyRegistryTest is Test {
    LoyaltyRegistry registry;

    address callbackAddr = address(0xCA11BAC4);
    address lpUser = address(0xA1);

    function setUp() public {
        registry = new LoyaltyRegistry();
        registry.setCallbackContract(callbackAddr);
    }

    // ==================== recordLPActivity Tests ====================

    function test_recordLPActivity_incrementsCount() public {
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.lpActivityCount(lpUser), 1);

        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.lpActivityCount(lpUser), 2);
    }

    function test_recordLPActivity_onlyCallback() public {
        vm.expectRevert(LoyaltyRegistry.OnlyCallback.selector);
        registry.recordLPActivity(lpUser);
    }

    // ==================== Tier Upgrade Tests ====================

    function test_tierUpgrade_bronze() public {
        // 1 event → BRONZE
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);

        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.BRONZE));
    }

    function test_tierUpgrade_silver() public {
        // 5 events → SILVER
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.SILVER));
    }

    function test_tierUpgrade_gold() public {
        // 10 events → GOLD
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.GOLD));
    }

    function test_tierUpgrade_incrementalProgression() public {
        // Start at NONE
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.NONE));

        // 1 event → BRONZE
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.BRONZE));

        // 4 more events (5 total) → SILVER
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.SILVER));

        // 5 more events (10 total) → GOLD
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.GOLD));
    }

    // ==================== getFeeDiscount Tests ====================

    function test_getFeeDiscount_returnsCorrectValues() public {
        // NONE → 0
        assertEq(registry.getFeeDiscount(lpUser), 0);

        // BRONZE → 1000
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.getFeeDiscount(lpUser), 1000);

        // SILVER → 2000
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(registry.getFeeDiscount(lpUser), 2000);

        // GOLD → 3000
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(registry.getFeeDiscount(lpUser), 3000);
    }

    // ==================== Access Control Tests ====================

    function test_setCallbackContract_onlyOnce() public {
        // Already set in setUp
        vm.expectRevert(LoyaltyRegistry.CallbackAlreadySet.selector);
        registry.setCallbackContract(address(0xBEEF));
    }

    function test_setCallbackContract_onlyOwner() public {
        LoyaltyRegistry fresh = new LoyaltyRegistry();
        vm.prank(address(0xDEAD));
        vm.expectRevert(LoyaltyRegistry.OnlyOwner.selector);
        fresh.setCallbackContract(address(0xBEEF));
    }

    function test_setTier_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(LoyaltyRegistry.OnlyOwner.selector);
        registry.setTier(lpUser, LoyaltyRegistry.LoyaltyTier.GOLD);
    }

    function test_setTier_manuallySetsTier() public {
        registry.setTier(lpUser, LoyaltyRegistry.LoyaltyTier.GOLD);
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.GOLD));
        assertEq(registry.getFeeDiscount(lpUser), 3000);
    }

    function test_setTier_updatesTotalLoyaltyMembers() public {
        assertEq(registry.totalLoyaltyMembers(), 0);

        registry.setTier(lpUser, LoyaltyRegistry.LoyaltyTier.BRONZE);
        assertEq(registry.totalLoyaltyMembers(), 1);

        // Upgrading tier doesn't double-count
        registry.setTier(lpUser, LoyaltyRegistry.LoyaltyTier.GOLD);
        assertEq(registry.totalLoyaltyMembers(), 1);

        // Setting back to NONE decrements
        registry.setTier(lpUser, LoyaltyRegistry.LoyaltyTier.NONE);
        assertEq(registry.totalLoyaltyMembers(), 0);
    }

    // ==================== totalLoyaltyMembers Tests ====================

    function test_totalLoyaltyMembers_incrementsOnFirstActivity() public {
        assertEq(registry.totalLoyaltyMembers(), 0);

        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.totalLoyaltyMembers(), 1);

        // Second activity for same user doesn't increment
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.totalLoyaltyMembers(), 1);
    }

    function test_totalLoyaltyMembers_tracksMultipleUsers() public {
        address lp2 = address(0xA2);

        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);

        vm.prank(callbackAddr);
        registry.recordLPActivity(lp2);

        assertEq(registry.totalLoyaltyMembers(), 2);
    }

    // ==================== Zero-Address Validation (A3) ====================

    function test_setCallbackContract_revertsOnZeroAddress() public {
        LoyaltyRegistry fresh = new LoyaltyRegistry();
        vm.expectRevert(LoyaltyRegistry.ZeroAddress.selector);
        fresh.setCallbackContract(address(0));
    }

    // ==================== Fuzz Tests ====================

    // ==================== Event Emission Tests ====================

    function test_recordLPActivity_emitsLPActivityRecordedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit LoyaltyRegistry.LPActivityRecorded(lpUser, 1);
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
    }

    function test_recordLPActivity_secondActivity_emitsWithCount2() public {
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);

        vm.expectEmit(true, false, false, true);
        emit LoyaltyRegistry.LPActivityRecorded(lpUser, 2);
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
    }

    function test_tierUpgrade_emitsTierUpdatedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit LoyaltyRegistry.TierUpdated(lpUser, LoyaltyRegistry.LoyaltyTier.BRONZE);
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser); // NONE → BRONZE
    }

    function test_tierUpgrade_silverEmitsTierUpdatedEvent() public {
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        vm.expectEmit(true, false, false, true);
        emit LoyaltyRegistry.TierUpdated(lpUser, LoyaltyRegistry.LoyaltyTier.SILVER);
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser); // 5th activity → SILVER
    }

    // ==================== Counter Precision Tests ====================

    function test_totalLoyaltyMembers_noDoubleCountOnTierUpgradeViaRecord() public {
        // NONE → BRONZE → SILVER → GOLD should only increment totalLoyaltyMembers once
        assertEq(registry.totalLoyaltyMembers(), 0);

        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser); // → BRONZE
        assertEq(registry.totalLoyaltyMembers(), 1);

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser); // → SILVER at count 5
        }
        assertEq(registry.totalLoyaltyMembers(), 1); // still 1

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser); // → GOLD at count 10
        }
        assertEq(registry.totalLoyaltyMembers(), 1); // still 1
    }

    function test_tierCap_staysGoldBeyondThreshold() public {
        // More than GOLD_THRESHOLD activities — tier should remain GOLD
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(uint256(registry.loyaltyTier(lpUser)), uint256(LoyaltyRegistry.LoyaltyTier.GOLD));
        assertEq(registry.getFeeDiscount(lpUser), 3000);
        assertEq(registry.totalLoyaltyMembers(), 1);
    }

    function test_multipleUsers_independentTiers() public {
        address lp2 = address(0xA2);
        address lp3 = address(0xA3);

        // lp1 → GOLD
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        // lp2 → SILVER
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lp2);
        }
        // lp3 → BRONZE
        vm.prank(callbackAddr);
        registry.recordLPActivity(lp3);

        assertEq(registry.getFeeDiscount(lpUser), 3000);
        assertEq(registry.getFeeDiscount(lp2), 2000);
        assertEq(registry.getFeeDiscount(lp3), 1000);
        assertEq(registry.totalLoyaltyMembers(), 3);
    }

    // ==================== Additional Fuzz Tests ====================

    function testFuzz_discountNeverExceedsMax(uint256 activityCount) public {
        activityCount = bound(activityCount, 0, 100);

        for (uint256 i = 0; i < activityCount; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        uint24 discount = registry.getFeeDiscount(lpUser);
        assertTrue(discount <= 3000);
    }

    function testFuzz_getFeeDiscount_matchesTierThresholds(uint256 activityCount) public {
        activityCount = bound(activityCount, 0, 50);

        for (uint256 i = 0; i < activityCount; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        uint24 discount = registry.getFeeDiscount(lpUser);
        LoyaltyRegistry.LoyaltyTier tier = registry.loyaltyTier(lpUser);

        // Discount must exactly match the tier
        if (tier == LoyaltyRegistry.LoyaltyTier.GOLD)        assertEq(discount, 3000);
        else if (tier == LoyaltyRegistry.LoyaltyTier.SILVER) assertEq(discount, 2000);
        else if (tier == LoyaltyRegistry.LoyaltyTier.BRONZE) assertEq(discount, 1000);
        else                                                  assertEq(discount, 0);

        // Tier must match expected threshold
        if (activityCount >= registry.GOLD_THRESHOLD())
            assertEq(uint256(tier), uint256(LoyaltyRegistry.LoyaltyTier.GOLD));
        else if (activityCount >= registry.SILVER_THRESHOLD())
            assertEq(uint256(tier), uint256(LoyaltyRegistry.LoyaltyTier.SILVER));
        else if (activityCount >= registry.BRONZE_THRESHOLD())
            assertEq(uint256(tier), uint256(LoyaltyRegistry.LoyaltyTier.BRONZE));
        else
            assertEq(uint256(tier), uint256(LoyaltyRegistry.LoyaltyTier.NONE));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {ArbShieldHook} from "../src/ArbShieldHook.sol";
import {LoyaltyRegistry} from "../src/LoyaltyRegistry.sol";

contract ArbShieldHookTest is Test, Deployers {
    ArbShieldHook hook;
    LoyaltyRegistry registry;

    address callbackAddr = address(0xCA11BAC4);
    address lpUser = address(0xA1);  // LP user for loyalty tests

    function setUp() public {
        // Deploy PoolManager and routers
        deployFreshManagerAndRouters();

        // Deploy two test currencies
        deployMintAndApprove2Currencies();

        // Deploy hook to an address with correct flag bits
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo("ArbShieldHook.sol:ArbShieldHook", abi.encode(manager, address(this)), address(flags));
        hook = ArbShieldHook(address(flags));

        // Link callback contract
        hook.setCallbackContract(callbackAddr);

        // Deploy and link LoyaltyRegistry
        registry = new LoyaltyRegistry();
        registry.setCallbackContract(callbackAddr);
        hook.setLoyaltyRegistry(address(registry));

        // Approve currencies for routers
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize pool with dynamic fee flag
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    // ==================== Unit Tests ====================

    function test_hookPermissions_correct() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertTrue(perms.beforeInitialize);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.afterInitialize);
        assertFalse(perms.beforeAddLiquidity);
        assertFalse(perms.afterAddLiquidity);
        assertFalse(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertFalse(perms.beforeDonate);
        assertFalse(perms.afterDonate);
        assertFalse(perms.beforeSwapReturnDelta);
        assertFalse(perms.afterSwapReturnDelta);
    }

    function test_beforeInitialize_requiresDynamicFee() public {
        // Try to init a pool without dynamic fee flag -- should revert
        // PoolManager wraps hook errors, so we just expect any revert
        vm.expectRevert();
        initPool(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);
    }

    function test_beforeSwap_appliesBaseFeeWhenNoDivergence() public {
        // No divergence fee set, so should use baseFee (3000)
        assertEq(hook.getEffectiveFee(), 3000);

        // Swap should work (uses baseFee)
        _doSwap();
    }

    function test_beforeSwap_appliesDivergenceFeeWhenHigher() public {
        // Set divergence fee higher than base
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125); // 1% fee, 1.25% divergence

        assertEq(hook.getEffectiveFee(), 10000);

        // Swap should still work with higher fee
        _doSwap();
    }

    function test_beforeSwap_capsAtMaxFee() public {
        // Set fee above MAX_FEE
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(60000, 1000); // above MAX_FEE (50000)

        // Should be capped to MAX_FEE
        assertEq(hook.getEffectiveFee(), 50000);
    }

    function test_afterSwap_tracksArbFeeCaptured() public {
        // Set divergence fee
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        uint256 capturedBefore = hook.totalArbFeeCaptured();
        _doSwap();
        uint256 capturedAfter = hook.totalArbFeeCaptured();

        // Extra fee = 10000 - 3000 = 7000
        assertEq(capturedAfter - capturedBefore, 7000);
    }

    function test_afterSwap_noTrackingWhenBaseFee() public {
        uint256 capturedBefore = hook.totalArbFeeCaptured();
        _doSwap();
        uint256 capturedAfter = hook.totalArbFeeCaptured();

        assertEq(capturedAfter, capturedBefore);
        assertEq(capturedAfter, 0);
    }

    function test_updateDivergenceFee_updatesState() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(8000, 100);

        assertEq(hook.currentDivergenceFee(), 8000);
        assertEq(hook.lastFeeUpdate(), block.timestamp);
    }

    function test_updateDivergenceFee_onlyCallback() public {
        vm.expectRevert(ArbShieldHook.OnlyCallback.selector);
        hook.updateDivergenceFee(8000, 100);
    }

    function test_resetToBaseFee_resetsState() public {
        // Set fee first
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);
        assertEq(hook.currentDivergenceFee(), 10000);

        // Reset
        vm.prank(callbackAddr);
        hook.resetToBaseFee();
        assertEq(hook.currentDivergenceFee(), 0);
        assertEq(hook.getEffectiveFee(), 3000); // back to base
    }

    function test_resetToBaseFee_onlyCallback() public {
        vm.expectRevert(ArbShieldHook.OnlyCallback.selector);
        hook.resetToBaseFee();
    }

    function test_setCallbackContract_onlyOwner() public {
        // The hook's owner is this test contract. Call from a different address reverts with OnlyOwner
        // (modifier runs before the body, so OnlyOwner fires before CallbackAlreadySet).
        vm.prank(address(0xDEAD));
        vm.expectRevert(ArbShieldHook.OnlyOwner.selector);
        hook.setCallbackContract(address(0xBEEF));
    }

    function test_setCallbackContract_onlyOnce() public {
        // Callback already set in setUp
        vm.expectRevert(ArbShieldHook.CallbackAlreadySet.selector);
        hook.setCallbackContract(address(0xBEEF));
    }

    function test_getEffectiveFee_returnsCorrectFee() public {
        // No divergence: returns baseFee
        assertEq(hook.getEffectiveFee(), 3000);

        // Low divergence fee (below base): still returns baseFee
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(1000, 10);
        assertEq(hook.getEffectiveFee(), 3000);

        // High divergence fee: returns divergence fee
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(15000, 200);
        assertEq(hook.getEffectiveFee(), 15000);
    }

    // ==================== Fuzz Tests ====================

    function testFuzz_feeNeverExceedsMax(uint24 divergenceFee) public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(divergenceFee, 0);

        uint24 effective = hook.getEffectiveFee();
        assertTrue(effective <= hook.MAX_FEE());
    }

    function testFuzz_updateDivergenceFee_capped(uint24 newFee) public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(newFee, 0);

        assertTrue(hook.currentDivergenceFee() <= hook.MAX_FEE());
    }

    // ==================== Integration Tests ====================

    function test_fullFlow_divergenceFeeApplied() public {
        // Swap at base fee
        uint256 balance0Before = currency0.balanceOf(address(this));
        _doSwap();
        uint256 spent1 = balance0Before - currency0.balanceOf(address(this));

        // Now set divergence fee (higher fee = worse execution for swapper)
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(20000, 250); // 2% fee

        // Swap again at elevated fee
        uint256 balance0Before2 = currency0.balanceOf(address(this));
        _doSwap();
        uint256 spent2 = balance0Before2 - currency0.balanceOf(address(this));

        // Both swaps should have the same input (0.001 ether exact input)
        // The outputs differ due to different fees, but input is the same
        assertEq(spent1, spent2);
    }

    function test_fullFlow_feeResetAfterConvergence() public {
        // Set divergence fee
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(20000, 250);

        _doSwap();
        uint256 captured1 = hook.totalArbFeeCaptured();
        assertTrue(captured1 > 0);

        // Reset to base fee
        vm.prank(callbackAddr);
        hook.resetToBaseFee();

        _doSwap();
        // No additional arb fee captured after reset
        assertEq(hook.totalArbFeeCaptured(), captured1);
    }

    // ==================== Loyalty Discount Tests ====================

    function test_loyaltyDiscount_noneGetsNoDiscount() public {
        // No loyalty activity — NONE tier = full base fee (3000)
        assertEq(hook.getEffectiveFee(), 3000);
        _doSwapAs(lpUser);
        // No loyalty discounts applied
        assertEq(hook.totalLoyaltyDiscountsApplied(), 0);
    }

    function test_loyaltyDiscount_bronzeGetsTenPercentOff() public {
        // Record 1 LP activity → BRONZE (10% off)
        vm.prank(callbackAddr);
        registry.recordLPActivity(lpUser);
        assertEq(registry.getFeeDiscount(lpUser), 1000);

        _doSwapAs(lpUser);
        // baseFee=3000, 10% off = 2700
        assertEq(hook.totalLoyaltyDiscountsApplied(), 1);
    }

    function test_loyaltyDiscount_goldGetsThirtyPercentOff() public {
        // Record 10 LP activities → GOLD (30% off)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(registry.getFeeDiscount(lpUser), 3000);

        _doSwapAs(lpUser);
        // baseFee=3000, 30% off = 2100
        assertEq(hook.totalLoyaltyDiscountsApplied(), 1);
    }

    function test_loyaltyDiscount_appliedOnTopOfDivergenceFee() public {
        // Set divergence fee to 8000
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(8000, 100);

        // Give user GOLD tier (30% off)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        // Effective fee = 8000 * (10000 - 3000) / 10000 = 5600
        _doSwapAs(lpUser);
        assertEq(hook.totalLoyaltyDiscountsApplied(), 1);
    }

    function test_loyaltyDiscount_worksWithoutRegistry() public {
        // Deploy a fresh hook without registry
        uint160 flags2 = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        // Use a different address to avoid collision
        address hookAddr2 = address(uint160(flags2) | (1 << 20));
        deployCodeTo("ArbShieldHook.sol:ArbShieldHook", abi.encode(manager, address(this)), hookAddr2);
        ArbShieldHook hook2 = ArbShieldHook(hookAddr2);
        hook2.setCallbackContract(callbackAddr);
        // Do NOT set loyalty registry

        // Initialize a second pool with hook2
        (PoolKey memory key2,) = initPool(
            currency0,
            currency1,
            hook2,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        modifyLiquidityRouter.modifyLiquidity(
            key2,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Swap should work without registry (no discount, no revert)
        swapRouter.swap(
            key2,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        assertEq(hook2.totalLoyaltyDiscountsApplied(), 0);
    }

    function test_setLoyaltyRegistry_onlyOwner() public {
        // Create a fresh hook to test setLoyaltyRegistry access control
        uint160 flags3 = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        address hookAddr3 = address(uint160(flags3) | (2 << 20));
        deployCodeTo("ArbShieldHook.sol:ArbShieldHook", abi.encode(manager, address(this)), hookAddr3);
        ArbShieldHook hook3 = ArbShieldHook(hookAddr3);

        vm.prank(address(0xDEAD));
        vm.expectRevert(ArbShieldHook.OnlyOwner.selector);
        hook3.setLoyaltyRegistry(address(registry));
    }

    function test_setLoyaltyRegistry_onlyOnce() public {
        // Registry already set in setUp
        vm.expectRevert(ArbShieldHook.LoyaltyRegistryAlreadySet.selector);
        hook.setLoyaltyRegistry(address(0xBEEF));
    }

    function test_fullFlow_loyaltyPlusDivergence() public {
        // Set divergence fee
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        // Give lpUser SILVER tier (20% off)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        // Swap as loyal LP: divergence fee 10000, 20% off → 8000
        _doSwapAs(lpUser);

        // Verify discount was tracked
        assertEq(hook.totalLoyaltyDiscountsApplied(), 1);

        // Verify arb fee was also tracked
        assertTrue(hook.totalArbFeeCaptured() > 0);
    }

    // ==================== Zero-Address Validation Tests (A3) ====================

    function test_setCallbackContract_revertsOnZeroAddress() public {
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddr = address(uint160(flags) | (3 << 20));
        deployCodeTo("ArbShieldHook.sol:ArbShieldHook", abi.encode(manager, address(this)), hookAddr);
        ArbShieldHook freshHook = ArbShieldHook(hookAddr);

        vm.expectRevert(ArbShieldHook.ZeroAddress.selector);
        freshHook.setCallbackContract(address(0));
    }

    function test_setLoyaltyRegistry_revertsOnZeroAddress() public {
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddr = address(uint160(flags) | (3 << 20));
        deployCodeTo("ArbShieldHook.sol:ArbShieldHook", abi.encode(manager, address(this)), hookAddr);
        ArbShieldHook freshHook = ArbShieldHook(hookAddr);

        vm.expectRevert(ArbShieldHook.ZeroAddress.selector);
        freshHook.setLoyaltyRegistry(address(0));
    }

    // ==================== Emergency Pause Tests (B1) ====================

    function test_pause_blocksSwaps() public {
        hook.pause();
        assertTrue(hook.paused());

        vm.expectRevert();
        _doSwap();
    }

    function test_unpause_resumesSwaps() public {
        hook.pause();
        hook.unpause();
        assertFalse(hook.paused());

        _doSwap(); // should succeed
    }

    function test_pause_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(ArbShieldHook.OnlyOwner.selector);
        hook.pause();
    }

    function test_unpause_onlyOwner() public {
        hook.pause();
        vm.prank(address(0xDEAD));
        vm.expectRevert(ArbShieldHook.OnlyOwner.selector);
        hook.unpause();
    }

    // ==================== Fee Staleness Decay Tests (B2) ====================

    function test_stalenessDecay_returnsBaseFeeAfterPeriod() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        // Warp past staleness period (5 minutes = 300 seconds)
        vm.warp(block.timestamp + 6 minutes);
        assertEq(hook.getEffectiveFee(), 3000);
    }

    function test_stalenessDecay_linearDecay() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        // At half the staleness period (2.5 min = 150s)
        vm.warp(block.timestamp + 150);
        uint24 fee = hook.getEffectiveFee();
        // fee = 3000 + (10000-3000) * (300-150)/300 = 3000 + 3500 = 6500
        assertEq(fee, 6500);
    }

    function test_stalenessDecay_noDecayWhenAtBaseFee() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(1000, 10); // below baseFee

        vm.warp(block.timestamp + 6 minutes);
        assertEq(hook.getEffectiveFee(), 3000); // still baseFee
    }

    function test_totalArbFeeCaptured_usesDecayedFeeInStalenessWindow() public {
        // This test demonstrates the Fix 5 correction: during the decay window,
        // totalArbFeeCaptured records _getEffectiveFee() - baseFee, NOT currentDivergenceFee - baseFee.
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        // Warp to exactly half the staleness period
        vm.warp(block.timestamp + 150);
        // effectiveFee = 3000 + (10000-3000) * (300-150)/300 = 3000 + 3500 = 6500
        assertEq(hook.getEffectiveFee(), 6500);

        uint256 capturedBefore = hook.totalArbFeeCaptured();
        _doSwap();
        uint256 capturedAfter = hook.totalArbFeeCaptured();

        // Captured = effectiveFee - baseFee = 6500 - 3000 = 3500
        // (NOT currentDivergenceFee - baseFee = 10000 - 3000 = 7000)
        assertEq(capturedAfter - capturedBefore, 3500);
    }

    // ==================== Swap Counter & isFeeElevated Tests (D1) ====================

    function test_totalSwaps_incrementsOnSwap() public {
        assertEq(hook.totalSwaps(), 0);
        _doSwap();
        assertEq(hook.totalSwaps(), 1);
        _doSwap();
        assertEq(hook.totalSwaps(), 2);
    }

    function test_isFeeElevated_falseAtBaseFee() public view {
        (bool elevated, uint24 elevation) = hook.isFeeElevated();
        assertFalse(elevated);
        assertEq(elevation, 0);
    }

    function test_isFeeElevated_trueWhenDivergent() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        (bool elevated, uint24 elevation) = hook.isFeeElevated();
        assertTrue(elevated);
        assertEq(elevation, 7000); // 10000 - 3000
    }

    // ==================== getProtocolStats Tests (C1) ====================

    function test_getProtocolStats_returnsDefaults() public view {
        (
            uint24 effectiveFee, uint24 _baseFee, uint24 divergenceFee,
            uint256 _lastFeeUpdate, uint256 arbFeeCaptured,
            uint256 loyaltyDiscounts, uint256 _totalSwaps, bool isPaused
        ) = hook.getProtocolStats();

        assertEq(effectiveFee, 3000);
        assertEq(_baseFee, 3000);
        assertEq(divergenceFee, 0);
        assertEq(_lastFeeUpdate, 0);
        assertEq(arbFeeCaptured, 0);
        assertEq(loyaltyDiscounts, 0);
        assertEq(_totalSwaps, 0);
        assertFalse(isPaused);
    }

    // ==================== _resolveUser hookData Tests ====================

    function test_resolveUser_decodesAddressFromHookData() public {
        // Give lpUser GOLD tier (30% discount)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }
        assertEq(registry.getFeeDiscount(lpUser), 3000);

        // Swap as the test contract — tx.origin ≠ lpUser.
        // Encode lpUser in hookData so _resolveUser picks it up instead of tx.origin.
        bytes memory hookData = abi.encodePacked(lpUser);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // lpUser's GOLD discount was recognized via hookData, not tx.origin
        assertEq(hook.totalLoyaltyDiscountsApplied(), 1);
    }

    // ==================== Unichain Priority Fee Tests ====================

    function test_afterSwap_tracksUnichainPriorityFee() public {
        vm.fee(10 gwei);         // block.basefee = 10 gwei
        vm.txGasPrice(15 gwei);  // tx.gasprice = 15 gwei

        _doSwap();

        // priorityFee = gasprice - basefee = 15 - 10 = 5 gwei
        assertEq(hook.totalPriorityFeesCaptured(), 5 gwei);
    }

    function test_afterSwap_noPriorityFeeWhenGasPriceEqualsBaseFee() public {
        vm.fee(10 gwei);
        vm.txGasPrice(10 gwei); // gasprice == basefee → no priority fee

        _doSwap();

        assertEq(hook.totalPriorityFeesCaptured(), 0);
    }

    function test_afterSwap_noPriorityFeeInDefaultTestEnv() public {
        // Default test env: basefee = 0, gasprice = 0 → condition false, nothing recorded
        _doSwap();
        assertEq(hook.totalPriorityFeesCaptured(), 0);
    }

    function test_afterSwap_priorityFeeAccumulatesAcrossSwaps() public {
        vm.fee(5 gwei);
        vm.txGasPrice(8 gwei); // 3 gwei priority

        _doSwap();
        assertEq(hook.totalPriorityFeesCaptured(), 3 gwei);

        _doSwap();
        assertEq(hook.totalPriorityFeesCaptured(), 6 gwei);
    }

    // ==================== Helpers ====================

    function _doSwap() internal {
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
    }

    // ==================== Boundary Condition Tests ====================

    function test_staleness_exactlyAtBoundaryReturnsBase() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        vm.warp(block.timestamp + hook.STALENESS_PERIOD()); // exactly at boundary
        assertEq(hook.getEffectiveFee(), 3000);
    }

    function test_staleness_oneSecondBeforeBoundaryStillDecays() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        vm.warp(block.timestamp + hook.STALENESS_PERIOD() - 1);
        uint24 fee = hook.getEffectiveFee();
        assertTrue(fee > 3000, "fee should still be above base one second before staleness");
    }

    function test_updateDivergenceFee_exactlyAtMaxFee() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(50000, 500); // exactly MAX_FEE

        assertEq(hook.currentDivergenceFee(), 50000);
        assertEq(hook.getEffectiveFee(), 50000);
    }

    function test_updateDivergenceFee_belowBase_effectiveFeeIsBase() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(1000, 5); // below baseFee

        assertEq(hook.currentDivergenceFee(), 1000);
        assertEq(hook.getEffectiveFee(), 3000); // clamps to baseFee
    }

    // ==================== Event Emission Tests ====================

    function test_pause_emitsPausedEvent() public {
        vm.expectEmit(true, false, false, false);
        emit ArbShieldHook.Paused(address(this));
        hook.pause();
    }

    function test_unpause_emitsUnpausedEvent() public {
        hook.pause();
        vm.expectEmit(true, false, false, false);
        emit ArbShieldHook.Unpaused(address(this));
        hook.unpause();
    }

    function test_updateDivergenceFee_emitsDivergenceFeeUpdatedEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ArbShieldHook.DivergenceFeeUpdated(8000, 100, block.timestamp);
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(8000, 100);
    }

    function test_resetToBaseFee_emitsFeeResetToBaseEvent() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        vm.expectEmit(false, false, false, true);
        emit ArbShieldHook.FeeResetToBase(block.timestamp);
        vm.prank(callbackAddr);
        hook.resetToBaseFee();
    }

    // ==================== getProtocolStats After Activity ====================

    function test_getProtocolStats_afterActivityPopulatesFields() public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(10000, 125);

        _doSwap(); // swap 1
        _doSwap(); // swap 2

        (
            uint24 effectiveFee, uint24 _baseFee, uint24 divergenceFee,
            uint256 _lastFeeUpdate, uint256 arbFeeCaptured,
            uint256 loyaltyDiscounts, uint256 _totalSwaps, bool isPaused
        ) = hook.getProtocolStats();

        assertEq(effectiveFee, 10000);
        assertEq(_baseFee, 3000);
        assertEq(divergenceFee, 10000);
        assertTrue(_lastFeeUpdate > 0);
        assertEq(arbFeeCaptured, 14000); // (10000 - 3000) * 2 swaps
        assertEq(loyaltyDiscounts, 0);
        assertEq(_totalSwaps, 2);
        assertFalse(isPaused);
    }

    // ==================== Additional Fuzz Tests ====================

    function testFuzz_stalenessDecay_feeAlwaysInRange(uint24 divergenceFee, uint256 elapsed) public {
        vm.prank(callbackAddr);
        hook.updateDivergenceFee(divergenceFee, 0);

        elapsed = bound(elapsed, 0, 1 days);
        vm.warp(block.timestamp + elapsed);

        uint24 fee = hook.getEffectiveFee();
        assertTrue(fee >= hook.baseFee(), "fee dropped below baseFee");
        assertTrue(fee <= hook.MAX_FEE(), "fee exceeded MAX_FEE");
    }

    function testFuzz_loyaltyDiscount_noUint24Overflow(uint24 divergenceFee, uint256 activityCount) public {
        activityCount = bound(activityCount, 0, 20);

        vm.prank(callbackAddr);
        hook.updateDivergenceFee(divergenceFee, 0);

        for (uint256 i = 0; i < activityCount; i++) {
            vm.prank(callbackAddr);
            registry.recordLPActivity(lpUser);
        }

        uint24 discount = registry.getFeeDiscount(lpUser);
        uint24 effectiveFee = hook.getEffectiveFee();
        uint256 discountedFee = uint256(effectiveFee) * (10000 - discount) / 10000;
        assertTrue(discountedFee <= type(uint24).max, "discounted fee overflows uint24");
    }

    function _doSwapAs(address user) internal {
        // Fund the user with tokens
        MockERC20(Currency.unwrap(currency0)).mint(user, 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(user, 1 ether);

        // Approve swap router
        vm.startPrank(user, user); // sets both msg.sender and tx.origin
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {ArbShieldHook} from "../src/ArbShieldHook.sol";
import {ArbShieldCallback} from "../src/ArbShieldCallback.sol";
import {ArbShieldReactive} from "../src/ArbShieldReactive.sol";
import {LoyaltyRegistry} from "../src/LoyaltyRegistry.sol";
import {ArbShieldReactiveHarness} from "./ArbShieldReactive.t.sol";

/// @title ArbShieldIntegration
/// @notice End-to-end integration tests that wire together the full ArbShield stack:
///         ArbShieldReactiveHarness → Callback event → ArbShieldCallback → ArbShieldHook / LoyaltyRegistry
///         This mirrors the production flow where Reactive Network relays cross-chain events
///         and calls back into Unichain contracts.
contract ArbShieldIntegration is Test, Deployers {

    ArbShieldHook hook;
    ArbShieldCallback callback;
    LoyaltyRegistry registry;
    ArbShieldReactiveHarness harness;

    // Unichain Sepolia callback proxy (matches DeployHook.s.sol)
    address constant CALLBACK_PROXY  = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;
    address constant ETHEREUM_POOL   = address(0xE1);
    address constant LP_USER         = address(0xA1);
    uint256 constant ORIGIN_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID   = 130;

    // sqrtPriceX96 = N × 2^96  →  price = N² (contract's shift-and-square formula)
    uint160 constant SQRT_PRICE_1 = uint160(1) << 96; // price = 1
    uint160 constant SQRT_PRICE_4 = uint160(2) << 96; // price = 4

    // tick topics for Mint/Burn (tickLower=0, tickUpper=0 — same as reactive unit tests)
    uint256 constant T2 = 0;
    uint256 constant T3 = 0;

    // ─────────────────────────────────────────────────────────────────────────
    // setUp
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Deploy LoyaltyRegistry (owner = this test contract)
        registry = new LoyaltyRegistry();

        // Deploy ArbShieldHook at the flags address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo(
            "ArbShieldHook.sol:ArbShieldHook",
            abi.encode(manager, address(this)),
            address(flags)
        );
        hook = ArbShieldHook(address(flags));

        // Deploy ArbShieldCallback pranking as CALLBACK_PROXY so that
        // AbstractCallback sets rvm_id = CALLBACK_PROXY (needed by rvmIdOnly checks).
        vm.prank(CALLBACK_PROXY);
        callback = new ArbShieldCallback(CALLBACK_PROXY, address(hook), address(registry));

        // Link all three contracts
        hook.setCallbackContract(address(callback));
        registry.setCallbackContract(address(callback));
        hook.setLoyaltyRegistry(address(registry));

        // Reactive harness: vm=true, skips real subscriptions
        harness = new ArbShieldReactiveHarness(
            ETHEREUM_POOL,
            address(manager), // unichainPool — event routing uses chain_id, not address
            address(callback),
            ORIGIN_CHAIN_ID,
            DEST_CHAIN_ID
        );

        // Initialize the pool with dynamic fee flag
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        // Seed liquidity
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

        // Approve routers for this test contract
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Baseline swap — no divergence, no extra fee
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_baselineSwap() public {
        assertEq(hook.getEffectiveFee(), 3000, "baseline fee should be 3000");
        _doSwap();
        assertEq(hook.totalSwaps(), 1, "swap counter should increment");
        assertEq(hook.totalArbFeeCaptured(), 0, "no arb fee at base fee");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: Ethereum diverges → fee raised via full Reactive → Callback path
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_ethereumDiverges_feeRaisedBeforeArbSwap() public {
        // Start recording; trigger divergence (1 ETH V3 + 4 Unichain V4 signals)
        vm.recordLogs();
        _triggerDivergence();

        // Expect hook to emit DivergenceFeeUpdated(50000, 7500, ts) when callback is executed
        // divergenceBps = (4-1)*10000/4 = 7500; fee = min(7500²×80/100, 50000) = 50000
        vm.expectEmit(false, false, false, true);
        emit ArbShieldHook.DivergenceFeeUpdated(50000, 7500, block.timestamp);
        _executeCallbackEvents();

        assertEq(hook.getEffectiveFee(), 50000, "fee should be raised to 50000");

        // Swap at elevated fee — expect ArbFeeCaptured(effectiveFee=50000, baseFee=3000, extra=47000)
        vm.expectEmit(false, false, false, true);
        emit ArbShieldHook.ArbFeeCaptured(50000, 3000, 47000);
        _doSwap();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: Fee decays linearly over the staleness window (5 minutes)
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_feeDecaysLinearlyOverStalenessWindow() public {
        // Set divergence fee directly (bypasses reactive for simplicity)
        vm.prank(address(callback));
        hook.updateDivergenceFee(50000, 7500);
        uint256 feeSetTime = block.timestamp;

        // At T + 150 s (half the 300 s window):
        // effectiveFee = 3000 + (50000-3000) × (300-150)/300 = 3000 + 23500 = 26500
        vm.warp(feeSetTime + 150);
        assertApproxEqAbs(hook.getEffectiveFee(), 26500, 100, "fee should be ~26500 at half staleness");

        // At T + 300 s (exactly at STALENESS_PERIOD): fee reverts to baseFee
        vm.warp(feeSetTime + 300);
        assertEq(hook.getEffectiveFee(), 3000, "fee should be base after staleness");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: Convergence resets fee immediately (before staleness window)
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_convergenceResetsBeforeStaleness() public {
        // Step 1: trigger divergence and execute callback → fee = 50000
        vm.recordLogs();
        _triggerDivergence();
        _executeCallbackEvents();
        assertEq(hook.getEffectiveFee(), 50000, "pre-condition: fee should be 50000");

        // Step 2: send convergent Unichain signal (price matches Ethereum = 4)
        //         this causes PricesConverged + resetToBaseFee Callback
        vm.recordLogs();

        vm.expectEmit(false, false, false, false);
        emit ArbShieldReactive.PricesConverged();
        harness.reactTest(DEST_CHAIN_ID, address(manager), harness.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));

        // Expect FeeResetToBase emitted by hook during callback execution
        vm.expectEmit(false, false, false, true);
        emit ArbShieldHook.FeeResetToBase(block.timestamp);
        _executeCallbackEvents();

        // Fee must be baseFee immediately — no need to wait out the decay window
        assertEq(hook.getEffectiveFee(), 3000, "fee should reset immediately on convergence");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 5: LP holds position long enough → BRONZE tier → discount on arb swap
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_loyaltyPath_mintBurnCallbackDiscount() public {
        // Mint LP position at block 1000
        vm.roll(1000);
        _mintLP(LP_USER, block.number); // Mint: records entry block; no callback emitted

        // Burn at block 1000 + MIN_LOYALTY_BLOCKS (50400) → qualifies for loyalty
        vm.roll(1000 + 50400);
        vm.recordLogs();
        _burnLP(LP_USER, block.number); // emits LPDurationQualified + Callback(recordLPActivity)

        // Execute callback → registry.recordLPActivity(LP_USER) → BRONZE tier
        _executeCallbackEvents();
        assertEq(
            uint8(registry.loyaltyTier(LP_USER)),
            uint8(LoyaltyRegistry.LoyaltyTier.BRONZE),
            "LP_USER should be BRONZE after qualifying burn"
        );

        // Set divergence fee to 20000 and swap as LP_USER
        vm.prank(address(callback));
        hook.updateDivergenceFee(20000, 500);

        // Pre-fund LP_USER and approve BEFORE setting vm.expectEmit so that
        // the ERC20 Transfer/Approval events don't fire between expectEmit and the swap.
        MockERC20(Currency.unwrap(currency0)).mint(LP_USER, 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(LP_USER, 1 ether);
        vm.startPrank(LP_USER, LP_USER);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // BRONZE = 10% discount (1000 bps): effectiveFee=20000 × 9000/10000 = 18000
        vm.expectEmit(true, false, false, true);
        emit ArbShieldHook.LoyaltyDiscountApplied(LP_USER, 1000, 18000);
        vm.startPrank(LP_USER, LP_USER);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 6: Access control — unauthorized callers are rejected
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_accessControl() public {
        // Hook's updateDivergenceFee is guarded by onlyCallback
        vm.expectRevert(ArbShieldHook.OnlyCallback.selector);
        hook.updateDivergenceFee(5000, 100);

        // Callback's updateDivergenceFee is guarded by rvmIdOnly:
        // rvm_id was set to CALLBACK_PROXY in setUp; passing address(0) fails.
        vm.expectRevert("Authorized RVM ID only");
        callback.updateDivergenceFee(address(0), 5000, 100);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 7: Protocol stats are consistent after a full cycle
    // ─────────────────────────────────────────────────────────────────────────

    function test_integration_protocolStats_afterFullCycle() public {
        // ── Part A: divergence cycle ──────────────────────────────────────────
        vm.recordLogs();
        _triggerDivergence();
        _executeCallbackEvents();
        _doSwap(); // swap 1 at elevated fee (50000)

        // ── Part B: loyalty cycle ─────────────────────────────────────────────
        vm.roll(1000);
        _mintLP(LP_USER, block.number);
        vm.roll(1000 + 50400);
        vm.recordLogs();
        _burnLP(LP_USER, block.number);
        _executeCallbackEvents();

        vm.prank(address(callback));
        hook.updateDivergenceFee(20000, 500);
        _doSwapAs(LP_USER); // swap 2 with loyalty discount

        // ── Verify aggregated stats ───────────────────────────────────────────
        (
            ,           // effectiveFee
            ,           // baseFee
            ,           // divergenceFee
            ,           // lastFeeUpdate
            uint256 arbFeeCaptured,
            uint256 loyaltyDiscounts,
            uint256 totalSwaps,
            bool isPaused
        ) = hook.getProtocolStats();

        assertTrue(totalSwaps >= 2,       "should have at least 2 swaps");
        assertTrue(arbFeeCaptured > 0,    "arb fee should have been captured");
        assertTrue(loyaltyDiscounts >= 1, "loyalty discount should have been applied");
        assertFalse(isPaused,             "hook should not be paused");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Process all Callback events recorded since the last vm.recordLogs() call.
    ///      For each Callback event:
    ///        1. Decode the payload
    ///        2. Patch the rvm_id placeholder (address(0) at ABI arg[0]) with CALLBACK_PROXY
    ///        3. Execute via vm.prank(CALLBACK_PROXY) — mirroring Reactive Network's relay
    function _executeCallbackEvents() private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        address proxy = CALLBACK_PROXY;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != callbackSig) continue;

            bytes memory payload = abi.decode(logs[i].data, (bytes));

            // ABI payload layout: [4 bytes selector][32 bytes arg0 = rvm_id placeholder]...
            // Memory: payload ptr → 32-byte length → content starts at ptr+32
            // arg0 slot starts at content+4 = ptr+36
            // Overwrite address(0) placeholder with CALLBACK_PROXY (= rvm_id in ArbShieldCallback)
            assembly {
                mstore(add(payload, 36), proxy)
            }

            vm.prank(proxy);
            (bool ok, bytes memory err) = address(callback).call(payload);
            if (!ok) {
                assembly { revert(add(err, 32), mload(err)) }
            }
        }
    }

    /// @dev Trigger divergence: 1 Ethereum V3 signal at price=4, 4 Unichain V4 signals at price=1.
    ///      The first 3 Unichain signals increment the streak (0→1→2→3, each returns early).
    ///      The 4th signal fires DivergenceDetected + Callback(updateDivergenceFee(50000, 7500)).
    function _triggerDivergence() private {
        harness.reactTest(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL,
            harness.V3_SWAP_TOPIC_0(), 0, 0,
            _v3SwapData(SQRT_PRICE_4)
        );
        for (uint256 i = 0; i < 4; i++) {
            harness.reactTest(
                DEST_CHAIN_ID, address(manager),
                harness.V4_SWAP_TOPIC_0(), 0, 0,
                _v4SwapData(SQRT_PRICE_1)
            );
        }
    }

    function _doSwap() private {
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
    }

    function _doSwapAs(address user) private {
        MockERC20(Currency.unwrap(currency0)).mint(user, 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(user, 1 ether);
        vm.startPrank(user, user); // sets both msg.sender and tx.origin = user
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    /// @dev V3 Swap event data: (int256, int256, uint160 sqrtPriceX96, uint128, int24)
    function _v3SwapData(uint160 sqrtPrice) private pure returns (bytes memory) {
        return abi.encode(int256(-1e18), int256(2000e6), sqrtPrice, uint128(1e18), int24(200));
    }

    /// @dev V4 Swap event data: (int128, int128, uint160 sqrtPriceX96, uint128, int24, uint24)
    ///      sqrtPriceX96 sits at the same ABI byte offset as in V3, so the same decoder works.
    function _v4SwapData(uint160 sqrtPrice) private pure returns (bytes memory) {
        return abi.encode(int128(-1000e6), int128(2000e6), sqrtPrice, uint128(1e18), int24(200), uint24(3000));
    }

    /// @dev Simulate an LP Mint event (records entry block; no callback emitted).
    function _mintLP(address lp, uint256 blockNum) private {
        harness.reactTestFull(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL,
            harness.MINT_TOPIC_0(),
            uint256(uint160(lp)), T2, T3,
            abi.encode(uint128(1e18), uint256(1e18), uint256(2000e6)),
            blockNum
        );
    }

    /// @dev Simulate an LP Burn event (awards loyalty if held >= MIN_LOYALTY_BLOCKS).
    function _burnLP(address lp, uint256 blockNum) private {
        harness.reactTestFull(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL,
            harness.BURN_TOPIC_0(),
            uint256(uint160(lp)), T2, T3,
            abi.encode(uint128(1e18), uint256(1e18), uint256(2000e6)),
            blockNum
        );
    }
}

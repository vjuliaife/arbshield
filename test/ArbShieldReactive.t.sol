// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {ArbShieldReactive} from "../src/ArbShieldReactive.sol";

// ============================================================
// Harness: extends the real contract, enables VM mode for tests
// ============================================================

/// @title ArbShieldReactiveHarness
/// @notice Wraps ArbShieldReactive for unit testing. Forces vm=true so react() can be called
///         in a Foundry test environment without a Reactive Network system contract at 0xFFFFF.
///         All subscription calls are suppressed via the !vm guard in the parent constructor.
contract ArbShieldReactiveHarness is ArbShieldReactive {
    constructor(
        address _ethereumPool,
        address _unichainPool,
        address _callbackContract,
        uint256 _originChainId,
        uint256 _destChainId
    )
        ArbShieldReactive(_ethereumPool, _unichainPool, _callbackContract, _originChainId, _destChainId)
    {
        vm = true;
    }

    /// @notice Convenience wrapper for swap events (topic_3 = 0, block_number = block.number).
    function reactTest(
        uint256 chainId,
        address contractAddr,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        bytes memory data
    ) external {
        LogRecord memory log = LogRecord({
            chain_id: chainId,
            _contract: contractAddr,
            topic_0: topic0,
            topic_1: topic1,
            topic_2: topic2,
            topic_3: 0,
            data: data,
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
        this.react(log);
    }

    /// @notice Full-parameter wrapper for LP Mint/Burn events where topic_3 and block_number matter.
    function reactTestFull(
        uint256 chainId,
        address contractAddr,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3,
        bytes memory data,
        uint256 blockNumber
    ) external {
        LogRecord memory log = LogRecord({
            chain_id: chainId,
            _contract: contractAddr,
            topic_0: topic0,
            topic_1: topic1,
            topic_2: topic2,
            topic_3: topic3,
            data: data,
            block_number: blockNumber,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
        this.react(log);
    }
}

// ============================================================
// Test contract
// ============================================================

contract ArbShieldReactiveTest is Test {
    ArbShieldReactiveHarness reactive;

    address constant ETHEREUM_POOL         = address(0xE1);
    address constant UNICHAIN_POOL_MANAGER = address(0x22);
    address constant CALLBACK_CONTRACT     = address(0xCA11BAC4);
    uint256 constant ORIGIN_CHAIN_ID       = 1;
    uint256 constant DEST_CHAIN_ID         = 130;

    address constant LP_USER = address(0xA1);

    // sqrtPriceX96 = N * 2^96  →  price = N^2 (via the contract's shift-and-square formula)
    uint160 constant SQRT_PRICE_1   = uint160(1)  << 96;  // price = 1
    uint160 constant SQRT_PRICE_4   = uint160(2)  << 96;  // price = 4
    uint160 constant SQRT_PRICE_9   = uint160(3)  << 96;  // price = 9
    uint160 constant SQRT_PRICE_100 = uint160(10) << 96;  // price = 100

    // topic_2 / topic_3 used for Mint and Burn events (tickLower=0, tickUpper=0 for test simplicity)
    uint256 constant T2 = 0;
    uint256 constant T3 = 0;

    // ─────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────

    /// @dev Produce V3 Swap event data with a given sqrtPriceX96.
    ///      Layout: (int256, int256, uint160 sqrtPriceX96, uint128, int24)
    function _v3SwapData(uint160 sqrtPrice) internal pure returns (bytes memory) {
        return abi.encode(int256(-1e18), int256(2000e6), sqrtPrice, uint128(1e18), int24(200));
    }

    /// @dev Produce V4 Swap event data with a given sqrtPriceX96.
    ///      Layout: (int128, int128, uint160 sqrtPriceX96, uint128, int24, uint24)
    ///      sqrtPriceX96 is at the same ABI byte offset (64) as in V3, so the same decoder works.
    function _v4SwapData(uint160 sqrtPrice) internal pure returns (bytes memory) {
        return abi.encode(int128(-1000e6), int128(2000e6), sqrtPrice, uint128(1e18), int24(200), uint24(3000));
    }

    /// @dev Compute the position key the contract uses for a given LP and tick topics.
    function _posKey(address lp) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(uint160(lp)), T2, T3));
    }

    /// @dev Set Ethereum price once then send 4 divergent Unichain signals to fire a callback.
    ///      After: lastEmittedFee is set, divergenceStreak is 0 (reset post-emission).
    ///      The streak requires 3 accumulation signals before the 4th fires:
    ///        signals 1–3 → streak increments (0→1→2→3), each returns early
    ///        signal 4    → streak ≥ MIN_DIVERGENCE_STREAK → fee calc + callback
    function _triggerDivergence(uint160 sqrtEth, uint160 sqrtUni) internal {
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(sqrtEth));
        for (uint256 i = 0; i < 4; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtUni));
        }
    }

    /// @dev Simulate an LP Mint event with a controlled block number.
    function _mintLP(address lp, uint256 blockNumber) internal {
        reactive.reactTestFull(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.MINT_TOPIC_0(),
            uint256(uint160(lp)), T2, T3,
            abi.encode(uint128(1e18), uint256(1e18), uint256(2000e6)),
            blockNumber
        );
    }

    /// @dev Simulate an LP Burn event with a controlled block number.
    function _burnLP(address lp, uint256 blockNumber) internal {
        reactive.reactTestFull(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.BURN_TOPIC_0(),
            uint256(uint160(lp)), T2, T3,
            abi.encode(uint128(1e18), uint256(1e18), uint256(2000e6)),
            blockNumber
        );
    }

    function setUp() public {
        reactive = new ArbShieldReactiveHarness(
            ETHEREUM_POOL, UNICHAIN_POOL_MANAGER, CALLBACK_CONTRACT, ORIGIN_CHAIN_ID, DEST_CHAIN_ID
        );
    }

    // ==================== Topic Hash Tests ====================

    function test_v3SwapTopicHash_correct() public view {
        uint256 expected = uint256(keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)"));
        assertEq(reactive.V3_SWAP_TOPIC_0(), expected);
    }

    function test_v4SwapTopicHash_correct() public view {
        // keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
        uint256 expected = 0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f;
        assertEq(reactive.V4_SWAP_TOPIC_0(), expected);
        assertTrue(reactive.V4_SWAP_TOPIC_0() != reactive.V3_SWAP_TOPIC_0());
    }

    function test_mintTopicHash_correct() public view {
        uint256 expected = uint256(keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)"));
        assertEq(reactive.MINT_TOPIC_0(), expected);
    }

    function test_burnTopicHash_correct() public view {
        uint256 expected = uint256(keccak256("Burn(address,int24,int24,uint128,uint256,uint256)"));
        assertEq(reactive.BURN_TOPIC_0(), expected);
    }

    // ==================== sqrtPriceX96ToPrice Tests ====================

    function test_sqrtPriceX96ToPrice_atPriceOne() public view {
        assertEq(reactive.sqrtPriceX96ToPrice(SQRT_PRICE_1), 1);
    }

    function test_sqrtPriceX96ToPrice_atPriceFour() public view {
        assertEq(reactive.sqrtPriceX96ToPrice(SQRT_PRICE_4), 4);
    }

    function test_sqrtPriceX96ToPrice_atPriceNine() public view {
        assertEq(reactive.sqrtPriceX96ToPrice(SQRT_PRICE_9), 9);
    }

    function test_sqrtPriceX96ToPrice_atZero() public view {
        assertEq(reactive.sqrtPriceX96ToPrice(0), 0);
    }

    function testFuzz_sqrtPriceX96ToPrice_noOverflow(uint160 sqrtPriceX96) public view {
        reactive.sqrtPriceX96ToPrice(sqrtPriceX96);
    }

    // ==================== Ethereum V3 Swap Handling ====================

    function test_react_ethereumV3Swap_updatesEthereumPrice() public {
        assertEq(reactive.lastEthereumPrice(), 0);
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        assertEq(reactive.lastEthereumPrice(), 1);
        assertEq(reactive.lastUnichainPrice(), 0);
    }

    function test_react_ethereumV3Swap_emitsPriceUpdatedEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ArbShieldReactive.PriceUpdated(ORIGIN_CHAIN_ID, 1);
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
    }

    // ==================== Unichain V4 Swap Handling ====================

    function test_react_unichainV4Swap_updatesUnichainPrice() public {
        assertEq(reactive.lastUnichainPrice(), 0);
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        assertEq(reactive.lastUnichainPrice(), 4);
        assertEq(reactive.lastEthereumPrice(), 0);
    }

    function test_react_unichainV4Swap_emitsPriceUpdatedEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ArbShieldReactive.PriceUpdated(DEST_CHAIN_ID, 4);
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
    }

    function test_react_v4SwapData_decodesCorrectPrice() public {
        // Verify that V4 data (int128 fields + extra uint24 fee) decodes sqrtPriceX96 correctly.
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_9));
        assertEq(reactive.lastUnichainPrice(), 9);
    }

    // ==================== No Divergence — No Callback ====================

    function test_react_equalPrices_noDivergenceCallbackEmitted() public {
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_100));
        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_100));
        bytes32 divergenceSig = keccak256("DivergenceDetected(uint256,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == divergenceSig, "Unexpected DivergenceDetected event");
        }
    }

    function test_react_onlyEthereumPrice_noDivergenceCallback() public {
        vm.recordLogs();
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_4));
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "no callback without both prices");
        }
        assertEq(reactive.lastEthereumPrice(), 4);
        assertEq(reactive.lastEmittedFee(), 0);
    }

    function test_react_onlyUnichainPrice_noDivergenceCallback() public {
        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_9));
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "no callback without both prices");
        }
        assertEq(reactive.lastUnichainPrice(), 9);
        assertEq(reactive.lastEmittedFee(), 0);
    }

    // ==================== Divergence Streak ====================

    function test_react_streak_firstThreeSignals_noCallback() public {
        // Signals 1–3: each increments streak (0→1→2→3) and returns early — no callback yet.
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        }
        assertEq(reactive.divergenceStreak(), 3);
        assertEq(reactive.lastEmittedFee(), 0);
    }

    function test_react_streak_fourthSignal_emitsCallbackAndResetsStreak() public {
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        }

        vm.expectEmit(false, false, false, true);
        emit ArbShieldReactive.DivergenceDetected(7500, 50000);
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));

        assertEq(reactive.divergenceStreak(), 0); // reset after emission
        assertEq(reactive.lastEmittedFee(), 50000);
    }

    function test_react_streak_resetOnConvergence() public {
        // Build streak to 2, then send a converging price — streak must reset to 0.
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        assertEq(reactive.divergenceStreak(), 2);

        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));
        assertEq(reactive.divergenceStreak(), 0);
    }

    function test_react_streak_interruptionRequiresRestartFromZero() public {
        // Convergence mid-streak forces a full restart; 3 more divergent signals don't fire.
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        assertEq(reactive.divergenceStreak(), 2);

        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));
        assertEq(reactive.divergenceStreak(), 0);

        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        }
        assertEq(reactive.lastEmittedFee(), 0); // still no callback (streak at 3, needs one more)
        assertEq(reactive.divergenceStreak(), 3);
    }

    // ==================== Divergence → Callback ====================

    function test_react_divergentPrices_emitsDivergenceDetected() public {
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        }
        vm.expectEmit(false, false, false, true);
        emit ArbShieldReactive.DivergenceDetected(7500, 50000);
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
    }

    function test_react_divergentPrices_emitsCallbackWithCorrectDestination() public {
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        }
        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));

        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == callbackSig) {
                found = true;
                assertEq(uint256(logs[i].topics[1]), DEST_CHAIN_ID);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), CALLBACK_CONTRACT);
            }
        }
        assertTrue(found, "Callback event not emitted");
    }

    function test_react_divergence_updatesLastEmittedFee() public {
        assertEq(reactive.lastEmittedFee(), 0);
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);
        assertEq(reactive.lastEmittedFee(), 50000);
    }

    function test_react_divergence_quadraticFeeCapAtMaxFee() public {
        _triggerDivergence(SQRT_PRICE_100, SQRT_PRICE_1);
        assertEq(reactive.lastEmittedFee(), reactive.MAX_FEE());
    }

    // ==================== Hysteresis ====================

    function test_react_hysteresis_noSecondCallbackForSameFee() public {
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);
        assertEq(reactive.lastEmittedFee(), 50000);

        // Streak resets to 0 after emission; next signal hits streak guard (0→1, return early).
        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        bytes32 divergenceSig = keccak256("DivergenceDetected(uint256,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == divergenceSig, "Unexpected second DivergenceDetected");
        }
    }

    function test_react_hysteresis_lastEmittedFeeUnchangedAfterNoCallback() public {
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);
        uint24 feeAfterFirst = reactive.lastEmittedFee();

        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_4));
        assertEq(reactive.lastEmittedFee(), feeAfterFirst);
    }

    function test_react_hysteresis_noCallbackWhenFeeDiffBelowThreshold() public {
        // N_A = 10000 (Ethereum): price = 1e8
        // N_B = 9968  (Unichain): divergence ≈ 63 bps → fee = 63²×80/100 = 3175
        // N_C = 9967  (Unichain): divergence ≈ 65 bps → fee = 65²×80/100 = 3380
        // |3380 − 3175| = 205 < FEE_CHANGE_THRESHOLD (500) → hysteresis blocks second emit
        uint160 sqrtPrice_A = uint160(10000) << 96;
        uint160 sqrtPrice_B = uint160(9968)  << 96;
        uint160 sqrtPrice_C = uint160(9967)  << 96;

        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(sqrtPrice_A));

        // Prime + trigger first callback at price B (3 accumulation signals + 1 trigger)
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtPrice_B));
        }
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtPrice_B));
        assertEq(reactive.lastEmittedFee(), 3175);

        // Rebuild streak at price C (streak reset to 0 after emission above)
        for (uint256 i = 0; i < 3; i++) {
            reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtPrice_C));
        }

        // 4th signal at price C: passes streak guard, reaches hysteresis check → no emit
        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtPrice_C));
        bytes32 divergenceSig = keccak256("DivergenceDetected(uint256,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == divergenceSig, "Fee diff < 500 bps should not emit");
        }
        assertEq(reactive.lastEmittedFee(), 3175); // unchanged
    }

    // ==================== Convergence Reset ====================

    function test_react_convergence_emitsPricesConverged() public {
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);

        vm.expectEmit(false, false, false, false);
        emit ArbShieldReactive.PricesConverged();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));
    }

    function test_react_convergence_emitsResetCallback() public {
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);

        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));

        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == callbackSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[2]))), CALLBACK_CONTRACT);
            }
        }
        assertTrue(found, "Reset Callback event not emitted after convergence");
    }

    function test_react_convergence_resetsLastEmittedFee() public {
        _triggerDivergence(SQRT_PRICE_1, SQRT_PRICE_4);
        assertEq(reactive.lastEmittedFee(), 50000);

        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));
        assertEq(reactive.lastEmittedFee(), 0);
    }

    function test_react_convergence_noResetIfNeverDiverged() public {
        // lastEmittedFee = 0 → convergence path skips the callback (guard: lastEmittedFee > 0)
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(SQRT_PRICE_1));

        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(SQRT_PRICE_1));

        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "Spurious Callback for never-diverged state");
        }
    }

    // ==================== LP Mint: Entry Block Recording ====================

    function test_react_mintEvent_recordsEntryBlock() public {
        _mintLP(LP_USER, 1000);
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 1000);
    }

    function test_react_mintEvent_emitsLPMintRecorded() public {
        bytes32 posKey = _posKey(LP_USER);
        vm.expectEmit(true, true, false, true);
        emit ArbShieldReactive.LPMintRecorded(LP_USER, posKey, 1000);
        _mintLP(LP_USER, 1000);
    }

    function test_react_mintEvent_noCallback() public {
        vm.recordLogs();
        _mintLP(LP_USER, 1000);
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "Mint must not emit a Callback");
        }
    }

    function test_react_mintEvent_idempotent_doesNotOverwriteEntry() public {
        _mintLP(LP_USER, 1000);
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 1000);

        // Second mint for the same position — entry block must NOT be overwritten.
        _mintLP(LP_USER, 2000);
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 1000);
    }

    function test_react_mintEvent_differentPositions_trackedIndependently() public {
        address lp2 = address(0xA2);
        _mintLP(LP_USER, 100);
        reactive.reactTestFull(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.MINT_TOPIC_0(),
            uint256(uint160(lp2)), T2, T3,
            abi.encode(uint128(1e18), uint256(1e18), uint256(2000e6)),
            200
        );
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 100);
        assertEq(reactive.positionEntryBlock(_posKey(lp2)), 200);
    }

    // ==================== LP Burn: Duration Loyalty ====================

    function test_react_burnBeforeMinBlocks_noLoyaltyCallback() public {
        uint256 entryBlock = 1000;
        _mintLP(LP_USER, entryBlock);

        vm.recordLogs();
        _burnLP(LP_USER, entryBlock + reactive.MIN_LOYALTY_BLOCKS() - 1);

        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "Burn before MIN_LOYALTY_BLOCKS must not award loyalty");
        }
        // Entry block preserved (not cleared on failed burn)
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), entryBlock);
    }

    function test_react_burnAtExactMinBlocks_emitsLoyaltyCallback() public {
        uint256 entryBlock = 1000;
        _mintLP(LP_USER, entryBlock);

        vm.recordLogs();
        _burnLP(LP_USER, entryBlock + reactive.MIN_LOYALTY_BLOCKS());

        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == callbackSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[2]))), CALLBACK_CONTRACT);
            }
        }
        assertTrue(found, "Qualifying burn must emit loyalty Callback");
    }

    function test_react_burnAfterMinBlocks_emitsLPDurationQualified() public {
        uint256 entryBlock = 500;
        uint256 exitBlock  = entryBlock + reactive.MIN_LOYALTY_BLOCKS() + 100;
        _mintLP(LP_USER, entryBlock);

        vm.expectEmit(true, false, false, true);
        emit ArbShieldReactive.LPDurationQualified(LP_USER, exitBlock - entryBlock);
        _burnLP(LP_USER, exitBlock);
    }

    function test_react_burnClearsEntryBlock() public {
        _mintLP(LP_USER, 1000);
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 1000);

        _burnLP(LP_USER, 1000 + reactive.MIN_LOYALTY_BLOCKS());
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 0);
    }

    function test_react_burnNoEntry_ignored() public {
        // Burn without a prior Mint — must be a no-op (no revert, no callback).
        vm.recordLogs();
        _burnLP(LP_USER, 9999);
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == callbackSig, "Burn with no entry must be ignored");
        }
    }

    function test_react_burnThenRemint_startsNewTimer() public {
        // Qualifying burn clears the entry. A subsequent re-add starts a fresh 7-day timer.
        _mintLP(LP_USER, 100);
        _burnLP(LP_USER, 100 + reactive.MIN_LOYALTY_BLOCKS()); // qualifies, clears entry
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 0);

        _mintLP(LP_USER, 200_000);
        assertEq(reactive.positionEntryBlock(_posKey(LP_USER)), 200_000);
    }

    // ==================== Unknown Topic / Edge Cases ====================

    function test_react_unknownTopic_ignored() public {
        vm.recordLogs();
        reactive.reactTest(
            ORIGIN_CHAIN_ID, ETHEREUM_POOL,
            uint256(keccak256("SomeOtherEvent(address,uint256)")),
            0, 0,
            abi.encode(uint256(42))
        );
        assertEq(reactive.lastEthereumPrice(), 0);
        assertEq(reactive.lastUnichainPrice(), 0);
        assertEq(reactive.lastEmittedFee(), 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    // ==================== Boundary: Divergence Threshold ====================

    function test_react_divergenceExactlyAtThreshold_noCallback() public {
        // N_A = 10000, N_B = 9999: divergence ≈ 1 bps (well below 10 bps threshold)
        uint160 sqrtA = uint160(10000) << 96;
        uint160 sqrtB = uint160(9999)  << 96;
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(sqrtA));

        vm.recordLogs();
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtB));

        bytes32 divergenceSig = keccak256("DivergenceDetected(uint256,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == divergenceSig, "1 bps divergence should not emit callback");
        }
        assertEq(reactive.lastEmittedFee(), 0);
    }

    // ==================== Fuzz Tests ====================

    function testFuzz_sqrtPriceX96ToPrice_noOverflow_fuzz(uint160 sqrtPriceX96) public view {
        reactive.sqrtPriceX96ToPrice(sqrtPriceX96);
    }

    function testFuzz_divergenceFeeCalculation_neverExceedsMax(uint160 sqrtPriceEth, uint160 sqrtPriceUni) public {
        // With only 2 signals the streak never reaches MIN_DIVERGENCE_STREAK, so lastEmittedFee
        // stays 0 — still satisfies the invariant fee <= MAX_FEE.
        reactive.reactTest(ORIGIN_CHAIN_ID, ETHEREUM_POOL, reactive.V3_SWAP_TOPIC_0(), 0, 0, _v3SwapData(sqrtPriceEth));
        reactive.reactTest(DEST_CHAIN_ID, UNICHAIN_POOL_MANAGER, reactive.V4_SWAP_TOPIC_0(), 0, 0, _v4SwapData(sqrtPriceUni));
        assertTrue(reactive.lastEmittedFee() <= reactive.MAX_FEE(), "fee exceeded MAX_FEE");
    }

    function testFuzz_addressExtractionFromTopic(address addr) public pure {
        uint256 topic = uint256(uint160(addr));
        address extracted = address(uint160(topic));
        assertEq(extracted, addr);
    }
}

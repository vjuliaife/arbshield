// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

interface ILoyaltyRegistry {
    function getFeeDiscount(address user) external view returns (uint24);
}

contract ArbShieldHook is BaseHook {

    event DivergenceFeeUpdated(uint24 newFee, uint256 divergenceBps, uint256 timestamp);
    event FeeResetToBase(uint256 timestamp);
    event ArbFeeCaptured(uint24 effectiveFee, uint24 baseFee, uint256 extraFeeBps);
    event CallbackContractSet(address indexed callbackContract);
    event LoyaltyRegistrySet(address indexed loyaltyRegistry);
    event LoyaltyDiscountApplied(address indexed user, uint24 discount, uint24 finalFee);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event UnichainPriorityFeeMonitored(uint256 priorityFee, uint256 blockBaseFee);

    error OnlyCallback();
    error OnlyOwner();
    error CallbackAlreadySet();
    error LoyaltyRegistryAlreadySet();
    error PoolMustUseDynamicFee();
    error ZeroAddress();
    error EnforcedPause();

    // 0.30%
    uint24 public baseFee = 3000; 
    // set by callback
    uint24 public currentDivergenceFee;
    // 5.00%
    uint24 public constant MAX_FEE = 50000;
    uint256 public constant STALENESS_PERIOD = 5 minutes;
    uint256 public lastFeeUpdate;
    uint256 public totalArbFeeCaptured;
    uint256 public totalLoyaltyDiscountsApplied;
    uint256 public totalSwaps;
    uint256 public totalPriorityFeesCaptured;
    address public owner;
    address public callbackContract;
    ILoyaltyRegistry public loyaltyRegistry;
    bool public paused;

    modifier onlyCallback() {
        if (msg.sender != callbackContract) revert OnlyCallback();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(IPoolManager _poolManager, address _owner) BaseHook(_poolManager) {
        owner = _owner;
    }
    // link the callback relay contract. Can only be set once.
    function setCallbackContract(address _cb) external onlyOwner {
        if (_cb == address(0)) revert ZeroAddress();
        if (callbackContract != address(0)) revert CallbackAlreadySet();
        callbackContract = _cb;
        emit CallbackContractSet(_cb);
    }

    // link the loyalty registry. Can only be set once.
    function setLoyaltyRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        if (address(loyaltyRegistry) != address(0)) revert LoyaltyRegistryAlreadySet();
        loyaltyRegistry = ILoyaltyRegistry(_registry);
        emit LoyaltyRegistrySet(_registry);
    }

    // pause the hook — all swaps will revert until unpaused
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    // unpaused the hook — swaps resume normal operation
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // enabled beforeInitialize, beforeSwap, afterSwap
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    // enforce that the pool uses the dynamic fee flag
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        if (key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG) revert PoolMustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    // Return the effective fee (with staleness decay and loyalty discount), with the OVERRIDE flag
    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata hookData)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (paused) revert EnforcedPause();

        uint24 effectiveFee = _getEffectiveFee();

        // apply loyalty discount if registry is set.
        if (address(loyaltyRegistry) != address(0)) {
            uint24 discountBps = loyaltyRegistry.getFeeDiscount(_resolveUser(hookData));
            if (discountBps > 0) {
                effectiveFee = uint24(uint256(effectiveFee) * (10000 - discountBps) / 10000);
            }
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, effectiveFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    // track arb fee captured when divergence fee is active
    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        totalSwaps++;

        // Use the decayed effective fee (not the raw currentDivergenceFee)
        uint24 effectiveFee = _getEffectiveFee();
        if (effectiveFee > baseFee) {
            uint256 extraFeeBps = uint256(effectiveFee - baseFee);
            totalArbFeeCaptured += extraFeeBps;
            emit ArbFeeCaptured(effectiveFee, baseFee, extraFeeBps);
        }

        // Track loyalty discount usage
        if (address(loyaltyRegistry) != address(0)) {
            address user = _resolveUser(hookData);
            uint24 discountBps = loyaltyRegistry.getFeeDiscount(user);
            if (discountBps > 0) {
                totalLoyaltyDiscountsApplied++;
                uint24 finalFee = uint24(uint256(effectiveFee) * (10000 - discountBps) / 10000);
                emit LoyaltyDiscountApplied(user, discountBps, finalFee);
            }
        }

        if (tx.gasprice > block.basefee) {
            uint256 priorityFee = tx.gasprice - block.basefee;
            totalPriorityFeesCaptured += priorityFee;
            emit UnichainPriorityFeeMonitored(priorityFee, block.basefee);
        }

        return (this.afterSwap.selector, 0);
    }

    function updateDivergenceFee(uint24 newFee, uint256 divergenceBps) external onlyCallback {
        currentDivergenceFee = newFee > MAX_FEE ? MAX_FEE : newFee;
        lastFeeUpdate = block.timestamp;
        emit DivergenceFeeUpdated(currentDivergenceFee, divergenceBps, block.timestamp);
    }

    // called by the callback contract to reset fees when prices converge
    function resetToBaseFee() external onlyCallback {
        currentDivergenceFee = 0;
        lastFeeUpdate = block.timestamp;
        emit FeeResetToBase(block.timestamp);
    }
    // returns the effective fee
    function getEffectiveFee() external view returns (uint24) {
        return _getEffectiveFee();
    }

    // returns whether the fee is currently elevated above baseFee and by how much
    function isFeeElevated() external view returns (bool elevated, uint24 elevationBps) {
        uint24 fee = _getEffectiveFee();
        elevated = fee > baseFee;
        elevationBps = elevated ? fee - baseFee : 0;
    }

    // returns all key protocol metrics in a single call for dashboard display
    function getProtocolStats()
        external
        view
        returns (
            uint24 effectiveFee,
            uint24 _baseFee,
            uint24 divergenceFee,
            uint256 _lastFeeUpdate,
            uint256 arbFeeCaptured,
            uint256 loyaltyDiscounts,
            uint256 _totalSwaps,
            bool isPaused
        )
    {
        effectiveFee = _getEffectiveFee();
        _baseFee = baseFee;
        divergenceFee = currentDivergenceFee;
        _lastFeeUpdate = lastFeeUpdate;
        arbFeeCaptured = totalArbFeeCaptured;
        loyaltyDiscounts = totalLoyaltyDiscountsApplied;
        _totalSwaps = totalSwaps;
        isPaused = paused;
    }

    // Internal functions

    // resolve the end-user address for loyalty lookups.
    function _resolveUser(bytes calldata hookData) internal view returns (address) {
        if (hookData.length >= 20) {
            return address(bytes20(hookData[:20]));
        }
        return tx.origin;
    }

    function _getEffectiveFee() internal view returns (uint24) {
        uint24 fee = currentDivergenceFee > baseFee ? currentDivergenceFee : baseFee;
        fee = fee > MAX_FEE ? MAX_FEE : fee;
        if (fee > baseFee && lastFeeUpdate > 0) {
            uint256 elapsed = block.timestamp - lastFeeUpdate;
            if (elapsed >= STALENESS_PERIOD) return baseFee;
            uint256 remaining = uint256(fee - baseFee) * (STALENESS_PERIOD - elapsed) / STALENESS_PERIOD;
            fee = baseFee + uint24(remaining);
        }
        return fee;
    }
}

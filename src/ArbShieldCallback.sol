// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AbstractCallback} from "reactive-lib/AbstractCallback.sol";

interface IArbShieldHook {
    function updateDivergenceFee(uint24 newFee, uint256 divergenceBps) external;
    function resetToBaseFee() external;
}

interface ILoyaltyRegistryCallback {
    function recordLPActivity(address lp) external;
}

contract ArbShieldCallback is AbstractCallback {

    IArbShieldHook public immutable hook;
    ILoyaltyRegistryCallback public immutable loyaltyRegistry;

    event DivergenceFeeRelayed(uint24 newFee, uint256 divergenceBps);
    event FeeResetRelayed();
    event LPActivityRelayed(address indexed lp);

    constructor(address _callbackProxy, address _hook, address _loyaltyRegistry) AbstractCallback(_callbackProxy) {
        hook = IArbShieldHook(_hook);
        loyaltyRegistry = ILoyaltyRegistryCallback(_loyaltyRegistry);
    }

    // called by the Reactive Network to update divergence fee
    function updateDivergenceFee(address _rvm_id, uint24 newFee, uint256 divergenceBps) external rvmIdOnly(_rvm_id) {
        hook.updateDivergenceFee(newFee, divergenceBps);
        emit DivergenceFeeRelayed(newFee, divergenceBps);
    }

    // called by the Reactive Network to reset fees
    function resetToBaseFee(address _rvm_id) external rvmIdOnly(_rvm_id) {
        hook.resetToBaseFee();
        emit FeeResetRelayed();
    }

    // called by the Reactive Network when LP activity is detected cross-chain
    function recordLPActivity(address _rvm_id, address lp) external rvmIdOnly(_rvm_id) {
        loyaltyRegistry.recordLPActivity(lp);
        emit LPActivityRelayed(lp);
    }
}

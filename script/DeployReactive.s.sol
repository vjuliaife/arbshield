// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ArbShieldReactive} from "../src/ArbShieldReactive.sol";

/// @notice Deploys ArbShieldReactive on the Reactive Network
/// @dev Required env vars:
///
///   REACTIVE_PRIVATE_KEY   Private key for deploying on the Reactive Network (Lasna testnet)
///   CALLBACK_CONTRACT      Address of the ArbShieldCallback deployed on Unichain (output of DeployHook)
///   ORIGIN_POOL            Address of the Ethereum V3 ETH/USDC pool to monitor for price and LP activity.
///                          Mainnet:  0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8 (Uniswap V3 ETH/USDC 0.30%)
///                          Sepolia:  use a V3 ETH/USDC pool deployed on Ethereum Sepolia
///   DEST_POOL              Address of the Unichain V4 PoolManager — NOT a V3 pool address.
///                          The reactive contract subscribes to V4 Swap events emitted by the PoolManager.
///                          Unichain Sepolia PoolManager: 0x00B036B58a818B1BC34d502D3fE730Db729e62AC
///   ORIGIN_CHAIN_ID        Chain ID of the Ethereum network to monitor (default: 11155111 = Sepolia)
///   DEST_CHAIN_ID          Chain ID of the Unichain network (default: 1301 = Unichain Sepolia)
contract DeployReactive is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("REACTIVE_PRIVATE_KEY");
        address callbackContract = vm.envAddress("CALLBACK_CONTRACT");
        address originPool = vm.envAddress("ORIGIN_POOL");
        // Must be the Unichain V4 PoolManager address (see NatSpec above).
        address destPool = vm.envAddress("DEST_POOL");
        uint256 originChainId = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        uint256 destChainId = vm.envOr("DEST_CHAIN_ID", uint256(1301));

        vm.startBroadcast(deployerPrivateKey);

        // Send 0.5 lREACT with deployment so the RSC can pay for the 4 subscribe()
        // calls that fire in the constructor. Each subscription costs ~0.003 lREACT;
        // the remainder stays in the contract to cover future callback gas payments.
        ArbShieldReactive reactive = new ArbShieldReactive{value: 0.5 ether}(
            originPool,
            destPool,
            callbackContract,
            originChainId,
            destChainId
        );

        console.log("ArbShieldReactive deployed to:", address(reactive));
        console.log("Origin chain ID:", originChainId);
        console.log("Dest chain ID:", destChainId);
        console.log("Monitoring origin pool:", originPool);
        console.log("Monitoring dest pool:", destPool);
        console.log("Callback contract:", callbackContract);

        vm.stopBroadcast();
    }
}

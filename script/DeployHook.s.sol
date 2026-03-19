// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ArbShieldHook} from "../src/ArbShieldHook.sol";
import {ArbShieldCallback} from "../src/ArbShieldCallback.sol";
import {LoyaltyRegistry} from "../src/LoyaltyRegistry.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Deploys ArbShieldHook + ArbShieldCallback + LoyaltyRegistry on Unichain
contract DeployHook is Script {
    // Unichain Sepolia PoolManager
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    // Unichain callback proxy (same on mainnet & testnet)
    address constant CALLBACK_PROXY = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Determine required hook flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        address deployer = vm.addr(deployerPrivateKey);

        // Mine a salt for CREATE2 that produces an address with the correct flag bits.
        // Constructor args must match exactly what will be passed during deployment.
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), deployer);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(ArbShieldHook).creationCode,
            constructorArgs
        );

        console.log("Deploying ArbShieldHook to:", hookAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy LoyaltyRegistry
        LoyaltyRegistry registry = new LoyaltyRegistry();
        console.log("LoyaltyRegistry deployed to:", address(registry));

        // 2. Deploy hook via CREATE2 — pass deployer as owner so msg.sender (the factory)
        //    is not recorded as owner.
        ArbShieldHook hook = new ArbShieldHook{salt: salt}(IPoolManager(POOL_MANAGER), deployer);
        require(address(hook) == hookAddress, "Hook address mismatch");

        // 3. Deploy callback with hook and registry references
        ArbShieldCallback callback = new ArbShieldCallback(CALLBACK_PROXY, address(hook), address(registry));
        console.log("ArbShieldCallback deployed to:", address(callback));

        // 4. Link callback to hook
        hook.setCallbackContract(address(callback));
        console.log("Callback linked to hook");

        // 5. Link loyalty registry to hook
        hook.setLoyaltyRegistry(address(registry));
        console.log("LoyaltyRegistry linked to hook");

        // 6. Link callback to registry
        registry.setCallbackContract(address(callback));
        console.log("Callback linked to registry");

        vm.stopBroadcast();
    }
}

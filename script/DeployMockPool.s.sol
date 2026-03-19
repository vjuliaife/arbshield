// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MockV3Pool} from "../src/MockV3Pool.sol";

/// @notice Deploys two MockERC20 tokens + MockV3Pool on Ethereum Sepolia for ArbShield demo.
///
/// Required env vars:
///   PRIVATE_KEY   — deployer key with Sepolia ETH
///
/// Run:
///   forge script script/DeployMockPool.s.sol \
///     --rpc-url https://rpc.sepolia.org \
///     --broadcast
///
/// Demo flow after RSC is deployed and funded:
///
///   # Diverge: sell 1000 token1 into pool (price 1 → 4, divergence = 7500 bps)
///   cast send $POOL 'swap(bool,uint256,address)' false 1000000000000000000000 $YOUR_ADDR \
///     --rpc-url https://rpc.sepolia.org --private-key $PRIVATE_KEY
///
///   # Converge: sell 500 token0 back (price 4 → 1, divergence = 0)
///   cast send $POOL 'swap(bool,uint256,address)' true 500000000000000000000 $YOUR_ADDR \
///     --rpc-url https://rpc.sepolia.org --private-key $PRIVATE_KEY
contract DeployMockPool is Script {
    uint256 constant SEED = 1000 ether; // 1000:1000 → price = 1 at start

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Capture the on-chain nonce BEFORE startBroadcast.
        // In Foundry broadcast mode, every external call (not just deployments) is a
        // signed transaction and increments the deployer nonce. The sequence is:
        //   preNonce + 0: deploy tokenA
        //   preNonce + 1: deploy tokenB
        //   preNonce + 2: mint(t0)      ← tx, nonce increments
        //   preNonce + 3: mint(t1)      ← tx, nonce increments
        //   preNonce + 4: approve(t0)   ← tx, nonce increments
        //   preNonce + 5: approve(t1)   ← tx, nonce increments
        //   preNonce + 6: deploy MockV3Pool  ← pool lives here
        uint64 preNonce = vm.getNonce(deployer);
        address predictedPool = vm.computeCreateAddress(deployer, preNonce + 6);

        vm.startBroadcast(deployerKey);

        // Deploy token pair (18 decimals each)
        MockERC20 tokenA = new MockERC20("Mock WETH", "mWETH", 18); // preNonce + 0
        MockERC20 tokenB = new MockERC20("Mock USDC", "mUSDC", 18); // preNonce + 1

        // V3 ordering: token0 < token1 by address
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        // Mint seed liquidity to deployer
        MockERC20(t0).mint(deployer, SEED);
        MockERC20(t1).mint(deployer, SEED);

        // Approve the predicted pool address to pull seed tokens
        // (MockV3Pool constructor calls transferFrom in the same tx)
        MockERC20(t0).approve(predictedPool, SEED);
        MockERC20(t1).approve(predictedPool, SEED);

        // Deploy pool at preNonce+2 — constructor pulls SEED of each token from deployer
        MockV3Pool pool = new MockV3Pool(t0, t1, SEED, SEED);
        require(address(pool) == predictedPool, "Pool address mismatch: nonce prediction wrong");

        vm.stopBroadcast();

        console.log("Deployed on Ethereum Sepolia:");
        console.log("  token0:", t0);
        console.log("  token1:", t1);
        console.log("  MockV3Pool:", address(pool));
        console.log("  Initial price (getPrice()):", pool.getPrice());
        console.log("");
        console.log("Next: set ORIGIN_POOL to the pool address above in DeployReactive.s.sol");
        console.log("");
        console.log("Demo swap commands (after RSC is deployed and funded):");
        console.log("  Mint + approve token1, then:");
        console.log("  DIVERGE  : swap(false, 1000e18, yourAddr)  price 1->4, ~7500 bps divergence");
        console.log("  CONVERGE : swap(true,  500e18,  yourAddr)  price 4->1, fee resets");
    }
}

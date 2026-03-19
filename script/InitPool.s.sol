// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @notice Initializes an ArbShield pool on Unichain Sepolia and seeds it with liquidity.
///
/// Prerequisites (env vars):
///   PRIVATE_KEY   - deployer private key with Unichain Sepolia ETH
///   HOOK_ADDRESS  - ArbShieldHook address from DeployHook output
///
/// Optional overrides:
///   TOKEN0              - real token address (default: deploy MockWETH)
///   TOKEN1              - real token address (default: deploy MockUSDC)
///   LIQUIDITY_AMOUNT    - token0 units to seed (default: 10 ether = 10e18)
///
/// Run:
///   forge script script/InitPool.s.sol \
///     --rpc-url https://sepolia.unichain.org \
///     --broadcast
contract InitPool is Script {
    // Unichain Sepolia PoolManager (same address on mainnet)
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    // PositionManager on Unichain Sepolia (from v4-periphery broadcast)
    address constant POSITION_MGR = 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664;
    // Canonical Permit2 (same on every chain)
    address constant PERMIT2      = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // 1:1 starting price -- sqrtPriceX96 = sqrt(1) * 2^96
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    // tick spacing 60 pairs with the dynamic fee flag
    int24 constant TICK_SPACING = 60;
    // +-10 tick spacings around the current tick
    int24 constant TICK_LOWER = -600;
    int24 constant TICK_UPPER =  600;

    // Shared state written during run(), read by helpers
    address internal _token0;
    address internal _token1;
    address internal _hook;
    address internal _deployer;
    uint256 internal _liquidityAmount;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        _deployer           = vm.addr(deployerKey);
        _hook               = vm.envAddress("HOOK_ADDRESS");
        _liquidityAmount    = vm.envOr("LIQUIDITY_AMOUNT", uint256(10 ether));

        vm.startBroadcast(deployerKey);

        _deployOrLoadTokens();
        _mintAndApprove();
        _initPoolAndAddLiquidity();

        vm.stopBroadcast();

        _printSummary();
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    function _deployOrLoadTokens() internal {
        address t0 = vm.envOr("TOKEN0", address(0));
        address t1 = vm.envOr("TOKEN1", address(0));

        if (t0 == address(0)) {
            t0 = address(new MockERC20("Mock WETH", "mWETH", 18));
            console.log("MockWETH deployed:", t0);
        }
        if (t1 == address(0)) {
            t1 = address(new MockERC20("Mock USDC", "mUSDC", 6));
            console.log("MockUSDC deployed:", t1);
        }

        // v4 requires currency0 < currency1 by address value
        (_token0, _token1) = t0 < t1 ? (t0, t1) : (t1, t0);
    }

    function _mintAndApprove() internal {
        // Mint 2x liquidity amount to deployer for both tokens
        MockERC20(_token0).mint(_deployer, _liquidityAmount * 2);
        MockERC20(_token1).mint(_deployer, _liquidityAmount * 2);
        console.log("Minted seed tokens to deployer");

        // Step A: ERC20 -> Permit2 unlimited allowance
        IERC20(_token0).approve(PERMIT2, type(uint256).max);
        IERC20(_token1).approve(PERMIT2, type(uint256).max);
        console.log("ERC20 approved Permit2");

        // Step B: Permit2 -> PositionManager allowance
        // IAllowanceTransfer.approve(address token, address spender, uint160 amount, uint48 expiration)
        (bool ok0,) = PERMIT2.call(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                _token0, POSITION_MGR, type(uint160).max, type(uint48).max
            )
        );
        require(ok0, "Permit2 approve token0 failed");

        (bool ok1,) = PERMIT2.call(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                _token1, POSITION_MGR, type(uint160).max, type(uint48).max
            )
        );
        require(ok1, "Permit2 approve token1 failed");
        console.log("Permit2 allowances granted to PositionManager");
    }

    function _initPoolAndAddLiquidity() internal {
        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(_token0),
            currency1:   Currency.wrap(_token1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks:       IHooks(_hook)
        });

        IPositionManager posm = IPositionManager(POSITION_MGR);

        // Initialize: triggers beforeInitialize on the hook.
        // Reverts with PoolMustUseDynamicFee if pool key is wrong.
        posm.initializePool(key, SQRT_PRICE_1_1);
        console.log("Pool initialized at 1:1 price");

        _mintPosition(posm, key);
    }

    function _mintPosition(IPositionManager posm, PoolKey memory key) internal {
        uint128 liquidity = _liquidityForAmount0(_liquidityAmount, TICK_LOWER, TICK_UPPER);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            TICK_LOWER,
            TICK_UPPER,
            liquidity,
            _liquidityAmount * 2,  // amount0Max (generous for demo)
            _liquidityAmount * 2,  // amount1Max
            _deployer,             // LP NFT recipient
            bytes("")              // hookData
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        posm.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 300  // 5-minute deadline
        );
        console.log("Liquidity minted. LP NFT held by deployer.");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("==========================================================");
        console.log("ArbShield pool live on Unichain Sepolia");
        console.log("==========================================================");
        console.log("Token0 (mWETH) :", _token0);
        console.log("Token1 (mUSDC) :", _token1);
        console.log("Hook           :", _hook);
        console.log("PoolManager    :", POOL_MANAGER);
        console.log("PositionMgr    :", POSITION_MGR);
        console.log("Deployer       :", _deployer);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Run DeployReactive.s.sol on Reactive Lasna");
        console.log("  2. Fund RSC: cast send <rsc_addr> --value 1ether --rpc-url https://lasna-rpc.rnk.dev/");
        console.log("  3. Trigger a swap on Ethereum Sepolia V3 to start price detection");
        console.log("  4. Verify on https://lasna.reactscan.net and https://sepolia.uniscan.xyz");
    }

    /// @dev Approximate liquidity from a token0 amount over [tickLower, tickUpper].
    ///      Formula: L = amount0 * sqrtLower * sqrtUpper / (sqrtUpper - sqrtLower) / 2^96
    ///      Accurate enough for testnet seeding; not suitable for production.
    function _liquidityForAmount0(uint256 amount0, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (uint128)
    {
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint256 numerator   = uint256(sqrtLower) * uint256(sqrtUpper) / (1 << 96);
        uint256 denominator = uint256(sqrtUpper - sqrtLower);
        uint256 liq = amount0 * numerator / denominator;
        return liq > type(uint128).max ? type(uint128).max : uint128(liq);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @dev Minimal WETH9 interface — only what is needed by this script.
interface IWETH9 is IERC20 {
    /// @notice Wrap ETH: call with `msg.value` ETH, receive equal amount of WETH.
    function deposit() external payable;
}

/// @title InitPoolReal
/// @notice Initializes an ArbShield pool on Unichain Sepolia using real WETH and USDC,
///         then seeds it with a liquidity position.
///
/// ── Token addresses (Unichain Sepolia, chain ID 1301) ──────────────────────────────────
///   WETH9:  0x4200000000000000000000000000000000000006  (OP Stack predeploy, same on mainnet)
///   USDC:   0x31d0220469e10c4E71834a79b1f276d740d3768F  (Circle-deployed, verified on Uniscan)
///
/// ── Before running this script ─────────────────────────────────────────────────────────
///   1. Get Unichain Sepolia ETH from a faucet:
///        https://app.optimism.io/faucet          (0.05 ETH / 24 h — Superchain faucet)
///        https://faucet.quicknode.com/unichain/sepolia
///        https://faucets.chain.link/unichain-testnet
///
///   2. Get USDC from Circle's testnet faucet:
///        https://faucet.circle.com/
///        Select "Unichain Sepolia", paste your wallet address → receive 20 USDC.
///        Rate limit: 20 USDC per address per 2 hours.
///
///   3. This script wraps ETH to WETH automatically.
///      Your wallet must hold enough ETH to cover:
///        - WETH_AMOUNT (default 0.01 ETH) → wrapped to WETH for liquidity
///        - Gas for all transactions (< 0.005 ETH at Unichain gas prices)
///
/// ── Required env vars ──────────────────────────────────────────────────────────────────
///   PRIVATE_KEY   — private key of the deployer wallet
///   HOOK_ADDRESS  — ArbShieldHook address from DeployHook.s.sol output
///
/// ── Optional env vars (override defaults) ──────────────────────────────────────────────
///   WETH_AMOUNT    — ETH to wrap and add as WETH liquidity, in wei
///                    Default: 10000000000000000 (0.01 ETH)
///   USDC_AMOUNT    — USDC to add as liquidity, in USDC's 6-decimal raw units
///                    Default: 20000000 (20 USDC — one Circle faucet claim)
///   INITIAL_TICK   — pool initialization tick (sets starting price)
///                    Default: 200280 ≈ 2000 USDC per ETH
///
///                    To compute for a different ETH price in USDC (Python):
///                      import math
///                      eth_price = 3500  # example: $3,500
///                      raw_price = 1e18 / (eth_price * 1e6)
///                      tick = math.floor(math.log(raw_price) / math.log(1.0001))
///                      # round to nearest multiple of 60
///                      tick = round(tick / 60) * 60
///                      print(tick)   # e.g., 198,600 at $3,500
///
///   TICK_RANGE     — ticks above and below INITIAL_TICK covered by the position
///                    Default: 3000 (about ±33% price range — wide enough for testnet)
///                    Must be a positive multiple of 60.
///
/// ── Run ────────────────────────────────────────────────────────────────────────────────
///   forge script script/InitPoolReal.s.sol \
///     --rpc-url https://sepolia.unichain.org  \
///     --broadcast
contract InitPoolReal is Script {
    // ── Unichain Sepolia addresses ────────────────────────────────────────────────
    // Source: https://docs.unichain.org/docs/technical-information/contract-addresses
    address constant WETH9        = 0x4200000000000000000000000000000000000006;
    address constant USDC         = 0x31d0220469e10c4E71834a79b1f276d740d3768F;
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    // Source: v4-periphery broadcast/DeployPosm.s.sol/1301/run-latest.json
    address constant POSITION_MGR = 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664;
    // Canonical Permit2 — same address on every EVM chain
    address constant PERMIT2      = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ── currency ordering ─────────────────────────────────────────────────────────
    // USDC (0x31...) < WETH (0x42...) so Uniswap assigns:
    //   currency0 = USDC  (6 decimals)
    //   currency1 = WETH  (18 decimals)
    //
    // Pool price = (WETH raw units) / (USDC raw units)
    //
    // At 1 ETH = 2000 USDC:
    //   raw price = 1e18 / (2000 * 1e6) = 5e8
    //   tick      = floor(ln(5e8) / ln(1.0001)) = 200,312
    //   nearest 60-multiple below: 200,280
    //
    // Tick spacing 60 is the standard choice for the 0.30% fee tier and pairs
    // well with the DYNAMIC_FEE_FLAG used by ArbShieldHook.
    int24 constant TICK_SPACING = 60;

    // ── shared state written in run(), read by helpers ────────────────────────────
    address internal _hook;
    address internal _deployer;
    int24   internal _initialTick;
    int24   internal _tickLower;
    int24   internal _tickUpper;
    uint256 internal _wethAmount;
    uint256 internal _usdcAmount;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        _deployer           = vm.addr(deployerKey);
        _hook               = vm.envAddress("HOOK_ADDRESS");

        // ── Load configurable parameters ─────────────────────────────────────────
        _wethAmount  = vm.envOr("WETH_AMOUNT",  uint256(0.01 ether));   // 0.01 WETH
        _usdcAmount  = vm.envOr("USDC_AMOUNT",  uint256(20_000_000));   // 20 USDC (6 dec)
        int256 iTick = vm.envOr("INITIAL_TICK", int256(200_280));       // ~2000 USDC/ETH
        int256 range = vm.envOr("TICK_RANGE",   int256(3_000));

        _initialTick = int24(iTick);
        _tickLower   = int24(iTick - range);
        _tickUpper   = int24(iTick + range);

        // Sanity checks: tick bounds must be multiples of TICK_SPACING and
        // within the TickMath valid range [-887272, 887272].
        require(_tickLower % TICK_SPACING == 0, "TICK_LOWER not multiple of tick spacing");
        require(_tickUpper % TICK_SPACING == 0, "TICK_UPPER not multiple of tick spacing");
        require(_tickLower > TickMath.MIN_TICK, "TICK_LOWER below TickMath.MIN_TICK");
        require(_tickUpper < TickMath.MAX_TICK, "TICK_UPPER above TickMath.MAX_TICK");
        require(_tickLower < _tickUpper,        "TICK_LOWER must be less than TICK_UPPER");

        // ── Pre-flight balance checks (fail fast before any broadcast) ────────────
        _checkBalances();

        vm.startBroadcast(deployerKey);

        _wrapEth();
        _approvePermit2();
        _initPoolAndMint();

        vm.stopBroadcast();

        _printSummary();
    }

    // ── Pre-flight ────────────────────────────────────────────────────────────────

    function _checkBalances() internal view {
        uint256 ethBal  = _deployer.balance;
        uint256 usdcBal = IERC20(USDC).balanceOf(_deployer);

        console.log("Pre-flight checks:");
        console.log("  ETH balance  :", ethBal);
        console.log("  USDC balance :", usdcBal, "(raw, 6 decimals)");
        console.log("  WETH_AMOUNT  :", _wethAmount, "wei to wrap");
        console.log("  USDC_AMOUNT  :", _usdcAmount, "raw units to add");

        // Require enough ETH to wrap + gas headroom (0.005 ETH)
        require(
            ethBal >= _wethAmount + 0.005 ether,
            "Insufficient ETH. Need WETH_AMOUNT + 0.005 ETH for gas. "
            "Get ETH from https://app.optimism.io/faucet"
        );

        // Require USDC — must be obtained from Circle faucet before running.
        require(
            usdcBal >= _usdcAmount,
            "Insufficient USDC. Visit https://faucet.circle.com/ to claim 20 USDC "
            "on Unichain Sepolia, then rerun."
        );
    }

    // ── Step 1: Wrap ETH -> WETH ──────────────────────────────────────────────────

    function _wrapEth() internal {
        IWETH9(WETH9).deposit{value: _wethAmount}();
        uint256 wethBal = IERC20(WETH9).balanceOf(_deployer);
        console.log("Wrapped ETH to WETH. WETH balance:", wethBal);
        require(wethBal >= _wethAmount, "WETH wrap produced less than expected");
    }

    // ── Step 2: ERC20 -> Permit2 -> PositionManager approvals ────────────────────

    function _approvePermit2() internal {
        // Step A: ERC20 unlimited allowance to Permit2
        // (Permit2 pulls tokens from the user only when explicitly signed/called)
        IERC20(USDC).approve(PERMIT2, type(uint256).max);
        IERC20(WETH9).approve(PERMIT2, type(uint256).max);
        console.log("ERC20 approved Permit2 for USDC and WETH");

        // Step B: Permit2 IAllowanceTransfer.approve(token, spender, amount, expiration)
        // This grants PositionManager the right to pull tokens via Permit2 on our behalf.
        (bool ok0,) = PERMIT2.call(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                USDC, POSITION_MGR, type(uint160).max, type(uint48).max
            )
        );
        require(ok0, "Permit2.approve for USDC failed");

        (bool ok1,) = PERMIT2.call(
            abi.encodeWithSignature(
                "approve(address,address,uint160,uint48)",
                WETH9, POSITION_MGR, type(uint160).max, type(uint48).max
            )
        );
        require(ok1, "Permit2.approve for WETH failed");
        console.log("Permit2 allowances granted to PositionManager");
    }

    // ── Step 3: Initialize pool and mint LP position ──────────────────────────────

    function _initPoolAndMint() internal {
        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(USDC),
            currency1:   Currency.wrap(WETH9),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks:       IHooks(_hook)
        });

        uint160 sqrtInitial = TickMath.getSqrtPriceAtTick(_initialTick);

        console.log("Initializing pool:");
        console.log("  currency0 (USDC):", USDC);
        console.log("  currency1 (WETH):", WETH9);
        console.log("  hook            :", _hook);
        console.log("  initialTick     :", uint256(uint24(_initialTick)));
        console.log("  tickLower       :", uint256(uint24(_tickLower)));
        console.log("  tickUpper       :", uint256(uint24(_tickUpper)));

        // Initialize: triggers beforeInitialize on ArbShieldHook which enforces
        // LPFeeLibrary.DYNAMIC_FEE_FLAG. If the hook address is wrong or the fee
        // flag is missing, this transaction will revert.
        IPositionManager(POSITION_MGR).initializePool(key, sqrtInitial);
        console.log("Pool initialized");

        _mintPosition(key, sqrtInitial);
    }

    function _mintPosition(PoolKey memory key, uint160 sqrtInitial) internal {
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(_tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(_tickUpper);

        // Compute the maximum liquidity achievable from our token balances.
        // getLiquidityForAmounts correctly handles:
        //   - non-1:1 price ratios
        //   - different token decimals (USDC=6, WETH=18)
        //   - current price relative to [tickLower, tickUpper]
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtInitial,
            sqrtLower,
            sqrtUpper,
            _usdcAmount,   // amount0 = USDC (currency0)
            _wethAmount    // amount1 = WETH (currency1)
        );

        require(liquidity > 0, "Computed liquidity is zero. Check token amounts and tick range.");

        console.log("Computed liquidity:", liquidity);

        // Slippage ceiling: allow up to 2x the seed amounts to account for
        // rounding and price movement between script submission and inclusion.
        uint256 amount0Max = _usdcAmount * 2;
        uint256 amount1Max = _wethAmount * 2;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            _tickLower,
            _tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            _deployer,   // LP NFT recipient
            bytes("")    // hookData (no loyalty lookup on add-liquidity)
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        IPositionManager(POSITION_MGR).modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 300  // 5-minute deadline
        );

        console.log("Liquidity minted. LP NFT held by deployer.");
    }

    // ── Summary ───────────────────────────────────────────────────────────────────

    function _printSummary() internal view {
        console.log("");
        console.log("==========================================================");
        console.log("ArbShield pool live on Unichain Sepolia (real assets)");
        console.log("==========================================================");
        console.log("currency0  USDC :", USDC);
        console.log("currency1  WETH :", WETH9);
        console.log("hook            :", _hook);
        console.log("PoolManager     :", POOL_MANAGER);
        console.log("PositionManager :", POSITION_MGR);
        console.log("initialTick     :", uint256(uint24(_initialTick)));
        console.log("tickLower       :", uint256(uint24(_tickLower)));
        console.log("tickUpper       :", uint256(uint24(_tickUpper)));
        console.log("deployer        :", _deployer);
        console.log("");
        console.log("Verify on block explorer:");
        console.log("  https://sepolia.uniscan.xyz/address/<hook>");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Run DeployReactive.s.sol on Reactive Lasna");
        console.log("     forge script script/DeployReactive.s.sol \\");
        console.log("       --rpc-url https://lasna-rpc.rnk.dev/ --broadcast");
        console.log("  2. Fund RSC with lREACT:");
        console.log("     cast send <rsc_addr> --value 1ether \\");
        console.log("       --rpc-url https://lasna-rpc.rnk.dev/ --private-key $REACTIVE_PRIVATE_KEY");
        console.log("  3. Trigger a swap on Ethereum Sepolia V3 to start price detection");
        console.log("  4. Watch: https://lasna.reactscan.net and https://sepolia.uniscan.xyz");
    }
}

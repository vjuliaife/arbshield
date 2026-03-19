// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @title MockV3Pool
/// @notice A minimal constant-product AMM that faithfully simulates a Uniswap V3 pool
///         for testnet demo purposes. Price changes ONLY through actual token swaps —
///         no shortcuts, no direct price setting.
///
/// @dev How price works:
///      The pool holds two ERC20 reserves (reserve0, reserve1).
///      After every swap, new reserves are computed via x * y = k (constant product).
///      sqrtPriceX96 is derived from the new reserves:
///
///          sqrtPriceX96 = sqrt(reserve1 / reserve0) × 2^96
///
///      This is the exact value that ArbShieldReactive reads from Swap events.
///
///      The emitted event matches the V3 Swap signature exactly:
///          Swap(address indexed sender, address indexed recipient,
///               int256 amount0, int256 amount1,
///               uint160 sqrtPriceX96, uint128 liquidity, int24 tick)
///      Topic: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
///
/// @dev Concrete demo numbers (both tokens have 18 decimals):
///
///      Seed pool with 1000:1000 → price = 1 (matches Unichain mock pool at 1:1)
///      RSC sees: lastEthereumPrice = 1, lastUnichainPrice = 1, divergence = 0
///      Hook fee = 0.30% (base fee)
///
///      Diverge: swap 1000 token1 in → reserves become 500:2000 → price = 4
///      RSC sees: lastEthereumPrice = 4, lastUnichainPrice = 1, divergence = 7500 bps
///      After 4 consecutive signals → hook fee jumps to 5.00% (MAX_FEE)
///
///      Converge: swap 500 token0 in → reserves return to 1000:1000 → price = 1
///      RSC detects convergence → hook fee resets to 0.30%
contract MockV3Pool {

    // ── Events ──────────────────────────────────────────────────────────────────

    /// @notice Exact V3 Swap event signature.
    ///         ArbShieldReactive subscribes to this topic:
    ///         keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)")
    ///         = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256  amount0,
        int256  amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24   tick
    );

    // ── State ────────────────────────────────────────────────────────────────────

    address public immutable token0;  // lower address (V3 ordering: token0 < token1)
    address public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;
    uint160 public currentSqrtPriceX96;

    // ── Constructor ──────────────────────────────────────────────────────────────

    /// @param _token0     Lower-address ERC20. Must be pre-approved by caller.
    /// @param _token1     Higher-address ERC20. Must be pre-approved by caller.
    /// @param _amount0    token0 seeded into the pool. Determines the starting price.
    /// @param _amount1    token1 seeded into the pool. Determines the starting price.
    ///
    /// @dev For a 1:1 starting price (matching the Unichain mock pool):
    ///      pass equal amounts, e.g. _amount0 = _amount1 = 1000 ether.
    constructor(address _token0, address _token1, uint256 _amount0, uint256 _amount1) {
        require(_token0 < _token1, "MockV3Pool: token0 must be < token1 by address");
        require(_amount0 > 0 && _amount1 > 0, "MockV3Pool: zero seed amount");

        token0 = _token0;
        token1 = _token1;

        // Pull seed liquidity from the deployer
        IERC20(_token0).transferFrom(msg.sender, address(this), _amount0);
        IERC20(_token1).transferFrom(msg.sender, address(this), _amount1);

        reserve0 = _amount0;
        reserve1 = _amount1;
        currentSqrtPriceX96 = _computeSqrtPriceX96(_amount0, _amount1);
    }

    // ── Core: Swap ───────────────────────────────────────────────────────────────

    /// @notice Swap token0 for token1, or token1 for token0.
    ///         Uses the constant-product formula: reserve0 × reserve1 = k (invariant).
    ///         The price (sqrtPriceX96) is updated from the new reserves after each swap.
    ///         A V3 Swap event is emitted — the RSC on Reactive Lasna picks this up.
    ///
    /// @param zeroForOne  true  = sell token0, receive token1 (price goes DOWN)
    ///                    false = sell token1, receive token0 (price goes UP)
    /// @param amountIn    Exact amount of the input token to sell. Must be approved.
    /// @param recipient   Address that receives the output tokens.
    /// @return amountOut  Amount of the output token sent to recipient.
    ///
    /// @dev Demo usage:
    ///
    ///      To diverge (price moves from 1 to 4):
    ///        zeroForOne = false, amountIn = 1000 ether
    ///        Reserves: 1000:1000 → 500:2000, price 1 → 4
    ///
    ///      To converge (price returns to 1):
    ///        zeroForOne = true, amountIn = 500 ether  (received from diverge swap)
    ///        Reserves: 500:2000 → 1000:1000, price 4 → 1
    function swap(bool zeroForOne, uint256 amountIn, address recipient)
        external
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "MockV3Pool: zero amountIn");

        // k is the constant product invariant. Computed fresh each swap.
        // Overflow check: with 1000 ether seeds, k = (1e21)^2 = 1e42 << uint256 max (1.16e77).
        uint256 k = reserve0 * reserve1;

        int256 delta0;
        int256 delta1;

        if (zeroForOne) {
            // ── Sell token0, buy token1 ─────────────────────────────────────
            // Caller sends amountIn of token0 to pool.
            // New reserve0 increases → price (reserve1/reserve0) falls.
            IERC20(token0).transferFrom(msg.sender, address(this), amountIn);

            uint256 newReserve0 = reserve0 + amountIn;
            uint256 newReserve1 = k / newReserve0;         // constant product
            amountOut = reserve1 - newReserve1;             // token1 output
            require(amountOut > 0, "MockV3Pool: insufficient output");

            IERC20(token1).transfer(recipient, amountOut);

            reserve0 = newReserve0;
            reserve1 = newReserve1;

            delta0 = int256(amountIn);    // pool received token0 (+)
            delta1 = -int256(amountOut);  // pool sent token1 (-)

        } else {
            // ── Sell token1, buy token0 ─────────────────────────────────────
            // Caller sends amountIn of token1 to pool.
            // New reserve1 increases → price (reserve1/reserve0) rises.
            IERC20(token1).transferFrom(msg.sender, address(this), amountIn);

            uint256 newReserve1 = reserve1 + amountIn;
            uint256 newReserve0 = k / newReserve1;         // constant product
            amountOut = reserve0 - newReserve0;             // token0 output
            require(amountOut > 0, "MockV3Pool: insufficient output");

            IERC20(token0).transfer(recipient, amountOut);

            reserve0 = newReserve0;
            reserve1 = newReserve1;

            delta0 = -int256(amountOut);  // pool sent token0 (-)
            delta1 = int256(amountIn);    // pool received token1 (+)
        }

        // Update and store the new price
        currentSqrtPriceX96 = _computeSqrtPriceX96(reserve0, reserve1);

        // Emit the V3 Swap event — this is what ArbShieldReactive reads
        emit Swap(
            msg.sender,
            recipient,
            delta0,
            delta1,
            currentSqrtPriceX96,
            uint128(reserve0 > type(uint128).max ? type(uint128).max : reserve0), // simplified liquidity
            int24(0)  // simplified tick (not used by RSC)
        );
    }

    // ── Liquidity Management ─────────────────────────────────────────────────────

    /// @notice Add more liquidity to the pool. Maintains the current price ratio.
    ///         Both tokens must be approved by the caller.
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        reserve0 += amount0;
        reserve1 += amount1;
        currentSqrtPriceX96 = _computeSqrtPriceX96(reserve0, reserve1);
    }

    // ── Price Computation ────────────────────────────────────────────────────────

    /// @notice View the price the RSC will see after the next swap.
    ///         Returns the same value that sqrtPriceX96ToPrice() in the RSC computes.
    function getPrice() external view returns (uint256) {
        uint256 sqrtP = uint256(currentSqrtPriceX96);
        uint256 shifted = sqrtP >> 32;
        return (shifted * shifted) >> 128;
    }

    /// @dev Compute sqrtPriceX96 from reserves using integer arithmetic.
    ///
    ///      Formula: sqrtPriceX96 = sqrt(reserve1 / reserve0) × 2^96
    ///
    ///      Implementation:
    ///        = sqrt(reserve1) × 2^96 / sqrt(reserve0)
    ///        = sqrt(reserve1 × 1e18) × 2^96 / sqrt(reserve0 × 1e18)
    ///        (the 1e18 scale factors cancel but improve integer precision)
    ///
    ///      Verification with 1000:1000 seeds:
    ///        sqrt(1e21 × 1e18) = sqrt(1e39) ≈ 3.162e19
    ///        sqrtPriceX96 = 3.162e19 × 2^96 / 3.162e19 = 2^96 ✓ (price = 1)
    ///
    ///      Verification with 500:2000 (after diverge swap):
    ///        sqrt(2e21 × 1e18) ≈ 4.472e19
    ///        sqrt(5e20 × 1e18) ≈ 2.236e19
    ///        sqrtPriceX96 = 4.472e19 × 2^96 / 2.236e19 = 2 × 2^96 ✓ (price = 4)
    function _computeSqrtPriceX96(uint256 r0, uint256 r1)
        internal
        pure
        returns (uint160)
    {
        // Scale by 1e18 before sqrt to preserve precision in integer arithmetic.
        // r * 1e18 with r up to 1e30 gives r*1e18 up to 1e48 << uint256 max (1.16e77).
        uint256 sqrtR1 = _sqrt(r1 * 1e18);
        uint256 sqrtR0 = _sqrt(r0 * 1e18);
        require(sqrtR0 > 0, "MockV3Pool: zero reserve");
        // sqrtR1 * 2^96 with sqrtR1 up to ~1e24 gives ~7.92e52 << uint256 max.
        return uint160(sqrtR1 * (1 << 96) / sqrtR0);
    }

    /// @dev Babylonian integer square root (rounds down).
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}

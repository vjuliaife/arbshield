# ArbShield: Cross-Chain LVR Protection Hook

**A Uniswap v4 hook that autonomously captures arbitrage profit for LPs by monitoring real-time price divergence between Ethereum and Unichain via Reactive Network. When the ETH/USDC price on Ethereum diverges from the Unichain pool, fees rise automatically to price out arbers — returning their edge to liquidity providers.**

## Problem: LVR Drains LP Returns

Loss-versus-Rebalancing (LVR) is the dominant source of LP losses on AMMs. When an asset's "true" price (as reflected on Ethereum) diverges from a pool's stale price on Unichain, arbitrageurs extract the difference in a risk-free trade — a systematic transfer of value from LPs to bots.

This happens because fees are static. A 0.30% fee is fine for noise; it's worthless against a 2% price divergence. The arber pockets the spread minus the fee.

## Solution: Dynamic Fees Funded by Divergence Signals

ArbShield adds a second fee component that scales with actual cross-chain divergence:

```
effectiveFee = max(baseFee, divergenceFee) with 5-minute linear decay
divergenceFee = (divergenceBps² × 80%) / 100  — capped at 5.00%
```

The fee is:
- **Proportional** to divergence magnitude (quadratic — large divergences cost much more)
- **Self-healing** — decays linearly back to 0.30% over 5 minutes with no new update
- **Immediate** on reset when prices converge (no waiting for staleness window)
- **LP loyalty–discounted** — long-term LPs get 10–30% off for holding through volatility

All of this happens autonomously. No off-chain keeper, no oracle contract to call, no privileged relayer. The Reactive Network monitors Ethereum Uniswap V3 swap events and pushes fee updates directly into Unichain.

## Architecture

```
ETHEREUM                           REACTIVE NETWORK                    UNICHAIN
========                           ================                    ========

Uniswap V3 Pool                    ArbShieldReactive.sol
  Swap event          ─────────►   Sub 1: V3 Swap (Ethereum pool)
  (sqrtPriceX96)                   - Decode sqrtPriceX96, compute price
                                   - Update lastEthereumPrice
                                   - Check divergence vs lastUnichainPrice
                                                    │
V4 PoolManager        ─────────►   Sub 2: V4 Swap (Unichain PoolManager)
  Swap event                       - Decode sqrtPriceX96, compute price
  (sqrtPriceX96)                   - Update lastUnichainPrice
                                   - Check divergence vs lastEthereumPrice
                                                    │
                                   Divergence logic:
                                   - Require 3-streak minimum (noise filter)
                                   - fee = divergenceBps² × 80 / 100
                                   - Emit only if fee changed ≥ 5 bps (hysteresis)
                                   - emit Callback → updateDivergenceFee()
                                                    │
V3 Pool LP Mint       ─────────►   Sub 3: V3 Mint (Ethereum pool)
  (owner, tickLow,                 - Record positionEntryBlock
   tickHigh)                       - Only on first mint (preserves original entry)
                                                    │
V3 Pool LP Burn       ─────────►   Sub 4: V3 Burn (Ethereum pool)
  (owner, tickLow,                 - Compute hold duration (blocks)
   tickHigh)                       - If >= 50,400 blocks (~7 days):
                                     emit Callback → recordLPActivity()
                                                    │
                                                    ▼
                                         ArbShieldCallback.sol ──────────► ArbShieldHook.sol
                                         (rvmIdOnly relay)                  - updateDivergenceFee()
                                                                            - resetToBaseFee()
                                              ├───────────────────────────► LoyaltyRegistry.sol
                                                                            - recordLPActivity()
                                                                                     │
                                                                                     ▼
                                                                            ArbShieldHook.sol
                                                                            beforeSwap:
                                                                              fee = max(base, divergence)
                                                                              apply staleness decay
                                                                              apply loyalty discount
                                                                              enforce OVERRIDE_FEE_FLAG
                                                                            afterSwap:
                                                                              track totalArbFeeCaptured
                                                                              track loyalty discount usage
                                                                              observe Unichain priority fee
```

## Fee Model

### Divergence Fee (Quadratic)

```
divergenceBps = |priceEthereum - priceUnichain| / max(priceEthereum, priceUnichain) × 10000
rawFee        = (divergenceBps² × 80) / 100
effectiveFee  = min(rawFee, 50000)   -- hard cap at 5.00%
```

**Examples:**

| Divergence | Effective Fee | Impact |
|-----------|--------------|--------|
| 0.10% (10 bps) | 0.30% (base) | Below threshold — no change |
| 0.50% (50 bps) | 0.30% (base) | 50²×0.8 = 2000 bps < baseFee |
| 1.00% (100 bps) | 0.80% | Arber pays 2.67× normal fee |
| 2.00% (200 bps) | 3.20% | Arber pays 10.7× normal fee |
| 5.00% (500 bps) | **5.00% (capped)** | Max protection activated |

### Staleness Decay (5-Minute Linear)

If no new divergence signal arrives, the fee decays linearly to the base fee over 5 minutes:

```
fee(t) = baseFee + (divergenceFee - baseFee) × (STALENESS_PERIOD - elapsed) / STALENESS_PERIOD
```

This protects swappers from being stuck at high fees after prices re-converge on-chain. When an explicit convergence signal arrives (`divergenceBps < 10`), the fee resets to `baseFee` immediately — no waiting.

### LP Loyalty Discounts

LPs who hold positions on Ethereum for ≥ 7 days (`MIN_LOYALTY_BLOCKS = 50,400`) earn cross-chain fee discounts on Unichain:

| Tier | LP Events | Swap Discount |
|------|-----------|---------------|
| NONE | 0 | 0% |
| BRONZE | 1+ | 10% off effective fee |
| SILVER | 5+ | 20% off effective fee |
| GOLD | 10+ | 30% off effective fee |

Discounts apply on top of the (possibly elevated) divergence fee — rewarding LPs who stay through volatility with cheaper rebalancing costs.

## Contracts

| Contract | Network | Purpose |
|----------|---------|---------|
| `ArbShieldHook.sol` | Unichain | Dynamic fee hook — divergence fee + staleness decay + loyalty discount |
| `ArbShieldCallback.sol` | Unichain | Reactive Network relay — rvmIdOnly, 3 callback functions |
| `LoyaltyRegistry.sol` | Unichain | LP tier tracking — BRONZE / SILVER / GOLD, fee discounts |
| `ArbShieldReactive.sol` | Reactive Network | RSC — 4 subscriptions, divergence detection, LP loyalty qualification |

### ArbShieldHook

Uniswap v4 hook computing the effective swap fee dynamically.

**Hook Permissions**: `beforeInitialize`, `beforeSwap`, `afterSwap`

| Hook | Behavior |
|------|----------|
| `beforeInitialize` | Requires `DYNAMIC_FEE_FLAG` on pool init |
| `beforeSwap` | Computes `_getEffectiveFee()` (divergence + staleness decay), applies loyalty discount via `LoyaltyRegistry.getFeeDiscount()`, returns with `OVERRIDE_FEE_FLAG` |
| `afterSwap` | Tracks `totalArbFeeCaptured` (extra bps above base per swap), `totalLoyaltyDiscountsApplied`, Unichain priority fee (`tx.gasprice - block.basefee`) |

**Constants:**
- `baseFee = 3000` (0.30%)
- `MAX_FEE = 50000` (5.00%)
- `STALENESS_PERIOD = 5 minutes`

**Admin functions (owner-only):**
- `setCallbackContract(address)` — link callback relay; one-time
- `setLoyaltyRegistry(address)` — link loyalty registry; one-time
- `pause()` / `unpause()` — emergency circuit breaker

**View functions:**
- `getEffectiveFee()` — current decayed fee
- `isFeeElevated()` — bool + elevation bps above base
- `getProtocolStats()` — single call returning all metrics for dashboard display

**Callback-only functions (called exclusively by ArbShieldCallback):**
- `updateDivergenceFee(uint24 newFee, uint256 divergenceBps)` — raises fee, records `lastFeeUpdate`
- `resetToBaseFee()` — immediately clears divergence fee

### ArbShieldReactive

RSC on Reactive Network. **4 scoped subscriptions** monitor both chains simultaneously.

**Subscription 1 — Ethereum V3 Swap** (`ethereumPool`, `V3_SWAP_TOPIC_0`):
```
sqrtPriceX96 = decode(log.data)
lastEthereumPrice = sqrtPriceX96ToPrice(sqrtPriceX96)
→ _checkDivergenceAndEmitCallback()
```

**Subscription 2 — Unichain V4 Swap** (`unichainPool`, `V4_SWAP_TOPIC_0`):
```
sqrtPriceX96 = decode(log.data)  // same ABI offset as V3 — compatible decoder
lastUnichainPrice = sqrtPriceX96ToPrice(sqrtPriceX96)
→ _checkDivergenceAndEmitCallback()
```

**Subscription 3 — Ethereum V3 Mint** (`ethereumPool`, `MINT_TOPIC_0`):
```
positionKey = keccak256(abi.encode(topic1, topic2, topic3))
if positionEntryBlock[posKey] == 0:
    positionEntryBlock[posKey] = block_number    // only on first mint
    emit LPMintRecorded
```

**Subscription 4 — Ethereum V3 Burn** (`ethereumPool`, `BURN_TOPIC_0`):
```
duration = block_number - positionEntryBlock[posKey]
if duration >= MIN_LOYALTY_BLOCKS (50,400 blocks ≈ 7 days):
    delete positionEntryBlock[posKey]            // fresh timer on re-add
    emit LPDurationQualified
    emit Callback → recordLPActivity(rvm_id, lp)
```

**Divergence logic (called after every swap update when both prices are known):**
```
divergenceBps = |priceA - priceB| × 10000 / max(priceA, priceB)

if divergenceBps < DIVERGENCE_THRESHOLD_BPS (10):
    divergenceStreak = 0
    if lastEmittedFee > 0:
        lastEmittedFee = 0
        emit PricesConverged
        emit Callback → resetToBaseFee(rvm_id)
else:
    if divergenceStreak < MIN_DIVERGENCE_STREAK (3):
        divergenceStreak++
        return                                   // noise filter — wait for 3 signals
    fee = min(divergenceBps² × 80 / 100, MAX_FEE)
    if |fee - lastEmittedFee| >= FEE_CHANGE_THRESHOLD (500):
        lastEmittedFee = fee
        divergenceStreak = 0
        emit DivergenceDetected
        emit Callback → updateDivergenceFee(rvm_id, fee, divergenceBps)
```

**Price conversion (overflow-safe):**
```solidity
function sqrtPriceX96ToPrice(uint160 sqrtPriceX96) public pure returns (uint256) {
    uint256 shifted = uint256(sqrtPriceX96) >> 32;
    return (shifted * shifted) >> 128;
}
```

### ArbShieldCallback

Minimal relay on Unichain. All functions use `rvmIdOnly` to verify the Reactive VM ID.

| Function | Relays to | Description |
|----------|-----------|-------------|
| `updateDivergenceFee(_rvm_id, newFee, divergenceBps)` | `hook.updateDivergenceFee()` | Raises pool fee when divergence confirmed |
| `resetToBaseFee(_rvm_id)` | `hook.resetToBaseFee()` | Resets fee immediately on convergence |
| `recordLPActivity(_rvm_id, lp)` | `registry.recordLPActivity()` | Awards loyalty credit for qualified LP exit |

### LoyaltyRegistry

Tracks cross-chain LP commitment. Activity incremented only via the callback contract (Reactive Network relay).

| Function | Access | Description |
|----------|--------|-------------|
| `recordLPActivity(lp)` | Callback only | Increment LP event count; auto-advance tier |
| `getFeeDiscount(user)` | View | Returns discount bps (0 / 1000 / 2000 / 3000) |
| `setCallbackContract(address)` | Owner, one-time | Link callback relay |
| `setTier(user, tier)` | Owner | Manual tier override (migration / support) |

## File Structure

```
arbshield/
├── src/
│   ├── ArbShieldHook.sol        # Dynamic fee hook (divergence fee + decay + loyalty)
│   ├── ArbShieldCallback.sol    # Reactive Network relay (3 functions, rvmIdOnly)
│   ├── ArbShieldReactive.sol    # RSC: 4 subscriptions, divergence detection, LP tracking
│   └── LoyaltyRegistry.sol     # Cross-chain LP loyalty (BRONZE/SILVER/GOLD)
├── test/
│   ├── ArbShieldHook.t.sol      # 56 tests (unit, fuzz, integration)
│   ├── ArbShieldReactive.t.sol  # 48 tests (divergence, LP lifecycle, hysteresis)
│   ├── LoyaltyRegistry.t.sol    # 24 tests (tier progression, discounts, access control)
│   └── ArbShieldIntegration.t.sol  # 7 end-to-end scenarios (full Reactive → Callback → Hook path)
├── script/
│   ├── DeployHook.s.sol         # Unichain: Hook + Callback + Registry (CREATE2 + HookMiner)
│   └── DeployReactive.s.sol     # Reactive Network: RSC deployment
├── dashboard/                   # React + Vite frontend (fee monitor + LP loyalty stats)
├── foundry.toml
└── remappings.txt
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for dashboard)

### Build

```bash
cd arbshield
forge build
```

### Test

```bash
# All 135 tests
forge test -vv

# Watch divergence + reactive logic specifically
forge test --match-path test/ArbShieldReactive.t.sol -vv

# Full end-to-end integration scenarios
forge test --match-path test/ArbShieldIntegration.t.sol -vv
```

### Deploy

**Step 1 — Unichain Sepolia (Hook + Callback + LoyaltyRegistry):**
```bash
PRIVATE_KEY=<key> \
forge script script/DeployHook.s.sol \
  --rpc-url <unichain-sepolia-rpc> --broadcast
```

This mines a CREATE2 salt (via `HookMiner`) to find an address with the correct Uniswap v4 flag bits, then deploys all three Unichain contracts and wires them together.

**Step 2 — Reactive Network (RSC):**

> **Important:** Use `forge create`, not `forge script`. Reactive Lasna has a custom precompile at `0x64` that Foundry's simulation cannot execute — `forge script` will always revert on `service.subscribe()`.

```bash
forge create src/ArbShieldReactive.sol:ArbShieldReactive \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --private-key $REACTIVE_PRIVATE_KEY \
  --value 0.1ether \
  --broadcast \
  --constructor-args \
  <ethereum-v3-pool> \
  0x00B036B58a818B1BC34d502D3fE730Db729e62AC \
  <callback-address> \
  11155111 \
  1301
```

Replace `<ethereum-v3-pool>` with the Ethereum-side pool address (mainnet: `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640`; testnet: your deployed MockV3Pool).
The 0.1 lREACT sent with deployment covers the 4 `subscribe()` calls in the constructor.

### Dashboard

```bash
cd arbshield
npm install
npm run dev
```

### Deployment Addresses

#### Deployed Contracts (Testnet)

| Contract | Network | Address |
|----------|---------|---------|
| **ArbShieldHook** | Unichain Sepolia | `0xa0780721F3e29816708028d20D7906cAF44660c0` |
| **ArbShieldCallback** | Unichain Sepolia | `0x1ebf25b0e40a00a3bdc14a4c1ff2564afc0e9894` |
| **LoyaltyRegistry** | Unichain Sepolia | `0xc6d9516e6d04b0b65a3cbba45dd5c8a608496ff4` |
| **ArbShieldReactive** | Reactive Lasna | `0xD72Bd0eDE3d477C3a19304248E786363413ABE42` |
| **MockV3Pool** | Ethereum Sepolia | `0x7562e05BA8364DA1C9A8179cc3A996d5DDF7a98C` |
| mWETH | Ethereum Sepolia | `0xC6D9516E6D04b0b65A3cbba45DD5c8A608496Ff4` |
| mUSDC | Ethereum Sepolia | `0xd72bd0ede3d477c3a19304248e786363413abe42` |
| mWETH | Unichain Sepolia | `0x7562e05BA8364DA1C9A8179cc3A996d5DDF7a98C` |
| mUSDC | Unichain Sepolia | `0x927f446991425b1Df8fb7e3879192A84c31C6544` |

#### Protocol Infrastructure

| Contract | Network | Address |
|----------|---------|---------|
| PoolManager | Unichain Sepolia | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| Callback Proxy | Unichain Sepolia | `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4` |
| Uniswap V3 ETH/USDC 0.05% | Ethereum Mainnet | `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640` |

## Tests

**135 tests across four files — all passing.**

### ArbShieldHook.t.sol (56 tests)

- Hook permissions (`beforeInitialize`, `beforeSwap`, `afterSwap`)
- Dynamic fee: base fee when no divergence, divergence fee when set, MAX_FEE cap
- `updateDivergenceFee` and `resetToBaseFee`: `onlyCallback` access control, state correctness
- Staleness decay: linear decay over 5 minutes, exact boundary at `STALENESS_PERIOD`, `totalArbFeeCaptured` records decayed fee (not raw `currentDivergenceFee`)
- Loyalty discounts: NONE/BRONZE/SILVER/GOLD tiers applied on top of divergence fee, no uint24 overflow
- `getProtocolStats()`: all fields correct at default and after activity
- `isFeeElevated()`: false at base fee, true with correct elevation bps
- `totalSwaps` counter; `totalPriorityFeesCaptured` (Unichain MEV tax observation)
- `_resolveUser`: hookData decodes address for loyalty lookup (aggregator pattern)
- Emergency pause: blocks swaps, owner-only
- Zero-address validation on `setCallbackContract` / `setLoyaltyRegistry`
- Fuzz: fee never exceeds `MAX_FEE`, staleness always in valid range, loyalty + divergence combo never overflows uint24

### ArbShieldReactive.t.sol (48 tests)

- Swap event decoding: `sqrtPriceX96` extracted correctly from V3 and V4 layouts (compatible decoder)
- `sqrtPriceX96ToPrice`: overflow-safe bit-shift arithmetic, fuzz roundtrip
- Price routing: Ethereum V3 → `lastEthereumPrice`; Unichain V4 → `lastUnichainPrice`
- Divergence detection: below threshold (no callback), streak accumulation (3-streak noise filter), callback only after streak confirmed
- Hysteresis (500 bps): suppresses callback spam for small fee changes
- Convergence: `PricesConverged` + `resetToBaseFee` callback emitted; `lastEmittedFee` cleared
- LP Mint: `positionEntryBlock` recorded; re-mint idempotent (first-entry preserved)
- LP Burn: below `MIN_LOYALTY_BLOCKS` → no callback; at/above → `LPDurationQualified` + `Callback(recordLPActivity)`; entry cleared for fresh timer
- Callback payload structure: address(0) rvm_id placeholder, correct function selector
- Unknown event topics: silently ignored (defense-in-depth)
- Fuzz: divergence percentage computation correctness, price comparison symmetry

### LoyaltyRegistry.t.sol (24 tests)

- `recordLPActivity`: increments count, auto-advances tier (NONE → BRONZE → SILVER → GOLD)
- `getFeeDiscount`: correct bps per tier (0 / 1000 / 2000 / 3000)
- `TierUpdated` events emitted on advancement
- `totalLoyaltyMembers`: increments on first activity, no double-count on tier upgrade
- `setTier` (owner override): manual tier set, decrements count when reset to NONE
- Callback-only and owner-only access control
- One-time callback setup (`CallbackAlreadySet` guard)
- Zero-address validation

### ArbShieldIntegration.t.sol (7 scenarios)

End-to-end tests wiring the complete stack — `ArbShieldReactiveHarness` → `Callback` events → `ArbShieldCallback.call()` → `ArbShieldHook` / `LoyaltyRegistry`. Uses `_executeCallbackEvents()` to faithfully replay Reactive Network delivery (patches rvm_id placeholder with CALLBACK_PROXY, pranks as CALLBACK_PROXY):

| Scenario | What It Proves |
|----------|---------------|
| 1. Baseline swap | No divergence → `baseFee`, `totalArbFeeCaptured = 0` |
| 2. Ethereum diverges | Full reactive path: 1 ETH signal + 4 Unichain signals (3-streak) → `DivergenceFeeUpdated(50000, 7500)` → arb swap emits `ArbFeeCaptured(50000, 3000, 47000)` |
| 3. Fee decay | Fee set at T; at T+150s: 26500 (half of 47000 range + base); at T+300s: 3000 (full staleness) |
| 4. Convergence resets | Divergence → fee=50000 → convergent V4 signal → `PricesConverged` + `FeeResetToBase` → `baseFee` immediately |
| 5. LP loyalty path | Mint block 1000, burn block 51400 (50400 elapsed) → BRONZE → 10% discount on arb swap → `LoyaltyDiscountApplied(LP_USER, 1000, 18000)` |
| 6. Access control | `updateDivergenceFee` guarded by `onlyCallback`; callback `rvmIdOnly` rejects wrong rvm_id |
| 7. Full cycle stats | Divergence cycle + loyalty cycle → `getProtocolStats()` consistent across both |

## Partner Integrations

### Reactive Network
- **`src/ArbShieldReactive.sol`** — RSC with 4 scoped subscriptions monitoring Ethereum V3 and Unichain V4 swap events in real time. Implements divergence detection, 3-streak noise filter, 5-bps hysteresis, and LP loyalty tracking entirely on-chain with no off-chain infrastructure
- **`src/ArbShieldCallback.sol`** — deployed on Unichain; receives callbacks from ArbShieldReactive via `rvmIdOnly` modifier and relays to ArbShieldHook and LoyaltyRegistry
- Cross-chain price comparison is only possible because of Reactive Network — a hook alone cannot observe prices on another chain. This is the architectural centerpiece of ArbShield

### Unichain
- **`src/ArbShieldHook.sol`** — Uniswap v4 hook deployed on Unichain Sepolia
- Leverages Unichain's **Flashblocks** (2-second block time): divergence fee updates land within seconds of Ethereum price movement, beating arbitrageurs before they can execute
- `afterSwap` records `tx.gasprice - block.basefee` (Unichain priority fee / MEV tax), surfacing ordering pressure during arbitrage windows
- `src/ArbShieldCallback.sol` deployed at Unichain callback proxy `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4`

### Uniswap V3 (Ethereum)
- **`src/ArbShieldReactive.sol`** subscribes to `Swap`, `Mint`, and `Burn` events on the Ethereum Uniswap V3 ETH/USDC 0.05% pool (`0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640`)
- V3 `Swap(address,address,int256,int256,uint160,uint128,int24)` — `sqrtPriceX96` used as cross-chain reference price
- V3 `Mint` and `Burn` — used to track LP position entry/exit blocks for cross-chain loyalty qualification

### Uniswap V4 (Unichain)
- **`src/ArbShieldReactive.sol`** subscribes to `Swap` events on the Unichain V4 PoolManager (`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`)
- Uses a compatible ABI decoder for both V3 and V4 Swap layouts — `sqrtPriceX96` sits at the same byte offset in both events
- Divergence is computed against the V4 pool's own price — the signal is endogenous to the pool being protected

## License

MIT

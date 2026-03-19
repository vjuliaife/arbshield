import { formatUnits } from 'viem'

interface PricePanelProps {
  ethPrice: bigint | null
  sqrtPriceX96: bigint       // from Unichain v4 pool
  isLoading: boolean
}

// Convert sqrtPriceX96 to raw price (token1 raw units / token0 raw units).
// This matches what ArbShieldReactive reads from V4 Swap events for divergence comparison.
// At tick 0 (sqrtPriceX96 = 2^96): rawPrice = 1.0, matching the Ethereum pool's 1:1 seed price.
function sqrtPriceX96ToPrice(sqrtP: bigint): number {
  if (sqrtP === 0n) return 0
  const Q96f = 2 ** 96
  const ratio = Number(sqrtP) / Q96f
  return ratio * ratio
}

function formatPrice(price: number): string {
  if (price === 0) return '—'
  if (price < 0.0001) return price.toExponential(4)
  if (price > 1e6)    return price.toLocaleString('en-US', { maximumFractionDigits: 2 })
  return price.toFixed(4)
}

export default function PricePanel({ ethPrice, sqrtPriceX96, isLoading }: PricePanelProps) {
  const ethPriceHuman = ethPrice !== null ? Number(formatUnits(ethPrice, 0)) : null
  const uniPriceHuman = sqrtPriceX96 > 0n ? sqrtPriceX96ToPrice(sqrtPriceX96) : null

  // Divergence in bps: |eth - uni| / uni * 10000
  let divergenceBps: number | null = null
  if (ethPriceHuman !== null && uniPriceHuman !== null && uniPriceHuman > 0) {
    divergenceBps = Math.abs(ethPriceHuman - uniPriceHuman) / Math.max(ethPriceHuman, uniPriceHuman) * 10000
  }

  const isDiverged = divergenceBps !== null && divergenceBps > 100

  return (
    <div className="card space-y-3">
      <div className="label">Cross-Chain Price</div>
      {isLoading ? (
        <p className="text-xs text-uni-text font-mono">Loading…</p>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3">
            {/* Ethereum Sepolia */}
            <div className="rounded-lg bg-uni-bg p-2 border border-uni-border">
              <div className="text-[10px] text-uni-text font-mono mb-1">Ethereum Sepolia</div>
              <div className="text-sm font-mono font-bold text-white">
                {ethPriceHuman !== null ? ethPriceHuman.toString() : '—'}
              </div>
              <div className="text-[10px] text-uni-text font-mono">reserve1/reserve0</div>
            </div>

            {/* Unichain Sepolia */}
            <div className="rounded-lg bg-uni-bg p-2 border border-uni-border">
              <div className="text-[10px] text-uni-text font-mono mb-1">Unichain Sepolia</div>
              <div className="text-sm font-mono font-bold text-white">
                {uniPriceHuman !== null ? formatPrice(uniPriceHuman) : '—'}
              </div>
              <div className="text-[10px] text-uni-text font-mono">sqrtPriceX96 → price</div>
            </div>
          </div>

          {/* Divergence */}
          <div className={`flex items-center justify-between rounded-lg p-2 border ${
            isDiverged ? 'border-red-500/40 bg-red-500/10' : 'border-uni-border bg-uni-bg'
          }`}>
            <span className="text-[10px] font-mono text-uni-text">Divergence</span>
            <span className={`text-sm font-mono font-bold ${isDiverged ? 'text-red-400' : 'text-green-400'}`}>
              {divergenceBps !== null ? `${divergenceBps.toFixed(0)} bps` : '—'}
            </span>
          </div>

          {/* RSC status */}
          <div className="flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
            <span className="text-[10px] font-mono text-uni-text">
              RSC live · <span className="text-white">0xD72B…BE42</span>
            </span>
          </div>
        </>
      )}
    </div>
  )
}

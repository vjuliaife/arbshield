interface PricePanelProps {
  ethPrice: bigint | null      // from MockV3Pool.getPrice() — integer, price×1
  unichainPrice: number        // always 1 (reference)
  isLoading: boolean
}

function formatPrice(raw: bigint | null): string {
  if (raw === null) return '—'
  // getPrice() returns reserve1/reserve0 as integer (price of token0 in token1 units)
  // Starting price is 1 (1000:1000 seed), after diverge is 4 (500:2000)
  return Number(raw).toFixed(2)
}

function calcDivergenceBps(ethPrice: bigint | null, refPrice: number): number | null {
  if (ethPrice === null) return null
  const eth = Number(ethPrice)
  const ref = refPrice
  if (ref === 0) return null
  // Divergence = |eth - ref| / ref × 10000 bps
  return Math.round(Math.abs(eth - ref) / ref * 10000)
}

export default function PricePanel({ ethPrice, unichainPrice, isLoading }: PricePanelProps) {
  const divBps = calcDivergenceBps(ethPrice, unichainPrice)
  const isDiverged = divBps !== null && divBps > 100

  return (
    <div className="card flex flex-col gap-4">
      <div className="label">Cross-Chain Price</div>

      {/* Chain prices */}
      <div className="flex flex-col gap-3">
        {/* Ethereum Sepolia */}
        <div className="flex items-center justify-between rounded-lg bg-uni-bg px-3 py-2.5">
          <div className="flex items-center gap-2">
            <div className="w-5 h-5 rounded-full bg-blue-500/20 flex items-center justify-center">
              <div className="w-2.5 h-2.5 rounded-full bg-blue-400" />
            </div>
            <span className="text-xs text-uni-text font-mono">Ethereum</span>
          </div>
          <span className="font-mono font-semibold text-white">
            {isLoading && ethPrice === null ? (
              <span className="text-uni-text animate-pulse">loading…</span>
            ) : (
              `$${formatPrice(ethPrice)}`
            )}
          </span>
        </div>

        {/* Unichain Sepolia */}
        <div className="flex items-center justify-between rounded-lg bg-uni-bg px-3 py-2.5">
          <div className="flex items-center gap-2">
            <div className="w-5 h-5 rounded-full bg-uni-pink/20 flex items-center justify-center">
              <div className="w-2.5 h-2.5 rounded-full bg-uni-pink" />
            </div>
            <span className="text-xs text-uni-text font-mono">Unichain</span>
          </div>
          <span className="font-mono font-semibold text-white">
            ${unichainPrice.toFixed(2)}
          </span>
        </div>
      </div>

      {/* Divergence row */}
      <div className={`flex items-center justify-between rounded-lg px-3 py-2 border ${
        isDiverged
          ? 'bg-red-500/10 border-red-500/30'
          : 'bg-green-500/10 border-green-500/30'
      }`}>
        <span className="text-xs font-mono text-uni-text">Gap</span>
        <div className="flex items-center gap-2">
          <span className={`font-mono font-semibold text-sm ${isDiverged ? 'text-red-400' : 'text-green-400'}`}>
            {divBps === null ? '—' : `${divBps.toLocaleString()} bps`}
          </span>
          <span className="text-lg">{isDiverged ? '⚡' : '✓'}</span>
        </div>
      </div>

      {/* RSC status */}
      <div className="flex items-center gap-2 pt-1">
        <div className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
        <span className="text-xs text-uni-text font-mono">
          RSC monitoring Ethereum Sepolia
        </span>
      </div>
    </div>
  )
}

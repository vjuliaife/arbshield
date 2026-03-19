export interface ProtocolStats {
  effectiveFee: number
  baseFee: number
  divergenceFee: number
  lastFeeUpdate: bigint
  arbFeeCaptured: bigint
  loyaltyDiscounts: bigint
  totalSwaps: bigint
  isPaused: boolean
}

interface StatsPanelProps {
  stats: ProtocolStats | null
}

function timeSince(ts: bigint): string {
  if (ts === 0n) return 'never'
  const seconds = Math.floor(Date.now() / 1000) - Number(ts)
  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  return `${Math.floor(seconds / 3600)}h ago`
}

export default function StatsPanel({ stats }: StatsPanelProps) {
  if (!stats) {
    return (
      <div className="card">
        <div className="label mb-3">Protocol Stats</div>
        <div className="text-uni-text text-sm font-mono animate-pulse">Loading stats…</div>
      </div>
    )
  }

  const items = [
    {
      label: 'Total Swaps',
      value: stats.totalSwaps.toString(),
      color: 'text-white',
    },
    {
      label: 'Arb Fee Captured',
      value: `${stats.arbFeeCaptured.toLocaleString()} bps·swaps`,
      color: 'text-uni-pink',
    },
    {
      label: 'Loyalty Discounts',
      value: stats.loyaltyDiscounts.toString(),
      color: 'text-blue-400',
    },
    {
      label: 'Base Fee',
      value: `${(stats.baseFee / 100).toFixed(2)}%`,
      color: 'text-green-400',
    },
    {
      label: 'Divergence Fee',
      value: stats.divergenceFee > 0 ? `${(stats.divergenceFee / 100).toFixed(2)}%` : '—',
      color: 'text-yellow-400',
    },
    {
      label: 'Last Update',
      value: timeSince(stats.lastFeeUpdate),
      color: 'text-uni-text',
    },
    {
      label: 'Hook Status',
      value: stats.isPaused ? 'PAUSED' : 'ACTIVE',
      color: stats.isPaused ? 'text-red-400' : 'text-green-400',
    },
  ]

  return (
    <div className="card">
      <div className="label mb-3">Protocol Stats</div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-2 xl:grid-cols-3">
        {items.map(item => (
          <div key={item.label} className="rounded-lg bg-uni-bg p-2.5">
            <div className="text-[10px] text-uni-text font-mono uppercase tracking-wide mb-1">
              {item.label}
            </div>
            <div className={`text-sm font-mono font-semibold ${item.color} truncate`}>
              {item.value}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

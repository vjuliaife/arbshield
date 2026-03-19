interface ProtocolStats {
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

function timeAgo(ts: bigint): string {
  const now = Math.floor(Date.now() / 1000)
  const delta = now - Number(ts)
  if (delta < 0) return 'just now'
  if (delta < 60) return `${delta}s ago`
  if (delta < 3600) return `${Math.floor(delta / 60)}m ago`
  if (delta < 86400) return `${Math.floor(delta / 3600)}h ago`
  return `${Math.floor(delta / 86400)}d ago`
}

function fmt(bps: number): string {
  return (bps / 10000).toFixed(2) + '%'
}

interface StatRowProps { label: string; value: string; accent?: string }
function StatRow({ label, value, accent }: StatRowProps) {
  return (
    <div className="flex items-center justify-between py-1.5 border-b border-uni-border last:border-0">
      <span className="text-xs text-uni-text font-mono">{label}</span>
      <span className={`text-xs font-mono font-semibold ${accent ?? 'text-white'}`}>{value}</span>
    </div>
  )
}

export default function StatsPanel({ stats }: StatsPanelProps) {
  if (!stats) {
    return (
      <div className="card">
        <div className="label">Protocol Stats</div>
        <p className="text-xs text-uni-text font-mono mt-2">Loading…</p>
      </div>
    )
  }

  return (
    <div className="card">
      <div className="label">Protocol Stats</div>
      <div className="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-x-6">
        <StatRow label="Effective Fee"   value={fmt(stats.effectiveFee)}   accent={stats.effectiveFee > stats.baseFee ? 'text-red-400' : 'text-green-400'} />
        <StatRow label="Base Fee"        value={fmt(stats.baseFee)} />
        <StatRow label="Divergence Fee"  value={stats.divergenceFee > 0 ? fmt(stats.divergenceFee) : '—'} />
        <StatRow label="Total Swaps"     value={stats.totalSwaps.toLocaleString()} />
        <StatRow label="Arb Fee Captured" value={`${stats.arbFeeCaptured.toLocaleString()} bps·swaps`} />
        <StatRow label="Loyalty Discounts" value={stats.loyaltyDiscounts.toString()} />
        <StatRow label="Last Fee Update" value={stats.lastFeeUpdate > 0n ? timeAgo(stats.lastFeeUpdate) : 'never'} />
        <StatRow
          label="Hook Status"
          value={stats.isPaused ? 'PAUSED' : 'ACTIVE'}
          accent={stats.isPaused ? 'text-red-400' : 'text-green-400'}
        />
      </div>
    </div>
  )
}

export type { ProtocolStats }

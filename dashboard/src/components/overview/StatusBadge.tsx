import { motion } from 'framer-motion'

interface StatusBadgeProps {
  fee: number
  elevated: boolean
  elevationBps: number
}

const BASE_FEE = 3000
const MAX_FEE  = 50000
type Status = 'BASE' | 'DECAYING' | 'ELEVATED'

function getStatus(fee: number, elevated: boolean): Status {
  if (!elevated || fee <= BASE_FEE) return 'BASE'
  if (fee >= MAX_FEE * 0.9) return 'ELEVATED'
  return 'DECAYING'
}

const STATUS_CONFIG: Record<Status, { color: string; dot: string; label: string; bg: string }> = {
  BASE:     { color: 'text-green-400',  dot: 'bg-green-400',  label: 'BASE FEE', bg: 'bg-green-400/10 border-green-400/30' },
  DECAYING: { color: 'text-yellow-400', dot: 'bg-yellow-400', label: 'DECAYING', bg: 'bg-yellow-400/10 border-yellow-400/30' },
  ELEVATED: { color: 'text-red-400',    dot: 'bg-red-400',    label: 'ELEVATED', bg: 'bg-red-400/10 border-red-400/30' },
}

export default function StatusBadge({ fee, elevated, elevationBps }: StatusBadgeProps) {
  const status = getStatus(fee, elevated)
  const cfg = STATUS_CONFIG[status]
  return (
    <div className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 ${cfg.bg}`}>
      {status === 'ELEVATED' ? (
        <motion.span className={`status-dot ${cfg.dot}`} animate={{ opacity: [1, 0.2, 1] }} transition={{ duration: 1.2, repeat: Infinity }} />
      ) : (
        <span className={`status-dot ${cfg.dot}`} />
      )}
      <span className={`text-xs font-mono font-semibold ${cfg.color}`}>{cfg.label}</span>
      {elevated && elevationBps > 0 && (
        <span className="text-xs font-mono text-uni-text">+{elevationBps} bps</span>
      )}
    </div>
  )
}

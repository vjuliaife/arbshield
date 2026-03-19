import { motion } from 'framer-motion'

interface FeeGaugeProps {
  fee: number      // in bps, e.g. 3000
  elevated: boolean
}

const MIN_FEE = 3000
const MAX_FEE = 50000
const CX = 100
const CY = 100
const RADIUS = 78
const CIRCUMFERENCE = 2 * Math.PI * RADIUS        // ≈ 490.09
const ARC_FRACTION = 270 / 360                     // 0.75 (270° sweep)
const ARC_LENGTH = CIRCUMFERENCE * ARC_FRACTION    // ≈ 367.57
const GAP_LENGTH = CIRCUMFERENCE - ARC_LENGTH      // ≈ 122.52

function feeToPercent(fee: number): number {
  return Math.max(0, Math.min(1, (fee - MIN_FEE) / (MAX_FEE - MIN_FEE)))
}

function feeColor(percent: number): string {
  if (percent < 0.15) return '#22C55E'   // green
  if (percent < 0.4)  return '#EAB308'   // yellow
  if (percent < 0.7)  return '#F97316'   // orange
  return '#EF4444'                        // red
}

function formatFee(bps: number): string {
  return (bps / 10000).toFixed(2) + '%'
}

export default function FeeGauge({ fee, elevated }: FeeGaugeProps) {
  const percent = feeToPercent(fee)
  const filledLength = percent * ARC_LENGTH
  const color = feeColor(percent)

  return (
    <div className="card flex flex-col items-center gap-3">
      <div className="label w-full">Fee Gauge</div>

      <div className="relative">
        <svg width="200" height="160" viewBox="0 0 200 180">
          {/* Background arc — 270° sweep starting at 7:30 */}
          <circle
            cx={CX}
            cy={CY}
            r={RADIUS}
            fill="none"
            stroke="#1B2234"
            strokeWidth="14"
            strokeLinecap="round"
            strokeDasharray={`${ARC_LENGTH} ${GAP_LENGTH}`}
            transform={`rotate(135, ${CX}, ${CY})`}
          />

          {/* Foreground arc — animated */}
          <motion.circle
            cx={CX}
            cy={CY}
            r={RADIUS}
            fill="none"
            stroke={color}
            strokeWidth="14"
            strokeLinecap="round"
            strokeDasharray={`${filledLength} ${CIRCUMFERENCE - filledLength}`}
            transform={`rotate(135, ${CX}, ${CY})`}
            animate={{
              strokeDasharray: `${filledLength} ${CIRCUMFERENCE - filledLength}`,
              stroke: color,
            }}
            transition={{ duration: 0.8, ease: 'easeInOut' }}
            style={{ filter: elevated ? `drop-shadow(0 0 8px ${color})` : 'none' }}
          />

          {/* Tick marks at min and max */}
          <text x="14" y="152" fill="#98A1C0" fontSize="9" fontFamily="JetBrains Mono">0.30%</text>
          <text x="155" y="152" fill="#98A1C0" fontSize="9" fontFamily="JetBrains Mono">5.00%</text>

          {/* Center fee display */}
          <text
            x={CX}
            y={CY - 8}
            textAnchor="middle"
            fill="white"
            fontSize="26"
            fontWeight="bold"
            fontFamily="JetBrains Mono"
          >
            {formatFee(fee)}
          </text>
          <text
            x={CX}
            y={CY + 14}
            textAnchor="middle"
            fill="#98A1C0"
            fontSize="10"
            fontFamily="JetBrains Mono"
          >
            {fee} bps
          </text>
        </svg>

        {/* Pulsing ring when elevated */}
        {elevated && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <motion.div
              className="w-32 h-32 rounded-full border-2 border-red-500"
              animate={{ scale: [1, 1.08, 1], opacity: [0.6, 0.2, 0.6] }}
              transition={{ duration: 1.5, repeat: Infinity, ease: 'easeInOut' }}
            />
          </div>
        )}
      </div>

      {/* Min / Max labels */}
      <div className="flex w-full justify-between px-2">
        <span className="text-xs font-mono text-green-500">BASE 0.30%</span>
        <span className="text-xs font-mono text-red-500">MAX 5.00%</span>
      </div>
    </div>
  )
}

import { motion, AnimatePresence } from 'framer-motion'
import { etherscanTx, blockscoutTx } from '../constants'

export interface TxStep {
  label: string
  status: 'idle' | 'pending' | 'done' | 'error'
  hash?: `0x${string}`
  error?: string
}

interface TxFlowProps {
  steps: TxStep[]
  chainId?: number  // determines which explorer to use
  onClose?: () => void
}

const CHAIN_ETH  = 11155111
// const CHAIN_UNI  = 1301

function explorerLink(hash: string, chainId?: number): string {
  return chainId === CHAIN_ETH ? etherscanTx(hash) : blockscoutTx(hash)
}

function StepIcon({ status }: { status: TxStep['status'] }) {
  if (status === 'done') {
    return (
      <span className="w-5 h-5 flex items-center justify-center rounded-full bg-green-500/20 text-green-400 text-xs">✓</span>
    )
  }
  if (status === 'error') {
    return (
      <span className="w-5 h-5 flex items-center justify-center rounded-full bg-red-500/20 text-red-400 text-xs">✗</span>
    )
  }
  if (status === 'pending') {
    return (
      <motion.span
        className="w-5 h-5 flex items-center justify-center rounded-full bg-uni-pink/20 border border-uni-pink text-xs"
        animate={{ rotate: 360 }}
        transition={{ duration: 1.2, repeat: Infinity, ease: 'linear' }}
      >
        ⟳
      </motion.span>
    )
  }
  return <span className="w-5 h-5 flex items-center justify-center rounded-full bg-uni-border text-uni-text text-xs">○</span>
}

export default function TxFlow({ steps, chainId, onClose }: TxFlowProps) {
  const allDone = steps.every(s => s.status === 'done')
  const hasError = steps.some(s => s.status === 'error')
  const active = steps.some(s => s.status === 'pending')

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 8 }}
        className="mt-3 rounded-lg border border-uni-border bg-uni-bg/80 p-3 space-y-2"
      >
        {/* Status header */}
        <div className="flex items-center justify-between">
          <span className="text-xs font-mono text-uni-text">
            {allDone ? '✓ Done' : hasError ? '✗ Failed' : active ? 'Processing…' : 'Queued'}
          </span>
          {onClose && (allDone || hasError) && (
            <button
              onClick={onClose}
              className="text-xs text-uni-text hover:text-white transition-colors px-2 py-0.5 rounded border border-uni-border"
            >
              ✕
            </button>
          )}
        </div>

        {/* Steps */}
        {steps.map((step, i) => (
          <div key={i} className="flex items-start gap-2">
            <div className="mt-0.5 flex-shrink-0">
              <StepIcon status={step.status} />
            </div>
            <div className="flex-1 min-w-0">
              <div className={`text-xs font-mono ${
                step.status === 'done'  ? 'text-green-400' :
                step.status === 'error' ? 'text-red-400'   :
                step.status === 'pending' ? 'text-white'   : 'text-uni-text'
              }`}>
                {step.label}
              </div>
              {step.hash && (
                <a
                  href={explorerLink(step.hash, chainId)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[10px] font-mono text-uni-pink hover:underline"
                >
                  {step.hash.slice(0, 10)}…{step.hash.slice(-6)} ↗
                </a>
              )}
              {step.error && (
                <p className="text-[10px] font-mono text-red-400 mt-0.5 break-all">{step.error}</p>
              )}
            </div>
          </div>
        ))}
      </motion.div>
    </AnimatePresence>
  )
}

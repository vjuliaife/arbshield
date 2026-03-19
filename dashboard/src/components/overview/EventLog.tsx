import { useEffect, useRef } from 'react'

export interface LogEntry {
  id: string
  timestamp: Date
  name: string
  args: Record<string, string>
  type: 'divergence' | 'reset' | 'arb' | 'loyalty' | 'info'
}

const TYPE_STYLE: Record<LogEntry['type'], { border: string; label: string; text: string }> = {
  divergence: { border: 'border-red-500/40',    label: 'bg-red-500/20 text-red-400',      text: 'text-red-300'    },
  reset:      { border: 'border-green-500/40',  label: 'bg-green-500/20 text-green-400',  text: 'text-green-300'  },
  arb:        { border: 'border-orange-500/40', label: 'bg-orange-500/20 text-orange-400',text: 'text-orange-300' },
  loyalty:    { border: 'border-blue-500/40',   label: 'bg-blue-500/20 text-blue-400',    text: 'text-blue-300'   },
  info:       { border: 'border-uni-border',    label: 'bg-uni-border text-uni-text',     text: 'text-uni-text'   },
}

interface EventLogProps {
  entries:   LogEntry[]
  fromBlock: bigint
}

export default function EventLog({ entries, fromBlock }: EventLogProps) {
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [entries])

  const shown = entries.slice(-20)

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-2">
        <span className="label">Event Log</span>
        <div className="flex items-center gap-3">
          {fromBlock > 0n && (
            <span className="text-[9px] font-mono text-uni-text/60" title="Scanning from this block">
              from block {fromBlock.toString()}
            </span>
          )}
          <span className="text-[10px] font-mono text-uni-text">{entries.length} events</span>
        </div>
      </div>
      <div className="space-y-1.5 max-h-56 overflow-y-auto custom-scrollbar">
        {shown.length === 0 ? (
          <div className="py-3 space-y-1">
            <p className="text-xs text-uni-text font-mono">No hook events in the last 10,000 blocks.</p>
            <p className="text-[10px] text-uni-text/60 font-mono">
              Events appear when: divergence is detected (DivergenceFeeUpdated), fee resets (FeeResetToBase),
              arb fee is captured (ArbFeeCaptured — only when fee is elevated), or a swap carries a priority fee
              (UnichainPriorityFeeMonitored). Trigger 3 divergence swaps on Ethereum Sepolia to activate fee elevation.
            </p>
          </div>
        ) : (
          shown.map(entry => {
            const style = TYPE_STYLE[entry.type]
            return (
              <div key={entry.id} className={`rounded-lg border p-2 ${style.border}`}>
                <div className="flex items-center gap-2 mb-1">
                  <span className={`text-[9px] font-mono px-1.5 py-0.5 rounded-full ${style.label}`}>
                    {entry.name}
                  </span>
                  <span className="text-[9px] text-uni-text font-mono">
                    {entry.timestamp.toLocaleTimeString()}
                  </span>
                </div>
                <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                  {Object.entries(entry.args).map(([k, v]) => (
                    <span key={k} className={`text-[10px] font-mono ${style.text}`}>
                      {k}: {v}
                    </span>
                  ))}
                </div>
              </div>
            )
          })
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}

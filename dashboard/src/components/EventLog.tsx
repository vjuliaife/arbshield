import { useEffect, useRef } from 'react'

export interface LogEntry {
  id: string
  timestamp: Date
  name: string
  args: Record<string, string>
  type: 'divergence' | 'reset' | 'arb' | 'loyalty' | 'info'
}

interface EventLogProps {
  entries: LogEntry[]
  fromBlock?: bigint
}

const TYPE_CONFIG: Record<LogEntry['type'], { color: string; bg: string; label: string }> = {
  divergence: { color: 'text-red-400',    bg: 'bg-red-400/10',    label: 'DIV' },
  reset:      { color: 'text-green-400',  bg: 'bg-green-400/10',  label: 'RST' },
  arb:        { color: 'text-orange-400', bg: 'bg-orange-400/10', label: 'ARB' },
  loyalty:    { color: 'text-blue-400',   bg: 'bg-blue-400/10',   label: 'LYL' },
  info:       { color: 'text-uni-text',   bg: 'bg-uni-bg',        label: 'INF' },
}

function formatTime(date: Date): string {
  return date.toLocaleTimeString('en-US', { hour12: false })
}

function formatArgs(args: Record<string, string>): string {
  return Object.entries(args)
    .map(([k, v]) => `${k}=${v}`)
    .join(', ')
}

export default function EventLog({ entries, fromBlock }: EventLogProps) {
  const bottomRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to bottom on new entries
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [entries.length])

  return (
    <div className="card flex flex-col gap-2" style={{ minHeight: '160px' }}>
      <div className="flex items-center justify-between">
        <div className="label">Live Event Log</div>
        <div className="flex items-center gap-1.5">
          <div className="w-1.5 h-1.5 rounded-full bg-uni-pink animate-pulse" />
          <span className="text-[10px] text-uni-text font-mono">
            {fromBlock && fromBlock > 0n ? `from #${fromBlock.toLocaleString()}` : 'Unichain Sepolia'}
          </span>
        </div>
      </div>

      <div
        className="flex-1 overflow-y-auto flex flex-col gap-1 font-mono text-xs"
        style={{ maxHeight: '200px' }}
      >
        {entries.length === 0 ? (
          <div className="text-uni-text py-4 text-center text-[11px]">
            No events yet — trigger divergence to see activity
          </div>
        ) : (
          entries.slice(-10).map(entry => {
            const cfg = TYPE_CONFIG[entry.type]
            return (
              <div
                key={entry.id}
                className={`flex items-start gap-2 rounded px-2 py-1 ${cfg.bg}`}
              >
                {/* Timestamp */}
                <span className="text-uni-text shrink-0 text-[10px] mt-0.5">
                  {formatTime(entry.timestamp)}
                </span>

                {/* Type badge */}
                <span className={`shrink-0 text-[9px] font-bold px-1 rounded ${cfg.color} border border-current/30 mt-0.5`}>
                  {cfg.label}
                </span>

                {/* Event name + args */}
                <div className="flex-1 min-w-0">
                  <span className={`font-semibold ${cfg.color}`}>{entry.name}</span>
                  {Object.keys(entry.args).length > 0 && (
                    <span className="text-uni-text ml-1">
                      — {formatArgs(entry.args)}
                    </span>
                  )}
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

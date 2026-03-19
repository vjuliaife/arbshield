import { useState, useEffect, useRef, useCallback } from 'react'
import {
  ADDRESSES, HOOK_ABI, POOL_MANAGER_ABI, POOL_ABI, POOL_STATE_SLOT,
  ethClient, unichainClient, parseSlot0,
  encodeV3Swap, sendTx, waitForTx, CHAIN_IDS,
} from '../../constants'
import PricePanel from './PricePanel'
import StatsPanel from './StatsPanel'
import type { ProtocolStats } from './StatsPanel'
import FeeGauge from './FeeGauge'
import StatusBadge from './StatusBadge'
import EventLog from './EventLog'
import type { LogEntry } from './EventLog'

interface OverviewTabProps {
  account: `0x${string}` | null
  chainId: number | null
  onLastPolled: (d: Date) => void
  onRpcError: (e: string | null) => void
}

const EVENT_TYPES: Record<string, LogEntry['type']> = {
  DivergenceFeeUpdated:         'divergence',
  FeeResetToBase:               'reset',
  ArbFeeCaptured:               'arb',
  LoyaltyDiscountApplied:       'loyalty',
  UnichainPriorityFeeMonitored: 'info',
  Paused:   'info',
  Unpaused: 'info',
}

function errMsg(e: unknown): string {
  if (e instanceof Error) return e.message
  return (e as any)?.message ?? JSON.stringify(e)
}

const EVENT_NAMES = [
  'DivergenceFeeUpdated', 'FeeResetToBase', 'ArbFeeCaptured',
  'LoyaltyDiscountApplied', 'UnichainPriorityFeeMonitored', 'Paused', 'Unpaused',
]

// Unichain Sepolia RPC limits getLogs to ~2,000 blocks per call.
// We chunk the range and query all event types per chunk in parallel.
async function fetchHookEvents(fromBlock: bigint, toBlock: bigint): Promise<LogEntry[]> {
  const CHUNK = 2000n
  const entries: LogEntry[] = []

  for (let start = fromBlock; start <= toBlock; start += CHUNK) {
    const end = start + CHUNK - 1n < toBlock ? start + CHUNK - 1n : toBlock

    const results = await Promise.all(
      EVENT_NAMES.map(name =>
        unichainClient.getLogs({
          address: ADDRESSES.UNI.HOOK,
          event: HOOK_ABI.find(e => e.type === 'event' && e.name === name) as any,
          fromBlock: start,
          toBlock: end,
        }).catch(err => {
          console.warn(`getLogs ${name} [${start}–${end}] failed:`, err)
          return [] as any[]
        })
      )
    )

    results.forEach((logs, i) => {
      const name = EVENT_NAMES[i]
      logs.forEach((log: any) => {
        const args: Record<string, string> = {}
        if (log.args) {
          Object.entries(log.args).forEach(([k, v]) => {
            args[k] = typeof v === 'bigint' ? v.toString() : String(v)
          })
        }
        entries.push({
          id: `${log.transactionHash}-${log.logIndex}`,
          timestamp: new Date(),
          name,
          args,
          type: EVENT_TYPES[name] ?? 'info',
        })
      })
    })
  }

  return entries.sort((a, b) => a.id.localeCompare(b.id))
}

export default function OverviewTab({ account, chainId, onLastPolled, onRpcError }: OverviewTabProps) {
  const [stats, setStats] = useState<ProtocolStats | null>(null)
  const [ethPrice, setEthPrice] = useState<bigint | null>(null)
  const [sqrtPriceX96, setSqrtPriceX96] = useState<bigint>(0n)
  const [events, setEvents] = useState<LogEntry[]>([])
  const [fromBlockDisplay, setFromBlockDisplay] = useState<bigint>(0n)
  const [divergeSteps, setDivergeSteps] = useState<string[]>([])
  const [convergeSteps, setConvergeSteps] = useState<string[]>([])

  const seenEvents  = useRef(new Set<string>())
  const fromBlockRef = useRef<bigint>(0n)

  const poll = useCallback(async () => {
    try {
      // Protocol stats
      const s = await unichainClient.readContract({
        address: ADDRESSES.UNI.HOOK,
        abi: HOOK_ABI,
        functionName: 'getProtocolStats',
      }) as unknown as readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint, boolean]

      setStats({
        effectiveFee:    Number(s[0]),
        baseFee:         Number(s[1]),
        divergenceFee:   Number(s[2]),
        lastFeeUpdate:   s[3],
        arbFeeCaptured:  s[4],
        loyaltyDiscounts: s[5],
        totalSwaps:      s[6],
        isPaused:        s[7],
      })

      // Unichain pool sqrtPriceX96
      try {
        const raw = await unichainClient.readContract({
          address: ADDRESSES.UNI.POOL_MANAGER,
          abi: POOL_MANAGER_ABI,
          functionName: 'extsload',
          args: [POOL_STATE_SLOT],
        })
        setSqrtPriceX96(parseSlot0(raw as `0x${string}`).sqrtPriceX96)
      } catch { /* pool not initialized yet */ }

      // Ethereum pool price
      try {
        const price = await ethClient.readContract({
          address: ADDRESSES.ETH.POOL,
          abi: POOL_ABI,
          functionName: 'getPrice',
        }) as bigint
        setEthPrice(price)
      } catch { /* ignore */ }

      // Events — scan last 25,000 blocks on first load (~90 min on Unichain Flashblocks)
      const latestBlock = await unichainClient.getBlockNumber().catch(() => 25000n)
      if (fromBlockRef.current === 0n) {
        fromBlockRef.current = latestBlock > 25000n ? latestBlock - 25000n : 1n
        setFromBlockDisplay(fromBlockRef.current)
      }
      const newEntries = await fetchHookEvents(fromBlockRef.current, latestBlock)
      const unseen = newEntries.filter(e => !seenEvents.current.has(e.id))
      if (unseen.length > 0) {
        unseen.forEach(e => seenEvents.current.add(e.id))
        setEvents(prev => [...prev, ...unseen].slice(-50))
      }
      // Advance the window so subsequent polls only scan recent blocks
      fromBlockRef.current = latestBlock > 5n ? latestBlock - 5n : fromBlockRef.current

      onLastPolled(new Date())
      onRpcError(null)
    } catch (err) {
      onRpcError(errMsg(err))
    }
  }, [onLastPolled, onRpcError])

  useEffect(() => {
    poll()
    const id = setInterval(poll, 8000)
    return () => clearInterval(id)
  }, [poll])

  const elevated = stats !== null && stats.effectiveFee > stats.baseFee

  async function triggerDivergence() {
    if (!account) return
    setDivergeSteps(['Sending swap (zeroForOne=true) on Ethereum V3 pool…'])
    try {
      if (chainId !== CHAIN_IDS.ETH_SEPOLIA) {
        setDivergeSteps(p => [...p, '⚠ Switch to Ethereum Sepolia first'])
        return
      }
      const data = encodeV3Swap(true, 100n * 10n ** 18n, account)
      const hash = await sendTx(ADDRESSES.ETH.POOL, data, account)
      setDivergeSteps(p => [...p, `Waiting… (${hash.slice(0, 10)}…)`])
      await waitForTx(hash)
      setDivergeSteps(p => [...p, `✓ Done · ${hash.slice(0, 18)}…`])
      setDivergeSteps(p => [...p, 'RSC detects divergence after 3 consecutive swaps'])
    } catch (err) {
      setDivergeSteps(p => [...p, `✗ ${errMsg(err)}`])
    }
  }

  async function triggerConverge() {
    if (!account) return
    setConvergeSteps(['Sending swap (zeroForOne=false) on Ethereum V3 pool…'])
    try {
      if (chainId !== CHAIN_IDS.ETH_SEPOLIA) {
        setConvergeSteps(p => [...p, '⚠ Switch to Ethereum Sepolia first'])
        return
      }
      const data = encodeV3Swap(false, 100n * 10n ** 18n, account)
      const hash = await sendTx(ADDRESSES.ETH.POOL, data, account)
      setConvergeSteps(p => [...p, `Waiting… (${hash.slice(0, 10)}…)`])
      await waitForTx(hash)
      setConvergeSteps(p => [...p, `✓ Done · ${hash.slice(0, 18)}…`])
    } catch (err) {
      setConvergeSteps(p => [...p, `✗ ${errMsg(err)}`])
    }
  }

  return (
    <div className="p-4 space-y-4">
      {/* Top row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <PricePanel
          ethPrice={ethPrice}
          sqrtPriceX96={sqrtPriceX96}
          isLoading={ethPrice === null && sqrtPriceX96 === 0n}
        />
        <div className="space-y-3">
          <FeeGauge fee={stats?.effectiveFee ?? 3000} elevated={elevated} />
          <div className="flex justify-center">
            <StatusBadge
              fee={stats?.effectiveFee ?? 3000}
              elevated={elevated}
              elevationBps={stats ? Math.max(0, stats.effectiveFee - stats.baseFee) : 0}
            />
          </div>
        </div>
      </div>

      {/* Protocol stats */}
      <StatsPanel stats={stats} />

      {/* Divergence simulator */}
      <div className="card space-y-3">
        <div className="label">Divergence Simulator</div>
        <p className="text-[10px] text-uni-text font-mono">
          Swap on Ethereum Sepolia V3 pool to shift the reference price.
          The RSC emits a fee callback after 3 consecutive divergent signals (≥ 10 bps).
          Connect on Ethereum Sepolia to send.
        </p>
        <div className="flex gap-3 flex-wrap">
          <button
            className="btn text-xs bg-red-700 hover:bg-red-600 text-white disabled:opacity-50"
            disabled={!account}
            onClick={triggerDivergence}
          >
            Trigger Divergence ↑
          </button>
          <button
            className="btn text-xs bg-emerald-700 hover:bg-emerald-600 text-white disabled:opacity-50"
            disabled={!account}
            onClick={triggerConverge}
          >
            Converge Prices ↓
          </button>
          {(divergeSteps.length > 0 || convergeSteps.length > 0) && (
            <button
              className="btn text-xs text-uni-text border-uni-border"
              onClick={() => { setDivergeSteps([]); setConvergeSteps([]) }}
            >
              Clear
            </button>
          )}
        </div>
        {divergeSteps.length > 0 && (
          <div className="rounded-lg bg-uni-bg border border-uni-border p-2 space-y-0.5">
            {divergeSteps.map((s, i) => (
              <p key={i} className="text-[10px] font-mono text-uni-text">{s}</p>
            ))}
          </div>
        )}
        {convergeSteps.length > 0 && (
          <div className="rounded-lg bg-uni-bg border border-uni-border p-2 space-y-0.5">
            {convergeSteps.map((s, i) => (
              <p key={i} className="text-[10px] font-mono text-uni-text">{s}</p>
            ))}
          </div>
        )}
      </div>

      {/* Event log */}
      <EventLog entries={events} fromBlock={fromBlockDisplay} />
    </div>
  )
}

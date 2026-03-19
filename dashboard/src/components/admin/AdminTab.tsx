import { useState } from 'react'
import {
  ADDRESSES, HOOK_ABI, LOYALTY_REGISTRY_ABI,
  CHAIN_IDS, sendTx, waitForTx, encodeFunctionData,
} from '../../constants'

interface Props {
  account: `0x${string}` | null
  chainId: number | null
  onSwitchUni: () => void
}

type Status = { type: 'idle' | 'pending' | 'success' | 'error'; message: string }

export default function AdminTab({ account, chainId, onSwitchUni }: Props) {
  const [lpAddr,  setLpAddr]  = useState('')
  const [tierVal, setTierVal] = useState<number>(1)
  const [status1, setStatus1] = useState<Status>({ type: 'idle', message: '' })
  const [status2, setStatus2] = useState<Status>({ type: 'idle', message: '' })

  const onUnichain = chainId === CHAIN_IDS.UNICHAIN

  async function runHookAction(fn: 'pause' | 'unpause', setter: (s: Status) => void) {
    if (!account) return
    setter({ type: 'pending', message: 'Sending transaction…' })
    try {
      const data = encodeFunctionData({ abi: HOOK_ABI, functionName: fn, args: [] })
      const hash = await sendTx(ADDRESSES.UNI.HOOK, data, account)
      setter({ type: 'pending', message: `Waiting… (${hash.slice(0, 10)}…)` })
      await waitForTx(hash)
      setter({ type: 'success', message: `${fn === 'pause' ? 'Hook paused' : 'Hook unpaused'} · tx: ${hash.slice(0, 18)}…` })
    } catch (e) {
      setter({ type: 'error', message: e instanceof Error ? e.message : 'Transaction failed' })
    }
  }

  async function runSetTier() {
    const a = lpAddr.trim()
    if (!/^0x[0-9a-fA-F]{40}$/.test(a)) {
      setStatus2({ type: 'error', message: 'Invalid LP address' })
      return
    }
    if (!account) return
    setStatus2({ type: 'pending', message: 'Sending transaction…' })
    try {
      const data = encodeFunctionData({
        abi: LOYALTY_REGISTRY_ABI, functionName: 'setTier', args: [a as `0x${string}`, tierVal as 0 | 1 | 2 | 3],
      })
      const hash = await sendTx(ADDRESSES.UNI.LOYALTY, data, account)
      setStatus2({ type: 'pending', message: `Waiting… (${hash.slice(0, 10)}…)` })
      await waitForTx(hash)
      setStatus2({ type: 'success', message: `Tier set to ${['NONE','BRONZE','SILVER','GOLD'][tierVal]} · tx: ${hash.slice(0, 18)}…` })
    } catch (e) {
      setStatus2({ type: 'error', message: e instanceof Error ? e.message : 'Transaction failed' })
    }
  }

  function StatusBox({ s }: { s: Status }) {
    if (s.type === 'idle') return null
    const cls = s.type === 'success'
      ? 'bg-green-900/30 border-green-700 text-green-300'
      : s.type === 'error'
        ? 'bg-red-900/30 border-red-700 text-red-300'
        : 'bg-blue-900/30 border-blue-700 text-blue-300'
    return (
      <div className={`rounded-lg px-3 py-2 text-xs border font-mono ${cls}`}>
        {s.type === 'pending' && <span className="mr-1 inline-block animate-spin">⟳</span>}
        {s.message}
      </div>
    )
  }

  if (!account) return (
    <div className="p-4">
      <div className="card text-center py-10">
        <div className="text-3xl mb-3">🔌</div>
        <div className="text-sm text-uni-text font-mono">Connect wallet to use admin actions</div>
      </div>
    </div>
  )

  if (!onUnichain) return (
    <div className="p-4">
      <div className="card text-center py-10">
        <div className="text-3xl mb-3">⛓️</div>
        <div className="text-sm text-uni-text font-mono mb-4">Switch to Unichain Sepolia to use admin actions</div>
        <button onClick={onSwitchUni} className="btn btn-pink text-xs">Switch to Unichain</button>
      </div>
    </div>
  )

  return (
    <div className="p-4 space-y-4">
      {/* Hook pause controls */}
      <div className="card space-y-3">
        <div className="label">Hook Controls</div>
        <p className="text-[11px] text-uni-text font-mono">
          Owner-only. Pausing the hook causes all swaps to revert until unpaused.
        </p>
        <div className="flex gap-3 flex-wrap">
          <button
            className="btn text-xs bg-red-700 hover:bg-red-600 text-white disabled:opacity-50"
            disabled={status1.type === 'pending'}
            onClick={() => runHookAction('pause', setStatus1)}
          >
            Pause Hook
          </button>
          <button
            className="btn text-xs bg-emerald-700 hover:bg-emerald-600 text-white disabled:opacity-50"
            disabled={status1.type === 'pending'}
            onClick={() => runHookAction('unpause', setStatus1)}
          >
            Unpause Hook
          </button>
        </div>
        <StatusBox s={status1} />
      </div>

      {/* Loyalty tier override */}
      <div className="card space-y-3">
        <div className="label">Loyalty Tier Override</div>
        <p className="text-[11px] text-uni-text font-mono">
          Directly set a wallet's loyalty tier (owner-only on LoyaltyRegistry).
          In production, tiers are set automatically via the Reactive Network callback.
        </p>
        <div>
          <label className="text-[10px] text-uni-text font-mono mb-1 block">LP / Wallet Address</label>
          <input
            type="text"
            value={lpAddr}
            onChange={e => setLpAddr(e.target.value)}
            placeholder="0x…"
            className="w-full bg-uni-bg border border-uni-border rounded-lg px-3 py-2 text-xs font-mono text-white placeholder-uni-text focus:outline-none focus:border-uni-pink"
          />
        </div>
        <div>
          <label className="text-[10px] text-uni-text font-mono mb-1 block">Tier</label>
          <div className="flex gap-2">
            {(['NONE', 'BRONZE', 'SILVER', 'GOLD'] as const).map((t, i) => (
              <button
                key={t}
                onClick={() => setTierVal(i)}
                className={`flex-1 py-1.5 rounded text-[10px] font-mono border transition-colors ${
                  tierVal === i
                    ? 'border-uni-pink bg-uni-pink/20 text-uni-pink'
                    : 'border-uni-border text-uni-text hover:border-uni-pink/50'
                }`}
              >
                {['⚪','🥉','🥈','🥇'][i]} {t}
              </button>
            ))}
          </div>
        </div>
        <button
          className="btn btn-pink text-xs w-full disabled:opacity-50"
          disabled={status2.type === 'pending'}
          onClick={runSetTier}
        >
          {status2.type === 'pending' ? 'Processing…' : 'Set Tier'}
        </button>
        <StatusBox s={status2} />
      </div>

      {/* Contract addresses */}
      <div className="card border-dashed border-uni-text/30">
        <div className="label mb-2">Deployed Contracts</div>
        <div className="space-y-1.5 text-[10px] font-mono text-uni-text">
          <div className="flex items-center justify-between">
            <span>Hook</span>
            <span className="text-white">{ADDRESSES.UNI.HOOK}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>LoyaltyRegistry</span>
            <span className="text-white">{ADDRESSES.UNI.LOYALTY}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Callback</span>
            <span className="text-white">{ADDRESSES.UNI.CALLBACK}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>RSC (Lasna)</span>
            <span className="text-green-400">{ADDRESSES.REACTIVE.RSC}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

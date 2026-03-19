import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeV4Swap,
  parseUnits, CHAIN_IDS,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'

interface V4SwapProps {
  account: `0x${string}`
  routerApproved: boolean
  onRefresh: () => void
}

export default function V4Swap({ account, routerApproved, onRefresh }: V4SwapProps) {
  // zeroForOne=true: sell TOKEN0 (mWETH), receive TOKEN1 (mUSDC)
  // zeroForOne=false: sell TOKEN1 (mUSDC), receive TOKEN0 (mWETH)
  const [zeroForOne, setZeroForOne] = useState(true)
  const [amountIn, setAmountIn] = useState('1')
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  const inputLabel  = zeroForOne ? 'mWETH (TOKEN0, 18 dec)' : 'mUSDC (TOKEN1, 6 dec)'
  const outputLabel = zeroForOne ? 'mUSDC (TOKEN1, 6 dec)' : 'mWETH (TOKEN0, 18 dec)'
  const inputDecimals = zeroForOne ? 18 : 6

  async function handleSwap() {
    if (!routerApproved) {
      setSteps([{ label: '⚠ Complete Permit2 Setup first', status: 'error' }])
      return
    }
    setRunning(true)

    try {
      const parsed = parseUnits(amountIn, inputDecimals)
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 300)

      setSteps([{ label: `Encoding V4 swap: ${amountIn} ${inputLabel} → ${outputLabel}…`, status: 'pending' }])

      const data = encodeV4Swap({ zeroForOne, amountIn: parsed, recipient: account, deadline })

      const hash = await sendTx(ADDRESSES.UNI.UNIVERSAL_ROUTER, data, account)
      setSteps([{ label: 'Waiting for swap tx…', status: 'pending', hash }])
      await waitForTx(hash)
      setSteps([{ label: `✓ Swap complete: ${amountIn} ${inputLabel} → ${outputLabel}`, status: 'done', hash }])
      onRefresh()
    } catch (err) {
      setSteps([{ label: 'Swap failed', status: 'error', error: err instanceof Error ? err.message : ((err as any)?.message ?? JSON.stringify(err)) }])
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Swap (v4 Universal Router)</div>

      {!routerApproved && (
        <div className="rounded-lg border border-yellow-500/40 bg-yellow-500/10 p-2">
          <p className="text-xs font-mono text-yellow-400">⚠ Complete Permit2 Setup before swapping.</p>
        </div>
      )}

      {/* Direction toggle */}
      <div className="flex rounded-lg border border-uni-border overflow-hidden">
        <button
          className={`flex-1 text-xs font-mono py-2 px-2 transition-colors ${zeroForOne ? 'bg-uni-pink/20 text-uni-pink border-r border-uni-pink/30' : 'text-uni-text hover:text-white'}`}
          onClick={() => setZeroForOne(true)}
        >
          mWETH → mUSDC
          <span className="block text-[9px] opacity-70">TOKEN0 → TOKEN1 (zeroForOne)</span>
        </button>
        <button
          className={`flex-1 text-xs font-mono py-2 px-2 transition-colors ${!zeroForOne ? 'bg-uni-pink/20 text-uni-pink' : 'text-uni-text hover:text-white'}`}
          onClick={() => setZeroForOne(false)}
        >
          mUSDC → mWETH
          <span className="block text-[9px] opacity-70">TOKEN1 → TOKEN0 (oneForZero)</span>
        </button>
      </div>

      <div>
        <label className="text-[10px] text-uni-text font-mono block mb-1">
          Amount In ({inputLabel})
        </label>
        <input
          type="number" min="0" step="0.01" value={amountIn} onChange={e => setAmountIn(e.target.value)}
          className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          placeholder="amount"
        />
      </div>

      <div className="text-[10px] text-uni-text font-mono px-1">
        Swap via UniversalRouter → ArbShieldHook (dynamic fee applies).
        Hook may capture arb fee if price is diverged from Ethereum.
      </div>

      <button
        className="btn btn-pink w-full text-xs disabled:opacity-50"
        disabled={running || !routerApproved}
        onClick={handleSwap}
      >
        {running ? 'Processing…' : `Swap ${inputLabel} → ${outputLabel}`}
      </button>

      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.UNICHAIN} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

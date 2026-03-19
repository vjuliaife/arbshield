import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeApprove, encodeAddLiquidity,
  parseUnits, maxUint256, CHAIN_IDS, ethClient,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'

interface AddLiquidityProps {
  account: `0x${string}`
  allowance0: bigint
  allowance1: bigint
  onRefresh: () => void
}

export default function AddLiquidity({ account, allowance0, allowance1, onRefresh }: AddLiquidityProps) {
  const [amount0, setAmount0] = useState('100')
  const [amount1, setAmount1] = useState('100')
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  async function handleAdd() {
    setRunning(true)
    const parsed0 = parseUnits(amount0, 18)
    const parsed1 = parseUnits(amount1, 18)
    const initialSteps: TxStep[] = []

    if (allowance0 < parsed0) {
      initialSteps.push({ label: 'Approve mWETH → Pool', status: 'idle' })
    }
    if (allowance1 < parsed1) {
      initialSteps.push({ label: 'Approve mUSDC → Pool', status: 'idle' })
    }
    initialSteps.push({ label: `Add liquidity (${amount0} mWETH + ${amount1} mUSDC)`, status: 'idle' })
    setSteps(initialSteps)

    try {
      let stepIdx = 0
      const baseNonce = await ethClient.getTransactionCount({ address: account, blockTag: 'latest' })
      let nonceOffset = 0

      // Approve TOKEN0 if needed
      if (allowance0 < parsed0) {
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'pending'}; return n })
        const h0 = await sendTx(ADDRESSES.ETH.TOKEN0, encodeApprove(ADDRESSES.ETH.POOL, maxUint256), account, '0x' + (baseNonce + nonceOffset).toString(16))
        nonceOffset++
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], hash: h0, label: 'Approve mWETH…'}; return n })
        await waitForTx(h0)
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'done'}; return n })
        stepIdx++
      }

      // Approve TOKEN1 if needed
      if (allowance1 < parsed1) {
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'pending'}; return n })
        const h1 = await sendTx(ADDRESSES.ETH.TOKEN1, encodeApprove(ADDRESSES.ETH.POOL, maxUint256), account, '0x' + (baseNonce + nonceOffset).toString(16))
        nonceOffset++
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], hash: h1, label: 'Approve mUSDC…'}; return n })
        await waitForTx(h1)
        setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'done'}; return n })
        stepIdx++
      }

      // Add liquidity
      setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'pending'}; return n })
      const hLiq = await sendTx(ADDRESSES.ETH.POOL, encodeAddLiquidity(parsed0, parsed1), account, '0x' + (baseNonce + nonceOffset).toString(16))
      setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], hash: hLiq, label: 'Adding liquidity…'}; return n })
      await waitForTx(hLiq)
      setSteps(s => { const n = [...s]; n[stepIdx] = {...n[stepIdx], status: 'done', label: '✓ Liquidity added'}; return n })
      onRefresh()
    } catch (err) {
      setSteps(s => {
        const n = [...s]
        const pendingIdx = n.findIndex(x => x.status === 'pending')
        if (pendingIdx >= 0) n[pendingIdx] = {...n[pendingIdx], status: 'error', error: err instanceof Error ? err.message : ((err as any)?.message ?? JSON.stringify(err))}
        return n
      })
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Add Liquidity</div>
      <div className="flex gap-2">
        <div className="flex-1">
          <label className="text-[10px] text-uni-text font-mono block mb-1">mWETH amount</label>
          <input
            type="number" min="0" value={amount0} onChange={e => setAmount0(e.target.value)}
            className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          />
        </div>
        <div className="flex-1">
          <label className="text-[10px] text-uni-text font-mono block mb-1">mUSDC amount</label>
          <input
            type="number" min="0" value={amount1} onChange={e => setAmount1(e.target.value)}
            className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          />
        </div>
      </div>
      <button
        className="btn btn-pink w-full text-xs disabled:opacity-50"
        disabled={running}
        onClick={handleAdd}
      >
        {running ? 'Processing…' : 'Add Liquidity'}
      </button>
      <p className="text-[10px] text-uni-text font-mono">
        Note: MockV3Pool has no removeLiquidity function — liquidity is one-way on this testnet pool.
      </p>
      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.ETH_SEPOLIA} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

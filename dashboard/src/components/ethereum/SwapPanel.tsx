import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeApprove, encodeV3Swap,
  parseUnits, maxUint256, CHAIN_IDS, ethClient,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'

interface SwapPanelProps {
  account: `0x${string}`
  allowance0: bigint
  allowance1: bigint
  onRefresh: () => void
}

export default function SwapPanel({ account, allowance0, allowance1, onRefresh }: SwapPanelProps) {
  // zeroForOne=true: sell TOKEN0, receive TOKEN1 (price goes down)
  // zeroForOne=false: sell TOKEN1, receive TOKEN0 (price goes up → diverge)
  const [zeroForOne, setZeroForOne] = useState(false)
  const [amountIn, setAmountIn] = useState('1000')
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  const inputToken = zeroForOne ? 'mWETH (TOKEN0)' : 'mUSDC (TOKEN1)'
  const outputToken = zeroForOne ? 'mUSDC (TOKEN1)' : 'mWETH (TOKEN0)'
  const inputAllowance = zeroForOne ? allowance0 : allowance1
  const inputTokenAddr = zeroForOne ? ADDRESSES.ETH.TOKEN0 : ADDRESSES.ETH.TOKEN1

  async function handleSwap() {
    setRunning(true)
    const parsed = parseUnits(amountIn, 18)
    const needApprove = inputAllowance < parsed
    const initialSteps: TxStep[] = []
    if (needApprove) initialSteps.push({ label: `Approve ${inputToken} → Pool`, status: 'idle' })
    initialSteps.push({ label: `Swap ${amountIn} ${inputToken} → ${outputToken}`, status: 'idle' })
    setSteps(initialSteps)

    try {
      let idx = 0
      const baseNonce = await ethClient.getTransactionCount({ address: account, blockTag: 'latest' })
      let nonceOffset = 0

      if (needApprove) {
        setSteps(s => { const n=[...s]; n[idx]={...n[idx],status:'pending'}; return n })
        const ah = await sendTx(inputTokenAddr, encodeApprove(ADDRESSES.ETH.POOL, maxUint256), account, '0x' + (baseNonce + nonceOffset).toString(16))
        nonceOffset++
        setSteps(s => { const n=[...s]; n[idx]={...n[idx],hash:ah,label:'Approving…'}; return n })
        await waitForTx(ah)
        setSteps(s => { const n=[...s]; n[idx]={...n[idx],status:'done'}; return n })
        idx++
      }

      setSteps(s => { const n=[...s]; n[idx]={...n[idx],status:'pending'}; return n })
      const sh = await sendTx(ADDRESSES.ETH.POOL, encodeV3Swap(zeroForOne, parsed, account), account, '0x' + (baseNonce + nonceOffset).toString(16))
      setSteps(s => { const n=[...s]; n[idx]={...n[idx],hash:sh,label:'Swapping…'}; return n })
      await waitForTx(sh)
      setSteps(s => { const n=[...s]; n[idx]={...n[idx],status:'done',label:'✓ Swap complete'}; return n })
      onRefresh()
    } catch (err) {
      setSteps(s => {
        const n=[...s]
        const pi=n.findIndex(x=>x.status==='pending')
        if(pi>=0) n[pi]={...n[pi],status:'error',error:err instanceof Error?err.message:String(err)}
        return n
      })
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Swap</div>

      {/* Direction toggle */}
      <div className="flex rounded-lg border border-uni-border overflow-hidden">
        <button
          className={`flex-1 text-xs font-mono py-2 px-3 transition-colors ${!zeroForOne ? 'bg-uni-pink/20 text-uni-pink border-r border-uni-pink/30' : 'text-uni-text hover:text-white'}`}
          onClick={() => setZeroForOne(false)}
        >
          TOKEN1 → TOKEN0
          <span className="block text-[9px] opacity-70">mUSDC → mWETH (price ↑, diverge)</span>
        </button>
        <button
          className={`flex-1 text-xs font-mono py-2 px-3 transition-colors ${zeroForOne ? 'bg-uni-pink/20 text-uni-pink' : 'text-uni-text hover:text-white'}`}
          onClick={() => setZeroForOne(true)}
        >
          TOKEN0 → TOKEN1
          <span className="block text-[9px] opacity-70">mWETH → mUSDC (price ↓, converge)</span>
        </button>
      </div>

      <div>
        <label className="text-[10px] text-uni-text font-mono block mb-1">
          Amount In ({inputToken})
        </label>
        <input
          type="number" min="0" value={amountIn} onChange={e => setAmountIn(e.target.value)}
          className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          placeholder="amount"
        />
      </div>

      <div className="text-[10px] text-uni-text font-mono px-1">
        {zeroForOne
          ? '→ Sell mWETH for mUSDC. Pool price decreases (converge toward Unichain).'
          : '→ Sell mUSDC for mWETH. Pool price increases (diverge from Unichain). RSC will detect and raise fees.'}
      </div>

      <button
        className="btn btn-pink w-full text-xs disabled:opacity-50"
        disabled={running}
        onClick={handleSwap}
      >
        {running ? 'Processing…' : `Swap ${inputToken} → ${outputToken}`}
      </button>

      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.ETH_SEPOLIA} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeApprove, encodePermit2Approve,
  maxUint256, CHAIN_IDS, unichainClient,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'
import type { Permit2Allowances } from '../../hooks/useUnichainPool'

interface Permit2PanelProps {
  account: `0x${string}`
  erc20Allow0: bigint
  erc20Allow1: bigint
  permit2: Permit2Allowances
  onRefresh: () => void
}

function AllowanceRow({ label, amount }: { label: string; amount: bigint }) {
  const isApproved = amount > 0n
  return (
    <div className="flex items-center justify-between py-1">
      <span className="text-[10px] font-mono text-uni-text">{label}</span>
      <span className={`text-[10px] font-mono font-semibold ${isApproved ? 'text-green-400' : 'text-red-400'}`}>
        {isApproved ? '✓ approved' : '✗ none'}
      </span>
    </div>
  )
}

export default function Permit2Panel({ account, erc20Allow0, erc20Allow1, permit2, onRefresh }: Permit2PanelProps) {
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  const allApproved =
    erc20Allow0 > 0n && erc20Allow1 > 0n &&
    permit2.token0_posMgr > 0n && permit2.token1_posMgr > 0n &&
    permit2.token0_router > 0n && permit2.token1_router > 0n

  async function handleApproveAll() {
    setRunning(true)
    const txSteps: TxStep[] = [
      { label: 'ERC20: mWETH → Permit2',     status: 'idle' },
      { label: 'ERC20: mUSDC → Permit2',     status: 'idle' },
      { label: 'Permit2: mWETH → PosMgr',   status: 'idle' },
      { label: 'Permit2: mUSDC → PosMgr',   status: 'idle' },
      { label: 'Permit2: mWETH → Router',   status: 'idle' },
      { label: 'Permit2: mUSDC → Router',   status: 'idle' },
    ]
    setSteps(txSteps)

    const ops: Array<{ to: `0x${string}`; data: `0x${string}`; label: string }> = [
      { to: ADDRESSES.UNI.TOKEN0, data: encodeApprove(ADDRESSES.UNI.PERMIT2, maxUint256), label: 'ERC20: mWETH → Permit2' },
      { to: ADDRESSES.UNI.TOKEN1, data: encodeApprove(ADDRESSES.UNI.PERMIT2, maxUint256), label: 'ERC20: mUSDC → Permit2' },
      { to: ADDRESSES.UNI.PERMIT2, data: encodePermit2Approve(ADDRESSES.UNI.TOKEN0, ADDRESSES.UNI.POSITION_MGR), label: 'Permit2: mWETH → PosMgr' },
      { to: ADDRESSES.UNI.PERMIT2, data: encodePermit2Approve(ADDRESSES.UNI.TOKEN1, ADDRESSES.UNI.POSITION_MGR), label: 'Permit2: mUSDC → PosMgr' },
      { to: ADDRESSES.UNI.PERMIT2, data: encodePermit2Approve(ADDRESSES.UNI.TOKEN0, ADDRESSES.UNI.UNIVERSAL_ROUTER), label: 'Permit2: mWETH → Router' },
      { to: ADDRESSES.UNI.PERMIT2, data: encodePermit2Approve(ADDRESSES.UNI.TOKEN1, ADDRESSES.UNI.UNIVERSAL_ROUTER), label: 'Permit2: mUSDC → Router' },
    ]

    try {
      const baseNonce = await unichainClient.getTransactionCount({ address: account, blockTag: 'latest' })
      for (let i = 0; i < ops.length; i++) {
        setSteps(s => { const n=[...s]; n[i]={...n[i],status:'pending'}; return n })
        const nonce = '0x' + (baseNonce + i).toString(16)
        const hash = await sendTx(ops[i].to, ops[i].data, account, nonce)
        setSteps(s => { const n=[...s]; n[i]={...n[i],hash,label:ops[i].label+' (waiting…)'}; return n })
        await waitForTx(hash)
        setSteps(s => { const n=[...s]; n[i]={...n[i],status:'done',label:'✓ '+ops[i].label}; return n })
      }
      onRefresh()
    } catch (err) {
      setSteps(s => {
        const n=[...s]
        const pi=n.findIndex(x=>x.status==='pending')
        if(pi>=0) n[pi]={...n[pi],status:'error',error:err instanceof Error?err.message:((err as any)?.message??JSON.stringify(err))}
        return n
      })
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Permit2 Setup</div>
      <p className="text-[10px] text-uni-text font-mono">
        Uniswap v4 uses Permit2 for efficient token approvals.
        Approve all 6 paths before adding liquidity or swapping.
      </p>

      {/* Allowance status */}
      <div className="rounded-lg bg-uni-bg border border-uni-border p-2 divide-y divide-uni-border">
        <AllowanceRow label="mWETH → Permit2 (ERC20)" amount={erc20Allow0} />
        <AllowanceRow label="mUSDC → Permit2 (ERC20)" amount={erc20Allow1} />
        <AllowanceRow label="mWETH → PositionManager (Permit2)" amount={permit2.token0_posMgr} />
        <AllowanceRow label="mUSDC → PositionManager (Permit2)" amount={permit2.token1_posMgr} />
        <AllowanceRow label="mWETH → UniversalRouter (Permit2)" amount={permit2.token0_router} />
        <AllowanceRow label="mUSDC → UniversalRouter (Permit2)" amount={permit2.token1_router} />
      </div>

      {!allApproved && (
        <button
          className="btn btn-pink w-full text-xs disabled:opacity-50"
          disabled={running}
          onClick={handleApproveAll}
        >
          {running ? 'Approving…' : 'Approve All (6 txs)'}
        </button>
      )}
      {allApproved && (
        <p className="text-xs font-mono text-green-400 text-center">✓ All approvals complete</p>
      )}

      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.UNICHAIN} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

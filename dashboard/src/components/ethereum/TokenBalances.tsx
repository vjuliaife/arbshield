import { useState } from 'react'
import { formatUnits } from 'viem'
import { ADDRESSES, sendTx, waitForTx, encodeMint, parseUnits, CHAIN_IDS } from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'

interface TokenBalancesProps {
  account: `0x${string}`
  balance0: bigint
  balance1: bigint
  onRefresh: () => void
}

function useTokenMint(tokenAddress: `0x${string}`, decimals: number) {
  const [amount, setAmount] = useState('1000')
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  async function mint(account: `0x${string}`, onRefresh: () => void) {
    setRunning(true)
    const step: TxStep = { label: `Mint ${amount} tokens`, status: 'pending' }
    setSteps([step])
    try {
      const parsed = parseUnits(amount, decimals)
      const hash = await sendTx(tokenAddress, encodeMint(account, parsed), account)
      setSteps([{ ...step, status: 'pending', hash, label: 'Waiting for tx…' }])
      await waitForTx(hash)
      setSteps([{ label: `✓ Minted ${amount} tokens`, status: 'done', hash }])
      onRefresh()
    } catch (err) {
      setSteps([{ ...step, status: 'error', error: err instanceof Error ? err.message : ((err as any)?.message ?? JSON.stringify(err)) }])
    } finally {
      setRunning(false)
    }
  }

  return { amount, setAmount, steps, running, mint, clearSteps: () => setSteps([]) }
}

export default function TokenBalances({ account, balance0, balance1, onRefresh }: TokenBalancesProps) {
  const t0 = useTokenMint(ADDRESSES.ETH.TOKEN0, 18)
  const t1 = useTokenMint(ADDRESSES.ETH.TOKEN1, 18)

  return (
    <div className="card space-y-4">
      <div className="label">Token Balances & Mint</div>

      {/* TOKEN0 */}
      <div className="rounded-lg border border-uni-border bg-uni-bg p-3 space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs font-mono text-white font-semibold">mWETH (TOKEN0)</span>
          <span className="text-xs font-mono text-uni-text">
            {formatUnits(balance0, 18)} mWETH
          </span>
        </div>
        <div className="flex gap-2">
          <input
            type="number"
            min="1"
            value={t0.amount}
            onChange={e => t0.setAmount(e.target.value)}
            className="flex-1 bg-uni-card border border-uni-border rounded px-2 py-1 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
            placeholder="amount"
          />
          <button
            className="btn btn-pink text-xs px-3 disabled:opacity-50"
            disabled={t0.running}
            onClick={() => t0.mint(account, onRefresh)}
          >
            Mint
          </button>
        </div>
        {t0.steps.length > 0 && (
          <TxFlow steps={t0.steps} chainId={CHAIN_IDS.ETH_SEPOLIA} onClose={t0.clearSteps} />
        )}
      </div>

      {/* TOKEN1 */}
      <div className="rounded-lg border border-uni-border bg-uni-bg p-3 space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs font-mono text-white font-semibold">mUSDC (TOKEN1)</span>
          <span className="text-xs font-mono text-uni-text">
            {formatUnits(balance1, 18)} mUSDC
          </span>
        </div>
        <div className="flex gap-2">
          <input
            type="number"
            min="1"
            value={t1.amount}
            onChange={e => t1.setAmount(e.target.value)}
            className="flex-1 bg-uni-card border border-uni-border rounded px-2 py-1 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
            placeholder="amount"
          />
          <button
            className="btn btn-pink text-xs px-3 disabled:opacity-50"
            disabled={t1.running}
            onClick={() => t1.mint(account, onRefresh)}
          >
            Mint
          </button>
        </div>
        {t1.steps.length > 0 && (
          <TxFlow steps={t1.steps} chainId={CHAIN_IDS.ETH_SEPOLIA} onClose={t1.clearSteps} />
        )}
      </div>
    </div>
  )
}

import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeV4MintPosition,
  parseUnits, getLiquidityForAmounts, CHAIN_IDS,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'

interface V4AddLiquidityProps {
  account: `0x${string}`
  sqrtPriceX96: bigint
  permit2Approved: boolean
  onRefresh: () => void
}

const DEFAULT_TICK_LOWER = -600
const DEFAULT_TICK_UPPER = 600

export default function V4AddLiquidity({ account, sqrtPriceX96, permit2Approved, onRefresh }: V4AddLiquidityProps) {
  const [tickLower, setTickLower] = useState(DEFAULT_TICK_LOWER.toString())
  const [tickUpper, setTickUpper] = useState(DEFAULT_TICK_UPPER.toString())
  const [amount0, setAmount0] = useState('10')
  const [amount1, setAmount1] = useState('10')
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)

  const tl = parseInt(tickLower) || DEFAULT_TICK_LOWER
  const tu = parseInt(tickUpper) || DEFAULT_TICK_UPPER

  function setRangeFromCurrent() {
    if (sqrtPriceX96 > 0n) {
      // Approximate current tick from sqrtPriceX96 (floating point OK for UI)
      const Q96f = 2 ** 96
      const ratio = Number(sqrtPriceX96) / Q96f
      const rawPrice = ratio * ratio  // raw price, no decimal adjustment (matches RSC)
      const approxTick = rawPrice > 0 ? Math.round(Math.log(rawPrice) / Math.log(1.0001)) : 0
      const spacings = 600  // ±10 × 60
      setTickLower(String(Math.floor((approxTick - spacings) / 60) * 60))
      setTickUpper(String(Math.ceil((approxTick + spacings) / 60) * 60))
    } else {
      setTickLower(DEFAULT_TICK_LOWER.toString())
      setTickUpper(DEFAULT_TICK_UPPER.toString())
    }
  }

  async function handleMint() {
    if (!permit2Approved) {
      setSteps([{ label: '⚠ Complete Permit2 Setup first', status: 'error' }])
      return
    }

    setRunning(true)
    setSteps([{ label: 'Computing liquidity…', status: 'pending' }])

    try {
      const parsed0 = parseUnits(amount0, 18)
      const parsed1 = parseUnits(amount1, 6) // mUSDC has 6 decimals on Unichain

      const liquidity = getLiquidityForAmounts(
        sqrtPriceX96 || BigInt('79228162514264337593543950336'), // default to 1:1
        tl, tu,
        parsed0, parsed1
      )

      if (liquidity === 0n) {
        setSteps([{ label: '✗ Computed liquidity is 0. Check tick range and amounts.', status: 'error' }])
        setRunning(false)
        return
      }

      const deadline = BigInt(Math.floor(Date.now() / 1000) + 300)
      const amount0Max = parsed0 + (parsed0 / 100n)  // +1% slippage
      const amount1Max = parsed1 + (parsed1 / 100n)

      setSteps([{
        label: `Mint position: ticks [${tl}, ${tu}], liquidity ${liquidity.toString().slice(0,12)}…`,
        status: 'pending',
      }])

      const data = encodeV4MintPosition({
        tickLower: tl,
        tickUpper: tu,
        liquidity,
        amount0Max,
        amount1Max,
        recipient: account,
        deadline,
      })

      const hash = await sendTx(ADDRESSES.UNI.POSITION_MGR, data, account)
      setSteps([{ label: 'Waiting for tx…', status: 'pending', hash }])
      await waitForTx(hash)
      setSteps([{ label: '✓ Position minted! Check Remove Liquidity panel for your NFT.', status: 'done', hash }])
      onRefresh()
    } catch (err) {
      setSteps([{ label: 'Mint failed', status: 'error', error: err instanceof Error ? err.message : ((err as any)?.message ?? JSON.stringify(err)) }])
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Add Liquidity (v4)</div>

      {!permit2Approved && (
        <div className="rounded-lg border border-yellow-500/40 bg-yellow-500/10 p-2">
          <p className="text-xs font-mono text-yellow-400">⚠ Complete Permit2 Setup above before adding liquidity.</p>
        </div>
      )}

      {/* Tick range */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[10px] text-uni-text font-mono">Tick Range</span>
          <button
            className="text-[10px] font-mono text-uni-pink hover:underline"
            onClick={setRangeFromCurrent}
          >
            ±10 from current
          </button>
        </div>
        <div className="flex gap-2">
          <div className="flex-1">
            <label className="text-[9px] text-uni-text font-mono block mb-0.5">tickLower</label>
            <input
              type="number" value={tickLower} onChange={e => setTickLower(e.target.value)}
              className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
            />
          </div>
          <div className="flex-1">
            <label className="text-[9px] text-uni-text font-mono block mb-0.5">tickUpper</label>
            <input
              type="number" value={tickUpper} onChange={e => setTickUpper(e.target.value)}
              className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
            />
          </div>
        </div>
        <p className="text-[9px] text-uni-text font-mono">Must be multiples of 60 (tick spacing)</p>
      </div>

      {/* Amounts */}
      <div className="flex gap-2">
        <div className="flex-1">
          <label className="text-[10px] text-uni-text font-mono block mb-1">mWETH (18 dec)</label>
          <input
            type="number" min="0" value={amount0} onChange={e => setAmount0(e.target.value)}
            className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          />
        </div>
        <div className="flex-1">
          <label className="text-[10px] text-uni-text font-mono block mb-1">mUSDC (6 dec)</label>
          <input
            type="number" min="0" value={amount1} onChange={e => setAmount1(e.target.value)}
            className="w-full bg-uni-bg border border-uni-border rounded px-2 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-uni-pink"
          />
        </div>
      </div>

      <button
        className="btn btn-pink w-full text-xs disabled:opacity-50"
        disabled={running || !permit2Approved}
        onClick={handleMint}
      >
        {running ? 'Processing…' : 'Mint Position'}
      </button>

      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.UNICHAIN} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

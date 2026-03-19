import { useState } from 'react'
import { formatUnits } from 'viem'
import {
  ADDRESSES, POSITION_MGR_ABI, POOL_KEY, INIT_SQRT_PRICE_X96,
  sendTx, waitForTx, encodeFunctionData, encodeMint, parseUnits,
} from '../../constants'

interface V4BalancesProps {
  balance0:      bigint
  balance1:      bigint
  sqrtPriceX96:  bigint
  tick:          number
  totalLiquidity: bigint
  account:       `0x${string}` | null
  onRefresh:     () => void
}

// Convert sqrtPriceX96 to raw price (token1/token0 in contract units)
function toHumanPrice(sqrtP: bigint): string {
  if (sqrtP === 0n) return '—'
  // Use BigInt arithmetic to avoid precision loss for large values
  const Q192 = 2n ** 192n
  const rawPriceNum = sqrtP * sqrtP
  const whole = rawPriceNum / Q192
  const frac = (rawPriceNum * 1_000_000n) / Q192 - whole * 1_000_000n
  return `${whole}.${frac.toString().padStart(6, '0')}`
}

type MintStatus = 'idle' | 'pending' | 'done' | 'error'

export default function V4Balances({ balance0, balance1, sqrtPriceX96, tick, totalLiquidity, account, onRefresh }: V4BalancesProps) {
  const [initStatus, setInitStatus] = useState<'idle' | 'pending' | 'done' | 'error'>('idle')
  const [initMsg,    setInitMsg]    = useState('')

  const [mint0Status, setMint0Status] = useState<MintStatus>('idle')
  const [mint0Msg,    setMint0Msg]    = useState('')
  const [mint1Status, setMint1Status] = useState<MintStatus>('idle')
  const [mint1Msg,    setMint1Msg]    = useState('')

  const poolNotInit = sqrtPriceX96 === 0n
  const needsTokens = balance0 < parseUnits('1', 18) || balance1 < parseUnits('1', 6)

  async function initPool() {
    if (!account) return
    setInitStatus('pending')
    setInitMsg('Sending initialize transaction…')
    try {
      const data = encodeFunctionData({
        abi: POSITION_MGR_ABI,
        functionName: 'initializePool',
        args: [
          {
            currency0:   POOL_KEY.currency0,
            currency1:   POOL_KEY.currency1,
            fee:         POOL_KEY.fee,
            tickSpacing: POOL_KEY.tickSpacing,
            hooks:       POOL_KEY.hooks,
          },
          INIT_SQRT_PRICE_X96,
        ],
      })
      const hash = await sendTx(ADDRESSES.UNI.POSITION_MGR, data, account)
      setInitMsg(`Waiting for confirmation… (${hash.slice(0, 10)}…)`)
      await waitForTx(hash)
      setInitStatus('done')
      setInitMsg(`Pool initialized! tx: ${hash.slice(0, 18)}…`)
      onRefresh()
    } catch (e) {
      setInitStatus('error')
      setInitMsg(e instanceof Error ? e.message : 'Init failed')
    }
  }

  async function mintToken0() {
    if (!account) return
    setMint0Status('pending')
    setMint0Msg('Minting 1000 mWETH…')
    try {
      const data = encodeMint(account, parseUnits('1000', 18))
      const hash = await sendTx(ADDRESSES.UNI.TOKEN0, data, account)
      setMint0Msg(`Waiting… (${hash.slice(0, 10)}…)`)
      await waitForTx(hash)
      setMint0Status('done')
      setMint0Msg('✓ 1000 mWETH minted!')
      onRefresh()
    } catch (e) {
      setMint0Status('error')
      setMint0Msg(e instanceof Error ? e.message : 'Mint failed')
    }
  }

  async function mintToken1() {
    if (!account) return
    setMint1Status('pending')
    setMint1Msg('Minting 1000 mUSDC…')
    try {
      const data = encodeMint(account, parseUnits('1000', 6))
      const hash = await sendTx(ADDRESSES.UNI.TOKEN1, data, account)
      setMint1Msg(`Waiting… (${hash.slice(0, 10)}…)`)
      await waitForTx(hash)
      setMint1Status('done')
      setMint1Msg('✓ 1000 mUSDC minted!')
      onRefresh()
    } catch (e) {
      setMint1Status('error')
      setMint1Msg(e instanceof Error ? e.message : 'Mint failed')
    }
  }

  function statusColor(s: MintStatus) {
    if (s === 'error') return 'text-red-400'
    if (s === 'done')  return 'text-green-400'
    return 'text-blue-400'
  }

  return (
    <div className="card space-y-3">
      <div className="label">Balances & Pool State</div>

      {/* Wallet balances */}
      <div className="grid grid-cols-2 gap-3">
        <div className="rounded-lg bg-uni-bg border border-uni-border p-2">
          <div className="text-[10px] text-uni-text font-mono mb-0.5">mWETH Balance</div>
          <div className="text-sm font-mono font-bold text-white">
            {parseFloat(formatUnits(balance0, 18)).toFixed(4)}
          </div>
          <div className="text-[9px] text-uni-text font-mono truncate">{ADDRESSES.UNI.TOKEN0.slice(0,10)}…</div>
        </div>
        <div className="rounded-lg bg-uni-bg border border-uni-border p-2">
          <div className="text-[10px] text-uni-text font-mono mb-0.5">mUSDC Balance</div>
          <div className="text-sm font-mono font-bold text-white">
            {parseFloat(formatUnits(balance1, 6)).toFixed(4)}
          </div>
          <div className="text-[9px] text-uni-text font-mono truncate">{ADDRESSES.UNI.TOKEN1.slice(0,10)}…</div>
        </div>
      </div>

      {/* Mint test tokens — shown when balance is low */}
      {needsTokens && account && (
        <div className="rounded-lg border border-blue-500/30 bg-blue-500/5 p-3 space-y-2">
          <div className="text-[10px] text-blue-400 font-mono font-semibold uppercase tracking-wider">
            Mint Test Tokens
          </div>
          <p className="text-[9px] text-uni-text font-mono">
            These are free testnet tokens. Mint before adding liquidity.
          </p>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <button
                onClick={mintToken0}
                disabled={mint0Status === 'pending' || mint0Status === 'done'}
                className="btn btn-pink text-[10px] w-full disabled:opacity-50"
              >
                {mint0Status === 'pending' ? 'Minting…' : mint0Status === 'done' ? '✓ Minted' : 'Mint 1000 mWETH'}
              </button>
              {mint0Msg && (
                <p className={`text-[9px] font-mono ${statusColor(mint0Status)}`}>{mint0Msg}</p>
              )}
            </div>
            <div className="space-y-1">
              <button
                onClick={mintToken1}
                disabled={mint1Status === 'pending' || mint1Status === 'done'}
                className="btn btn-pink text-[10px] w-full disabled:opacity-50"
              >
                {mint1Status === 'pending' ? 'Minting…' : mint1Status === 'done' ? '✓ Minted' : 'Mint 1000 mUSDC'}
              </button>
              {mint1Msg && (
                <p className={`text-[9px] font-mono ${statusColor(mint1Status)}`}>{mint1Msg}</p>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Pool state */}
      <div className="rounded-lg bg-uni-bg border border-uni-border p-3 space-y-2">
        <div className="text-[10px] text-uni-text font-mono font-semibold uppercase tracking-wider">ArbShield Pool (v4)</div>
        <div className="grid grid-cols-3 gap-2">
          <div>
            <div className="text-[9px] text-uni-text font-mono">Raw Price (token1/token0)</div>
            <div className="text-xs font-mono font-bold text-white">{toHumanPrice(sqrtPriceX96)}</div>
          </div>
          <div>
            <div className="text-[9px] text-uni-text font-mono">Current Tick</div>
            <div className="text-xs font-mono font-bold text-white">{tick}</div>
          </div>
          <div>
            <div className="text-[9px] text-uni-text font-mono">Total Liquidity</div>
            <div className="text-xs font-mono font-bold text-white">
              {totalLiquidity > 0n ? totalLiquidity.toString().slice(0, 12) + '…' : '0'}
            </div>
          </div>
        </div>
        <div className="text-[9px] text-uni-text font-mono">
          sqrtPriceX96: {sqrtPriceX96 > 0n ? sqrtPriceX96.toString().slice(0, 16) + '…' : '—'}
        </div>
      </div>

      {/* Initialize pool CTA — only shown when pool is not initialized */}
      {poolNotInit && (
        <div className="rounded-lg border border-yellow-500/40 bg-yellow-500/5 p-3 space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-yellow-400 text-sm">⚠</span>
            <span className="text-xs font-mono text-yellow-400 font-semibold">Pool not initialized</span>
          </div>
          <p className="text-[10px] text-uni-text font-mono">
            The v4 ArbShield pool has no starting price. Initialize it before adding liquidity or swapping.
            Starting price: 1 mWETH = 1 mUSDC (tick 0).
          </p>
          <button
            onClick={initPool}
            disabled={!account || initStatus === 'pending' || initStatus === 'done'}
            className="btn btn-pink text-xs w-full disabled:opacity-50"
          >
            {initStatus === 'pending' ? 'Initializing…' : initStatus === 'done' ? '✓ Initialized' : 'Initialize Pool'}
          </button>
          {initMsg && (
            <p className={`text-[10px] font-mono ${initStatus === 'error' ? 'text-red-400' : initStatus === 'done' ? 'text-green-400' : 'text-blue-400'}`}>
              {initMsg}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

import { useState } from 'react'
import {
  ADDRESSES, sendTx, waitForTx, encodeV4BurnPosition, CHAIN_IDS,
} from '../../constants'
import TxFlow, { type TxStep } from '../TxFlow'
import type { PositionData } from '../../hooks/useUnichainPool'

interface V4RemoveLiquidityProps {
  account: `0x${string}`
  positions: PositionData[]
  onRefresh: () => void
}

export default function V4RemoveLiquidity({ account, positions, onRefresh }: V4RemoveLiquidityProps) {
  const [steps, setSteps] = useState<TxStep[]>([])
  const [running, setRunning] = useState(false)
  const [selectedId, setSelectedId] = useState<bigint | null>(null)

  async function handleBurn(tokenId: bigint) {
    setSelectedId(tokenId)
    setRunning(true)
    setSteps([{ label: `Burning position #${tokenId}…`, status: 'pending' }])

    try {
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 300)
      const data = encodeV4BurnPosition({ tokenId, recipient: account, deadline })
      const hash = await sendTx(ADDRESSES.UNI.POSITION_MGR, data, account)
      setSteps([{ label: 'Waiting for tx…', status: 'pending', hash }])
      await waitForTx(hash)
      setSteps([{ label: `✓ Position #${tokenId} burned. Tokens returned.`, status: 'done', hash }])
      onRefresh()
    } catch (err) {
      setSteps([{ label: 'Burn failed', status: 'error', error: err instanceof Error ? err.message : ((err as any)?.message ?? JSON.stringify(err)) }])
    } finally {
      setRunning(false)
      setSelectedId(null)
    }
  }

  return (
    <div className="card space-y-3">
      <div className="label">Remove Liquidity (v4)</div>

      {positions.length === 0 ? (
        <p className="text-xs text-uni-text font-mono py-2">
          No positions found. Mint a position first using the Add Liquidity panel.
        </p>
      ) : (
        <div className="space-y-2">
          {positions.map(pos => (
            <div
              key={pos.tokenId.toString()}
              className="rounded-lg border border-uni-border bg-uni-bg p-3 space-y-2"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-mono font-bold text-white">
                  Position NFT #{pos.tokenId.toString()}
                </span>
                <span className="text-[10px] font-mono text-uni-text">
                  [{pos.tickLower}, {pos.tickUpper}]
                </span>
              </div>
              <div className="text-[9px] font-mono text-uni-text">
                PositionInfo: {pos.infoRaw.slice(0, 14)}…
              </div>
              <button
                className="btn btn-outline text-xs w-full disabled:opacity-50"
                disabled={running}
                onClick={() => handleBurn(pos.tokenId)}
              >
                {running && selectedId === pos.tokenId
                  ? 'Processing…'
                  : `Burn Position #${pos.tokenId} (remove all liquidity)`}
              </button>
            </div>
          ))}
        </div>
      )}

      {steps.length > 0 && (
        <TxFlow steps={steps} chainId={CHAIN_IDS.UNICHAIN} onClose={() => setSteps([])} />
      )}
    </div>
  )
}

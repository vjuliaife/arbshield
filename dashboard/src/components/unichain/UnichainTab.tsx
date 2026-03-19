import { useEffect } from 'react'
import { useUnichainPool } from '../../hooks/useUnichainPool'
import { CHAIN_IDS } from '../../constants'
import V4Balances from './V4Balances'
import Permit2Panel from './Permit2Panel'
import V4AddLiquidity from './V4AddLiquidity'
import V4RemoveLiquidity from './V4RemoveLiquidity'
import V4Swap from './V4Swap'

interface UnichainTabProps {
  account: `0x${string}` | null
  chainId: number | null
  onSwitchUni: () => void
}

export default function UnichainTab({ account, chainId, onSwitchUni }: UnichainTabProps) {
  const pool = useUnichainPool(account)

  useEffect(() => {
    pool.refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, chainId])

  const wrongChain = account !== null && chainId !== CHAIN_IDS.UNICHAIN

  if (!account) {
    return (
      <div className="p-8 text-center">
        <p className="text-uni-text font-mono text-sm">Connect your wallet to use the Unichain Pool.</p>
      </div>
    )
  }

  if (wrongChain) {
    return (
      <div className="p-8 text-center space-y-3">
        <p className="text-yellow-400 font-mono text-sm">Wrong network. Switch to Unichain Sepolia.</p>
        <button className="btn btn-pink text-xs" onClick={onSwitchUni}>Switch to Unichain Sepolia</button>
      </div>
    )
  }

  const permit2Approved =
    pool.permit2.token0_posMgr > 0n && pool.permit2.token1_posMgr > 0n &&
    pool.erc20_allow0_permit2 > 0n && pool.erc20_allow1_permit2 > 0n

  const routerApproved =
    pool.permit2.token0_router > 0n && pool.permit2.token1_router > 0n &&
    pool.erc20_allow0_permit2 > 0n && pool.erc20_allow1_permit2 > 0n

  return (
    <div className="p-4 space-y-4">
      {/* Header bar */}
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-mono text-uni-text">
          Unichain Sepolia · {account.slice(0,8)}…{account.slice(-6)}
        </span>
        <button
          className="text-[10px] font-mono text-uni-text hover:text-white border border-uni-border rounded px-2 py-0.5"
          onClick={pool.refresh}
          disabled={pool.loading}
        >
          {pool.loading ? 'Refreshing…' : '↺ Refresh'}
        </button>
      </div>

      {pool.error && (
        <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-2">
          <p className="text-xs font-mono text-red-400">{pool.error}</p>
        </div>
      )}

      {/* Layout: 2 columns on large screens */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Left column */}
        <div className="space-y-4">
          <V4Balances
            balance0={pool.balance0}
            balance1={pool.balance1}
            sqrtPriceX96={pool.sqrtPriceX96}
            tick={pool.tick}
            totalLiquidity={pool.totalLiquidity}
            account={account}
            onRefresh={pool.refresh}
          />
          <Permit2Panel
            account={account}
            erc20Allow0={pool.erc20_allow0_permit2}
            erc20Allow1={pool.erc20_allow1_permit2}
            permit2={pool.permit2}
            onRefresh={pool.refresh}
          />
        </div>

        {/* Right column */}
        <div className="space-y-4">
          <V4AddLiquidity
            account={account}
            sqrtPriceX96={pool.sqrtPriceX96}
            permit2Approved={permit2Approved}
            onRefresh={pool.refresh}
          />
          <V4RemoveLiquidity
            account={account}
            positions={pool.positions}
            onRefresh={pool.refresh}
          />
          <V4Swap
            account={account}
            routerApproved={routerApproved}
            onRefresh={pool.refresh}
          />
        </div>
      </div>
    </div>
  )
}

import { useEffect } from 'react'
import { useEthPool } from '../../hooks/useEthPool'
import { CHAIN_IDS } from '../../constants'
import TokenBalances from './TokenBalances'
import PoolReserves from './PoolReserves'
import AddLiquidity from './AddLiquidity'
import SwapPanel from './SwapPanel'

interface EthereumTabProps {
  account: `0x${string}` | null
  chainId: number | null
  onSwitchEth: () => void
}

export default function EthereumTab({ account, chainId, onSwitchEth }: EthereumTabProps) {
  const pool = useEthPool(account)

  useEffect(() => {
    pool.refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, chainId])

  const wrongChain = account !== null && chainId !== CHAIN_IDS.ETH_SEPOLIA

  if (!account) {
    return (
      <div className="p-8 text-center">
        <p className="text-uni-text font-mono text-sm">Connect your wallet to use the Ethereum Pool.</p>
      </div>
    )
  }

  if (wrongChain) {
    return (
      <div className="p-8 text-center space-y-3">
        <p className="text-yellow-400 font-mono text-sm">Wrong network. Switch to Ethereum Sepolia.</p>
        <button className="btn btn-pink text-xs" onClick={onSwitchEth}>Switch to Ethereum Sepolia</button>
      </div>
    )
  }

  return (
    <div className="p-4 space-y-4">
      {/* Address + refresh bar */}
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-mono text-uni-text">
          Ethereum Sepolia · {account.slice(0,8)}…{account.slice(-6)}
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

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="space-y-4">
          <TokenBalances
            account={account}
            balance0={pool.balance0}
            balance1={pool.balance1}
            onRefresh={pool.refresh}
          />
          <PoolReserves
            reserve0={pool.reserve0}
            reserve1={pool.reserve1}
            ethPrice={pool.ethPrice}
          />
        </div>
        <div className="space-y-4">
          <AddLiquidity
            account={account}
            allowance0={pool.allowance0}
            allowance1={pool.allowance1}
            onRefresh={pool.refresh}
          />
          <SwapPanel
            account={account}
            allowance0={pool.allowance0}
            allowance1={pool.allowance1}
            onRefresh={pool.refresh}
          />
        </div>
      </div>
    </div>
  )
}

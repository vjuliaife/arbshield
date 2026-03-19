import { useState, useCallback } from 'react'
import { ethClient, ADDRESSES, ERC20_ABI, POOL_ABI } from '../constants'

export interface EthPoolState {
  balance0: bigint
  balance1: bigint
  allowance0: bigint  // account → pool
  allowance1: bigint
  reserve0: bigint
  reserve1: bigint
  ethPrice: bigint
  loading: boolean
  error: string | null
}

const DEFAULT: EthPoolState = {
  balance0: 0n, balance1: 0n,
  allowance0: 0n, allowance1: 0n,
  reserve0: 0n, reserve1: 0n,
  ethPrice: 0n,
  loading: false, error: null,
}

export function useEthPool(account: `0x${string}` | null) {
  const [state, setState] = useState<EthPoolState>(DEFAULT)

  const refresh = useCallback(async () => {
    if (!account) return
    setState(prev => ({ ...prev, loading: true, error: null }))
    try {
      const [bal0, bal1, all0, all1, res0, res1, price] = await Promise.all([
        ethClient.readContract({ address: ADDRESSES.ETH.TOKEN0, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] }),
        ethClient.readContract({ address: ADDRESSES.ETH.TOKEN1, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] }),
        ethClient.readContract({ address: ADDRESSES.ETH.TOKEN0, abi: ERC20_ABI, functionName: 'allowance', args: [account, ADDRESSES.ETH.POOL] }),
        ethClient.readContract({ address: ADDRESSES.ETH.TOKEN1, abi: ERC20_ABI, functionName: 'allowance', args: [account, ADDRESSES.ETH.POOL] }),
        ethClient.readContract({ address: ADDRESSES.ETH.POOL, abi: POOL_ABI, functionName: 'reserve0' }),
        ethClient.readContract({ address: ADDRESSES.ETH.POOL, abi: POOL_ABI, functionName: 'reserve1' }),
        ethClient.readContract({ address: ADDRESSES.ETH.POOL, abi: POOL_ABI, functionName: 'getPrice' }),
      ])
      setState({
        balance0: bal0,
        balance1: bal1,
        allowance0: all0,
        allowance1: all1,
        reserve0: res0,
        reserve1: res1,
        ethPrice: price,
        loading: false,
        error: null,
      })
    } catch (err) {
      setState(prev => ({
        ...prev,
        loading: false,
        error: err instanceof Error ? err.message : String(err),
      }))
    }
  }, [account])

  return { ...state, refresh }
}

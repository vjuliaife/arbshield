import { useState, useCallback } from 'react'
import {
  unichainClient,
  ADDRESSES, ERC20_ABI, PERMIT2_ABI, POOL_MANAGER_ABI, POSITION_MGR_ABI,
  POOL_STATE_SLOT, POOL_LIQUIDITY_SLOT, parseSlot0,
} from '../constants'

export interface PositionData {
  tokenId: bigint
  tickLower: number
  tickUpper: number
  infoRaw: `0x${string}`
}

export interface Permit2Allowances {
  token0_posMgr: bigint
  token1_posMgr: bigint
  token0_router: bigint
  token1_router: bigint
}

export interface UnichainPoolState {
  balance0: bigint
  balance1: bigint
  sqrtPriceX96: bigint
  tick: number
  totalLiquidity: bigint
  erc20_allow0_permit2: bigint
  erc20_allow1_permit2: bigint
  permit2: Permit2Allowances
  positions: PositionData[]
  loading: boolean
  error: string | null
}

const DEFAULT: UnichainPoolState = {
  balance0: 0n, balance1: 0n,
  sqrtPriceX96: 0n, tick: 0, totalLiquidity: 0n,
  erc20_allow0_permit2: 0n, erc20_allow1_permit2: 0n,
  permit2: { token0_posMgr: 0n, token1_posMgr: 0n, token0_router: 0n, token1_router: 0n },
  positions: [],
  loading: false, error: null,
}

export function useUnichainPool(account: `0x${string}` | null) {
  const [state, setState] = useState<UnichainPoolState>(DEFAULT)

  const refresh = useCallback(async () => {
    if (!account) {
      // Still fetch pool-level data without account; pool may not be initialized yet
      try {
        const [slot0Raw, liqRaw] = await Promise.all([
          unichainClient.readContract({
            address: ADDRESSES.UNI.POOL_MANAGER, abi: POOL_MANAGER_ABI,
            functionName: 'extsload', args: [POOL_STATE_SLOT],
          }).catch(() => '0x' + '0'.repeat(64) as `0x${string}`),
          unichainClient.readContract({
            address: ADDRESSES.UNI.POOL_MANAGER, abi: POOL_MANAGER_ABI,
            functionName: 'extsload', args: [POOL_LIQUIDITY_SLOT],
          }).catch(() => '0x' + '0'.repeat(64) as `0x${string}`),
        ])
        const { sqrtPriceX96, tick } = parseSlot0(slot0Raw as `0x${string}`)
        const totalLiquidity = BigInt(liqRaw as string) & ((1n << 128n) - 1n)
        setState(prev => ({ ...prev, sqrtPriceX96, tick, totalLiquidity }))
      } catch { /* ignore */ }
      return
    }

    setState(prev => ({ ...prev, loading: true, error: null }))
    try {
      // Parallel reads: balances, allowances, pool state
      const [
        bal0, bal1,
        erc20all0, erc20all1,
        p2all0posMgr, p2all1posMgr,
        p2all0router, p2all1router,
        slot0Raw, liq,
        nextTokenId,
      ] = await Promise.all([
        unichainClient.readContract({ address: ADDRESSES.UNI.TOKEN0, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] }),
        unichainClient.readContract({ address: ADDRESSES.UNI.TOKEN1, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] }),
        // ERC20 → Permit2 allowances
        unichainClient.readContract({ address: ADDRESSES.UNI.TOKEN0, abi: ERC20_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.PERMIT2] }),
        unichainClient.readContract({ address: ADDRESSES.UNI.TOKEN1, abi: ERC20_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.PERMIT2] }),
        // Permit2 → PositionManager
        unichainClient.readContract({ address: ADDRESSES.UNI.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.TOKEN0, ADDRESSES.UNI.POSITION_MGR] }),
        unichainClient.readContract({ address: ADDRESSES.UNI.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.TOKEN1, ADDRESSES.UNI.POSITION_MGR] }),
        // Permit2 → Universal Router
        unichainClient.readContract({ address: ADDRESSES.UNI.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.TOKEN0, ADDRESSES.UNI.UNIVERSAL_ROUTER] }),
        unichainClient.readContract({ address: ADDRESSES.UNI.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance', args: [account, ADDRESSES.UNI.TOKEN1, ADDRESSES.UNI.UNIVERSAL_ROUTER] }),
        // Pool state via extsload (StateLibrary pattern — PoolManager has no getSlot0/getLiquidity)
        unichainClient.readContract({ address: ADDRESSES.UNI.POOL_MANAGER, abi: POOL_MANAGER_ABI, functionName: 'extsload', args: [POOL_STATE_SLOT] })
          .catch(() => '0x' + '0'.repeat(64) as `0x${string}`),
        unichainClient.readContract({ address: ADDRESSES.UNI.POOL_MANAGER, abi: POOL_MANAGER_ABI, functionName: 'extsload', args: [POOL_LIQUIDITY_SLOT] })
          .catch(() => '0x' + '0'.repeat(64) as `0x${string}`),
        // PositionManager
        unichainClient.readContract({ address: ADDRESSES.UNI.POSITION_MGR, abi: POSITION_MGR_ABI, functionName: 'nextTokenId' }),
      ])

      const { sqrtPriceX96, tick } = parseSlot0(slot0Raw as `0x${string}`)
      const totalLiquidity = BigInt(liq as string) & ((1n << 128n) - 1n)
      const [p2amt0pos] = p2all0posMgr as [bigint, number, number]
      const [p2amt1pos] = p2all1posMgr as [bigint, number, number]
      const [p2amt0rtr] = p2all0router as [bigint, number, number]
      const [p2amt1rtr] = p2all1router as [bigint, number, number]

      // Scan positions owned by account (scan tokenId 1..nextTokenId-1)
      // Uses Promise.allSettled instead of multicall3 (not deployed on Unichain Sepolia)
      const maxId = Number(nextTokenId) - 1
      const positions: PositionData[] = []
      if (maxId >= 1) {
        const scanIds = Array.from({ length: Math.min(maxId, 50) }, (_, i) => BigInt(i + 1))
        const ownerResults = await Promise.allSettled(
          scanIds.map(id =>
            unichainClient.readContract({
              address: ADDRESSES.UNI.POSITION_MGR,
              abi: POSITION_MGR_ABI,
              functionName: 'ownerOf',
              args: [id],
            })
          )
        )

        const ownedIds = scanIds.filter(
          (_, i) => ownerResults[i].status === 'fulfilled' &&
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            String((ownerResults[i] as PromiseFulfilledResult<any>).value).toLowerCase() === account.toLowerCase()
        )

        if (ownedIds.length > 0) {
          const infoResults = await Promise.allSettled(
            ownedIds.map(id =>
              unichainClient.readContract({
                address: ADDRESSES.UNI.POSITION_MGR,
                abi: POSITION_MGR_ABI,
                functionName: 'positionInfo',
                args: [id],
              })
            )
          )

          for (let i = 0; i < ownedIds.length; i++) {
            if (infoResults[i].status === 'fulfilled') {
              const infoRaw = (infoResults[i] as PromiseFulfilledResult<unknown>).value as `0x${string}`
              const infoBig = BigInt(infoRaw)
              const tickLower = Number(BigInt.asIntN(24, infoBig >> 232n))
              const tickUpper = Number(BigInt.asIntN(24, infoBig >> 208n))
              positions.push({ tokenId: ownedIds[i], tickLower, tickUpper, infoRaw })
            }
          }
        }
      }

      setState({
        balance0: bal0,
        balance1: bal1,
        sqrtPriceX96,
        tick,
        totalLiquidity,
        erc20_allow0_permit2: erc20all0,
        erc20_allow1_permit2: erc20all1,
        permit2: {
          token0_posMgr: p2amt0pos,
          token1_posMgr: p2amt1pos,
          token0_router: p2amt0rtr,
          token1_router: p2amt1rtr,
        },
        positions,
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

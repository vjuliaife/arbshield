import { formatUnits } from 'viem'

interface PoolReservesProps {
  reserve0: bigint
  reserve1: bigint
  ethPrice: bigint
}

export default function PoolReserves({ reserve0, reserve1, ethPrice }: PoolReservesProps) {
  return (
    <div className="card space-y-3">
      <div className="label">Pool Reserves</div>
      <div className="grid grid-cols-3 gap-3">
        <div className="rounded-lg bg-uni-bg border border-uni-border p-2 text-center">
          <div className="text-[10px] text-uni-text font-mono mb-0.5">reserve0 (mWETH)</div>
          <div className="text-sm font-mono font-bold text-white">
            {parseFloat(formatUnits(reserve0, 18)).toFixed(4)}
          </div>
        </div>
        <div className="rounded-lg bg-uni-bg border border-uni-border p-2 text-center">
          <div className="text-[10px] text-uni-text font-mono mb-0.5">reserve1 (mUSDC)</div>
          <div className="text-sm font-mono font-bold text-white">
            {parseFloat(formatUnits(reserve1, 18)).toFixed(4)}
          </div>
        </div>
        <div className="rounded-lg bg-uni-bg border border-uni-border p-2 text-center">
          <div className="text-[10px] text-uni-text font-mono mb-0.5">price (r1/r0)</div>
          <div className={`text-sm font-mono font-bold ${Number(ethPrice) > 1 ? 'text-red-400' : 'text-green-400'}`}>
            {Number(ethPrice).toLocaleString()}
          </div>
        </div>
      </div>
      <p className="text-[10px] text-uni-text font-mono">
        Constant-product AMM. Price = reserve1 / reserve0.
        Swap 1000 TOKEN1 → price 1→4. Swap 500 TOKEN0 back → price 4→1.
      </p>
    </div>
  )
}

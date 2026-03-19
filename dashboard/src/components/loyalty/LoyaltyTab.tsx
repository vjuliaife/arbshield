import { useState } from 'react'
import {
  unichainClient, ADDRESSES, LOYALTY_REGISTRY_ABI,
  TIER_LABELS, TIER_EMOJI, TIER_DISCOUNTS, TIER_THRESHOLDS,
} from '../../constants'

export default function LoyaltyTab({ account }: { account: `0x${string}` | null }) {
  const [addr,    setAddr]    = useState(account ?? '')
  const [loading, setLoading] = useState(false)
  const [error,   setError]   = useState<string | null>(null)
  const [result,  setResult]  = useState<{ tier: number; count: bigint; discount: number } | null>(null)

  async function check() {
    const a = addr.trim()
    if (!/^0x[0-9a-fA-F]{40}$/.test(a)) { setError('Enter a valid 0x address'); return }
    setLoading(true)
    setError(null)
    try {
      const [tier, count, discount] = await Promise.all([
        unichainClient.readContract({
          address: ADDRESSES.UNI.LOYALTY, abi: LOYALTY_REGISTRY_ABI,
          functionName: 'loyaltyTier', args: [a as `0x${string}`],
        }) as Promise<number>,
        unichainClient.readContract({
          address: ADDRESSES.UNI.LOYALTY, abi: LOYALTY_REGISTRY_ABI,
          functionName: 'lpActivityCount', args: [a as `0x${string}`],
        }) as Promise<bigint>,
        unichainClient.readContract({
          address: ADDRESSES.UNI.LOYALTY, abi: LOYALTY_REGISTRY_ABI,
          functionName: 'getFeeDiscount', args: [a as `0x${string}`],
        }) as Promise<number>,
      ])
      setResult({ tier, count, discount })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Lookup failed')
    } finally {
      setLoading(false)
    }
  }

  const nextTier  = result ? Math.min(result.tier + 1, 3) : null
  const needsMore = result && nextTier !== null && nextTier > result.tier
    ? TIER_THRESHOLDS[nextTier] - Number(result.count)
    : 0

  const tierColor = (t: number) => {
    if (t === 3) return 'text-yellow-400'
    if (t === 2) return 'text-gray-300'
    if (t === 1) return 'text-amber-600'
    return 'text-uni-text'
  }
  const tierBg = (t: number) => {
    if (t === 3) return 'border-yellow-500/40 bg-yellow-500/5'
    if (t === 2) return 'border-gray-400/40 bg-gray-400/5'
    if (t === 1) return 'border-amber-600/40 bg-amber-600/5'
    return 'border-uni-border bg-uni-card'
  }

  return (
    <div className="p-4 space-y-4">
      <div className="card">
        <div className="label mb-3">Loyalty Tier Lookup</div>
        <p className="text-[11px] text-uni-text font-mono mb-4">
          Enter any address to check their loyalty tier, activity count, and fee discount on Unichain Sepolia.
        </p>
        <div className="flex gap-2">
          <input
            type="text"
            value={addr}
            onChange={e => setAddr(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && check()}
            placeholder="0x… wallet address"
            className="flex-1 bg-uni-bg border border-uni-border rounded-lg px-3 py-2 text-xs font-mono text-white placeholder-uni-text focus:outline-none focus:border-uni-pink"
          />
          <button
            onClick={check}
            disabled={loading}
            className="btn btn-pink text-xs disabled:opacity-50"
          >
            {loading ? '…' : 'Check'}
          </button>
        </div>
        {error && (
          <p className="mt-2 text-xs text-red-400 font-mono">{error}</p>
        )}
      </div>

      {result && (
        <>
          {/* Tier badge */}
          <div className={`card border ${tierBg(result.tier)} text-center`}>
            <div className="text-5xl mb-2">{TIER_EMOJI[result.tier]}</div>
            <div className={`text-2xl font-bold ${tierColor(result.tier)}`}>{TIER_LABELS[result.tier]}</div>
            <div className="text-[10px] text-uni-text font-mono mt-1">Loyalty Tier</div>
          </div>

          {/* Stats grid */}
          <div className="grid grid-cols-3 gap-3">
            <div className="card text-center">
              <div className="label">Activities</div>
              <div className="text-xl font-bold text-white mt-1">{result.count.toString()}</div>
              <div className="text-[10px] text-uni-text font-mono">ETH LP events detected</div>
            </div>
            <div className={`card text-center ${result.discount > 0 ? 'border-uni-pink/30 bg-uni-pink/5' : ''}`}>
              <div className="label">Fee Discount</div>
              <div className={`text-xl font-bold mt-1 ${result.discount > 0 ? 'text-uni-pink' : 'text-white'}`}>
                {TIER_DISCOUNTS[result.tier]}%
              </div>
              <div className="text-[10px] text-uni-text font-mono">off effective fee</div>
            </div>
            <div className="card text-center">
              <div className="label">Next Tier</div>
              <div className="text-xl font-bold text-white mt-1">
                {result.tier < 3 ? TIER_EMOJI[result.tier + 1] : '—'}
              </div>
              <div className="text-[10px] text-uni-text font-mono">
                {result.tier < 3 && needsMore > 0
                  ? `${needsMore} more to ${TIER_LABELS[result.tier + 1]}`
                  : result.tier === 3 ? 'Max reached' : TIER_LABELS[result.tier + 1]}
              </div>
            </div>
          </div>

          {/* Tier progress bar */}
          <div className="card">
            <div className="label mb-3">Tier Ladder</div>
            <div className="flex items-center gap-2">
              {([0, 1, 2, 3] as const).map((t) => (
                <div key={t} className="flex-1 flex flex-col items-center gap-1">
                  <div className="text-xl">{TIER_EMOJI[t]}</div>
                  <div className={`w-full h-1.5 rounded-full ${result.tier >= t ? 'bg-uni-pink' : 'bg-uni-border'}`} />
                  <div className={`text-[9px] font-mono ${result.tier >= t ? tierColor(t) : 'text-uni-text'}`}>
                    {TIER_LABELS[t]}
                  </div>
                  <div className="text-[9px] font-mono text-uni-text">{TIER_THRESHOLDS[t]}+</div>
                </div>
              ))}
            </div>
          </div>

          {/* How it works */}
          <div className="card border-dashed border-uni-text/30">
            <div className="label mb-2">How loyalty is earned</div>
            <p className="text-[11px] text-uni-text font-mono leading-relaxed">
              Provide liquidity to the ETH/USDC V3 pool on Ethereum for ≥ 7 days (50,400 blocks).
              The Reactive Network RSC detects your Burn event and emits a cross-chain callback to
              LoyaltyRegistry on Unichain. On the next swap through ArbShield, your fee discount applies automatically.
            </p>
            <div className="mt-3 grid grid-cols-2 gap-2 text-[10px] font-mono">
              <div className="flex items-start gap-1.5">
                <span className="text-uni-pink mt-0.5">1.</span>
                <span className="text-uni-text">Add liquidity to Ethereum V3 pool</span>
              </div>
              <div className="flex items-start gap-1.5">
                <span className="text-uni-pink mt-0.5">2.</span>
                <span className="text-uni-text">Hold position ≥ 50,400 blocks (~7 days)</span>
              </div>
              <div className="flex items-start gap-1.5">
                <span className="text-uni-pink mt-0.5">3.</span>
                <span className="text-uni-text">Remove liquidity → Burn event emitted</span>
              </div>
              <div className="flex items-start gap-1.5">
                <span className="text-uni-pink mt-0.5">4.</span>
                <span className="text-uni-text">RSC detects event, issues Unichain callback</span>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

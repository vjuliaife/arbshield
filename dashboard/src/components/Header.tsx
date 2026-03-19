import { motion, AnimatePresence } from 'framer-motion'
import { CHAIN_IDS } from '../constants'

export type Tab = 'overview' | 'ethereum' | 'unichain' | 'loyalty' | 'admin'

interface HeaderProps {
  activeTab: Tab
  onTabChange: (tab: Tab) => void
  account: `0x${string}` | null
  chainId: number | null
  onConnect: () => void
  onSwitchEth: () => void
  onSwitchUni: () => void
  lastPolled: Date | null
  rpcError: string | null
}

const TABS: { id: Tab; label: string }[] = [
  { id: 'overview',  label: 'Overview' },
  { id: 'ethereum',  label: 'Ethereum Pool' },
  { id: 'unichain',  label: 'Unichain Pool' },
  { id: 'loyalty',   label: '🏅 Loyalty' },
  { id: 'admin',     label: '🛡 Admin' },
]

function ChainBadge({ chainId, tab }: { chainId: number | null; tab: Tab }) {
  if (tab === 'overview' || tab === 'loyalty' || tab === 'admin') return null
  const expected = tab === 'ethereum' ? CHAIN_IDS.ETH_SEPOLIA : CHAIN_IDS.UNICHAIN
  const ok = chainId === expected
  return (
    <span className={`text-[9px] font-mono px-1.5 py-0.5 rounded-full border ${
      ok ? 'border-green-500/40 text-green-400 bg-green-500/10'
         : 'border-yellow-500/40 text-yellow-400 bg-yellow-500/10'
    }`}>
      {tab === 'ethereum' ? 'ETH Sepolia' : 'Unichain'}
    </span>
  )
}

export default function Header({
  activeTab, onTabChange,
  account, chainId,
  onConnect, onSwitchEth, onSwitchUni,
  lastPolled, rpcError,
}: HeaderProps) {
  const shortAddr = account ? `${account.slice(0, 6)}…${account.slice(-4)}` : null

  function handleChainSwitch() {
    if (activeTab === 'ethereum') onSwitchEth()
    if (activeTab === 'unichain') onSwitchUni()
  }

  const expectedChain = activeTab === 'ethereum' ? CHAIN_IDS.ETH_SEPOLIA
    : (activeTab === 'unichain' || activeTab === 'admin') ? CHAIN_IDS.UNICHAIN
    : null
  const wrongChain = expectedChain !== null && chainId !== expectedChain && account !== null

  return (
    <header className="border-b border-uni-border bg-uni-bg sticky top-0 z-40">
      {/* Main header row */}
      <div className="px-4 py-2 flex items-center justify-between gap-4">
        {/* Logo */}
        <div className="flex items-center gap-2 flex-shrink-0">
          <span className="text-xl">⚡</span>
          <span className="font-bold text-base">ArbShield</span>
          <span className="text-uni-text text-xs hidden md:block">LVR Mitigation</span>
        </div>

        {/* Tab nav */}
        <nav className="flex items-center gap-1 flex-1 justify-center">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`relative px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                activeTab === tab.id
                  ? 'text-white bg-uni-card'
                  : 'text-uni-text hover:text-white'
              }`}
            >
              {tab.label}
              {activeTab === tab.id && (
                <motion.div
                  layoutId="activeTab"
                  className="absolute inset-0 rounded-lg bg-uni-pink/10 border border-uni-pink/30"
                  transition={{ type: 'spring', bounce: 0.2, duration: 0.4 }}
                />
              )}
            </button>
          ))}
        </nav>

        {/* Wallet + status */}
        <div className="flex items-center gap-2 flex-shrink-0">
          {/* RPC status dot */}
          <AnimatePresence mode="wait">
            {rpcError ? (
              <motion.div key="err" initial={{ scale: 0 }} animate={{ scale: 1 }} className="w-2 h-2 rounded-full bg-red-500" title={rpcError} />
            ) : (
              <motion.div key="ok" initial={{ scale: 0 }} animate={{ scale: 1 }} className="w-2 h-2 rounded-full bg-green-500" />
            )}
          </AnimatePresence>
          {lastPolled && <span className="text-[10px] text-uni-text font-mono hidden lg:block">{lastPolled.toLocaleTimeString()}</span>}

          {/* Wrong chain warning */}
          {wrongChain && (
            <button
              onClick={handleChainSwitch}
              className="text-[10px] font-mono px-2 py-1 rounded border border-yellow-500/50 text-yellow-400 bg-yellow-500/10 hover:bg-yellow-500/20 transition-colors"
            >
              Switch chain ⚠
            </button>
          )}

          {/* Wallet button */}
          {account ? (
            <div className="flex items-center gap-1.5">
              <ChainBadge chainId={chainId} tab={activeTab} />
              <span className="text-xs font-mono text-white px-2 py-1 rounded border border-uni-border bg-uni-card">
                {shortAddr}
              </span>
            </div>
          ) : (
            <button onClick={onConnect} className="btn btn-pink text-xs py-1 px-3">
              Connect
            </button>
          )}
        </div>
      </div>
    </header>
  )
}

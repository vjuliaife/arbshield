import { useState, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import Header, { type Tab } from './components/Header'
import OverviewTab from './components/overview/OverviewTab'
import EthereumTab from './components/ethereum/EthereumTab'
import UnichainTab from './components/unichain/UnichainTab'
import LoyaltyTab from './components/loyalty/LoyaltyTab'
import AdminTab from './components/admin/AdminTab'
import { useWallet } from './hooks/useWallet'

export default function App() {
  const [activeTab, setActiveTab] = useState<Tab>('overview')
  const [lastPolled, setLastPolled] = useState<Date | null>(null)
  const [rpcError, setRpcError] = useState<string | null>(null)

  const wallet = useWallet()

  const handleLastPolled = useCallback((d: Date) => setLastPolled(d), [])
  const handleRpcError   = useCallback((e: string | null) => setRpcError(e), [])

  return (
    <div className="min-h-screen bg-uni-bg text-white flex flex-col">
      <Header
        activeTab={activeTab}
        onTabChange={setActiveTab}
        account={wallet.account}
        chainId={wallet.chainId}
        onConnect={wallet.connect}
        onSwitchEth={wallet.switchToEthSepolia}
        onSwitchUni={wallet.switchToUnichain}
        lastPolled={lastPolled}
        rpcError={rpcError}
      />

      {/* Main content */}
      <main className="flex-1">
        <AnimatePresence mode="wait">
          {activeTab === 'overview' && (
            <motion.div
              key="overview"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.15 }}
            >
              <OverviewTab
                account={wallet.account}
                chainId={wallet.chainId}
                onLastPolled={handleLastPolled}
                onRpcError={handleRpcError}
              />
            </motion.div>
          )}

          {activeTab === 'ethereum' && (
            <motion.div
              key="ethereum"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.15 }}
            >
              <EthereumTab
                account={wallet.account}
                chainId={wallet.chainId}
                onSwitchEth={wallet.switchToEthSepolia}
              />
            </motion.div>
          )}

          {activeTab === 'unichain' && (
            <motion.div
              key="unichain"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.15 }}
            >
              <UnichainTab
                account={wallet.account}
                chainId={wallet.chainId}
                onSwitchUni={wallet.switchToUnichain}
              />
            </motion.div>
          )}

          {activeTab === 'loyalty' && (
            <motion.div
              key="loyalty"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.15 }}
            >
              <LoyaltyTab account={wallet.account} />
            </motion.div>
          )}

          {activeTab === 'admin' && (
            <motion.div
              key="admin"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.15 }}
            >
              <AdminTab
                account={wallet.account}
                chainId={wallet.chainId}
                onSwitchUni={wallet.switchToUnichain}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </main>

      {/* Footer */}
      <footer className="border-t border-uni-border px-4 py-2 flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-4 text-[10px] font-mono text-uni-text">
          <span>Hook: 0xa078…60c0</span>
          <span className="hidden sm:inline">Unichain Sepolia · Ethereum Sepolia · Reactive Lasna</span>
        </div>
        <div className="text-[10px] font-mono text-uni-text">ArbShield</div>
      </footer>
    </div>
  )
}

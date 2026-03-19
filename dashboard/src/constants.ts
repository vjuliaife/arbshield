import {
  createPublicClient,
  http,
  defineChain,
  encodeFunctionData,
  encodeAbiParameters,
  encodePacked,
  keccak256,
  parseUnits,
  maxUint256,
  concat,
} from 'viem'
import { sepolia } from 'viem/chains'

// ── Chain definitions ────────────────────────────────────────────────────────

export const unichainSepolia = defineChain({
  id: 1301,
  name: 'Unichain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://sepolia.unichain.org'] } },
  blockExplorers: {
    default: { name: 'Blockscout', url: 'https://unichain-sepolia.blockscout.com' },
  },
})

// ── Public clients (read-only) ───────────────────────────────────────────────

export const ethClient = createPublicClient({
  chain: sepolia,
  transport: http('https://ethereum-sepolia-rpc.publicnode.com'),
})

export const unichainClient = createPublicClient({
  chain: unichainSepolia,
  transport: http('https://sepolia.unichain.org'),
})

// ── Deployed addresses ───────────────────────────────────────────────────────

export const ADDRESSES = {
  // Ethereum Sepolia (chainId 11155111)
  ETH: {
    TOKEN0: '0xC6D9516E6D04b0b65A3cbba45DD5c8A608496Ff4' as `0x${string}`,  // mWETH 18dec
    TOKEN1: '0xd72bd0ede3d477c3a19304248e786363413abe42' as `0x${string}`,  // mUSDC 18dec
    POOL:   '0x7562e05BA8364DA1C9A8179cc3A996d5DDF7a98C' as `0x${string}`,  // MockV3Pool
  },
  // Reactive Lasna (chain 5318007)
  REACTIVE: {
    RSC: '0xD72Bd0eDE3d477C3a19304248E786363413ABE42' as `0x${string}`, // ArbShieldReactive
  },
  // Unichain Sepolia (chainId 1301)
  UNI: {
    TOKEN0:          '0x7562e05BA8364DA1C9A8179cc3A996d5DDF7a98C' as `0x${string}`, // mWETH 18dec
    TOKEN1:          '0x927f446991425b1Df8fb7e3879192A84c31C6544' as `0x${string}`, // mUSDC 6dec
    HOOK:            '0xa0780721F3e29816708028d20D7906cAF44660c0' as `0x${string}`,
    CALLBACK:        '0x1ebf25b0e40a00a3bdc14a4c1ff2564afc0e9894' as `0x${string}`,
    LOYALTY:         '0xc6d9516e6d04b0b65a3cbba45dd5c8a608496ff4' as `0x${string}`,
    POOL_MANAGER:    '0x00B036B58a818B1BC34d502D3fE730Db729e62AC' as `0x${string}`,
    POSITION_MGR:    '0xf969Aee60879C54bAAed9F3eD26147Db216Fd664' as `0x${string}`,
    PERMIT2:         '0x000000000022D473030F116dDEE9F6B43aC78BA3' as `0x${string}`,
    UNIVERSAL_ROUTER:'0xf70536b3bcc1bd1a972dc186a2cf84cc6da6be5d' as `0x${string}`,
  },
} as const

// ── Token decimals ───────────────────────────────────────────────────────────

export const DECIMALS = {
  ETH_TOKEN0: 18, // mWETH
  ETH_TOKEN1: 18, // mUSDC (Ethereum Sepolia)
  UNI_TOKEN0: 18, // mWETH
  UNI_TOKEN1: 6,  // mUSDC (Unichain Sepolia)
} as const

// ── Unichain v4 PoolKey ──────────────────────────────────────────────────────

export const POOL_KEY = {
  currency0:   ADDRESSES.UNI.TOKEN0,
  currency1:   ADDRESSES.UNI.TOKEN1,
  fee:         0x800000,  // LPFeeLibrary.DYNAMIC_FEE_FLAG = 8388608
  tickSpacing: 60,
  hooks:       ADDRESSES.UNI.HOOK,
} as const

// PoolId = keccak256(abi.encode(PoolKey))
export const POOL_ID = keccak256(
  encodeAbiParameters(
    [
      { type: 'address' },
      { type: 'address' },
      { type: 'uint24'  },
      { type: 'int24'   },
      { type: 'address' },
    ],
    [
      POOL_KEY.currency0,
      POOL_KEY.currency1,
      POOL_KEY.fee,
      POOL_KEY.tickSpacing,
      POOL_KEY.hooks,
    ]
  )
) as `0x${string}`

// ── Chain IDs ────────────────────────────────────────────────────────────────

export const CHAIN_IDS = {
  ETH_SEPOLIA: 11155111,
  UNICHAIN:    1301,
} as const

// ── ABIs ─────────────────────────────────────────────────────────────────────

export const ERC20_ABI = [
  { name: 'mint',     type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'to', type: 'address' }, { name: 'value', type: 'uint256' }],
    outputs: [] },
  { name: 'approve',  type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }] },
] as const

export const POOL_ABI = [
  { name: 'getPrice', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'reserve0', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'reserve1', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'swap', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'zeroForOne', type: 'bool' },
      { name: 'amountIn', type: 'uint256' },
      { name: 'recipient', type: 'address' },
    ],
    outputs: [{ name: 'amountOut', type: 'uint256' }] },
  { name: 'addLiquidity', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount0', type: 'uint256' },
      { name: 'amount1', type: 'uint256' },
    ],
    outputs: [] },
] as const

export const HOOK_ABI = [
  { name: 'getEffectiveFee', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint24' }] },
  { name: 'isFeeElevated', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: 'elevated', type: 'bool' }, { name: 'elevationBps', type: 'uint24' }] },
  { name: 'getProtocolStats', type: 'function', stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'effectiveFee', type: 'uint24' },
      { name: '_baseFee', type: 'uint24' },
      { name: 'divergenceFee', type: 'uint24' },
      { name: '_lastFeeUpdate', type: 'uint256' },
      { name: 'arbFeeCaptured', type: 'uint256' },
      { name: 'loyaltyDiscounts', type: 'uint256' },
      { name: '_totalSwaps', type: 'uint256' },
      { name: 'isPaused', type: 'bool' },
    ] },
  { name: 'baseFee', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint24' }] },
  { name: 'owner', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'address' }] },
  { name: 'paused', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'bool' }] },
  { name: 'pause',   type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { name: 'unpause', type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  // Events
  { name: 'DivergenceFeeUpdated', type: 'event',
    inputs: [
      { name: 'newFee', type: 'uint24', indexed: false },
      { name: 'divergenceBps', type: 'uint256', indexed: false },
      { name: 'timestamp', type: 'uint256', indexed: false },
    ] },
  { name: 'FeeResetToBase', type: 'event',
    inputs: [{ name: 'timestamp', type: 'uint256', indexed: false }] },
  { name: 'ArbFeeCaptured', type: 'event',
    inputs: [
      { name: 'effectiveFee', type: 'uint24', indexed: false },
      { name: 'baseFee', type: 'uint24', indexed: false },
      { name: 'extraFeeBps', type: 'uint256', indexed: false },
    ] },
  { name: 'LoyaltyDiscountApplied', type: 'event',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'discount', type: 'uint24', indexed: false },
      { name: 'finalFee', type: 'uint24', indexed: false },
    ] },
  { name: 'Paused', type: 'event',
    inputs: [{ name: 'account', type: 'address', indexed: true }] },
  { name: 'Unpaused', type: 'event',
    inputs: [{ name: 'account', type: 'address', indexed: true }] },
  { name: 'UnichainPriorityFeeMonitored', type: 'event',
    inputs: [
      { name: 'priorityFee', type: 'uint256', indexed: false },
      { name: 'blockBaseFee', type: 'uint256', indexed: false },
    ] },
] as const

export const POOL_MANAGER_ABI = [
  // v4-core exposes pool state via extsload (StateLibrary pattern), NOT getSlot0/getLiquidity
  { name: 'extsload', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'slot', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bytes32' }] },
  { name: 'initialize', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'key', type: 'tuple', components: [
        { name: 'currency0',   type: 'address' },
        { name: 'currency1',   type: 'address' },
        { name: 'fee',         type: 'uint24'  },
        { name: 'tickSpacing', type: 'int24'   },
        { name: 'hooks',       type: 'address' },
      ]},
      { name: 'sqrtPriceX96', type: 'uint160' },
    ],
    outputs: [{ name: 'tick', type: 'int24' }] },
] as const

// ── Pool state storage slots (StateLibrary pattern) ──────────────────────────
//
// In v4-core PoolManager, pool state lives in:
//   mapping(PoolId => Pool.State) pools;  ← at storage slot 6 (POOLS_SLOT)
//
// Pool.State layout:
//   slot+0  Slot0 (packed): sqrtPriceX96[160] | tick[24] | protocolFee[24] | lpFee[24]
//   slot+1  feeGrowthGlobal0X128
//   slot+2  feeGrowthGlobal1X128
//   slot+3  liquidity (uint128 at low bits)
//
// stateSlot = keccak256(abi.encodePacked(POOL_ID, POOLS_SLOT))

const POOLS_SLOT = '0x0000000000000000000000000000000000000000000000000000000000000006' as `0x${string}`
export const POOL_STATE_SLOT = keccak256(concat([POOL_ID, POOLS_SLOT]))
export const POOL_LIQUIDITY_SLOT = (
  '0x' + (BigInt(POOL_STATE_SLOT) + 3n).toString(16).padStart(64, '0')
) as `0x${string}`

/** Parse the packed Slot0 word returned by extsload(POOL_STATE_SLOT) */
export function parseSlot0(raw: `0x${string}`): { sqrtPriceX96: bigint; tick: number } {
  const data = BigInt(raw)
  const sqrtPriceX96 = data & ((1n << 160n) - 1n)
  // tick is 24-bit signed at bits 160..183 — sign-extend
  const rawTick = (data >> 160n) & ((1n << 24n) - 1n)
  const tick = rawTick >= (1n << 23n) ? Number(rawTick - (1n << 24n)) : Number(rawTick)
  return { sqrtPriceX96, tick }
}

// sqrtPriceX96 = 2^96 → tick 0, raw price = 1. Places the pool inside the default tick range (-600 to +600).
export const INIT_SQRT_PRICE_X96 = 79228162514264337593543950336n  // = 2^96, tick 0

export const POSITION_MGR_ABI = [
  { name: 'initializePool', type: 'function', stateMutability: 'payable',
    inputs: [
      { name: 'key', type: 'tuple', components: [
        { name: 'currency0',   type: 'address' },
        { name: 'currency1',   type: 'address' },
        { name: 'fee',         type: 'uint24'  },
        { name: 'tickSpacing', type: 'int24'   },
        { name: 'hooks',       type: 'address' },
      ]},
      { name: 'sqrtPriceX96', type: 'uint160' },
    ],
    outputs: [{ name: 'tick', type: 'int24' }] },
  { name: 'modifyLiquidities', type: 'function', stateMutability: 'payable',
    inputs: [{ name: 'unlockData', type: 'bytes' }, { name: 'deadline', type: 'uint256' }],
    outputs: [] },
  { name: 'nextTokenId', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'positionInfo', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'bytes32' }] },
  { name: 'ownerOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'address' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }] },
] as const

export const PERMIT2_ABI = [
  { name: 'approve', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
    ],
    outputs: [] },
  { name: 'allowance', type: 'function', stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'token', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
      { name: 'nonce', type: 'uint48' },
    ] },
] as const

export const UNIVERSAL_ROUTER_ABI = [
  { name: 'execute', type: 'function', stateMutability: 'payable',
    inputs: [
      { name: 'commands', type: 'bytes' },
      { name: 'inputs', type: 'bytes[]' },
      { name: 'deadline', type: 'uint256' },
    ],
    outputs: [] },
] as const

export const LOYALTY_REGISTRY_ABI = [
  { name: 'lpActivityCount',     type: 'function', stateMutability: 'view',
    inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'loyaltyTier',         type: 'function', stateMutability: 'view',
    inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'uint8' }] },
  { name: 'getFeeDiscount',      type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }], outputs: [{ type: 'uint24' }] },
  { name: 'totalLoyaltyMembers', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'owner',               type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'address' }] },
  { name: 'setTier', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'user', type: 'address' }, { name: 'tier', type: 'uint8' }], outputs: [] },
] as const

export const TIER_LABELS   = ['NONE', 'BRONZE', 'SILVER', 'GOLD'] as const
export const TIER_EMOJI    = ['⚪', '🥉', '🥈', '🥇'] as const
export const TIER_DISCOUNTS = [0, 10, 20, 30] as const
export const TIER_THRESHOLDS = [0, 1, 5, 10] as const

// ── Encode helpers ───────────────────────────────────────────────────────────

// Actions (from v4-periphery Actions.sol)
const ACTIONS = {
  SWAP_EXACT_IN_SINGLE: 0x06,
  SETTLE_ALL:           0x0c,  // V4Router: settles one currency from msgSender
  TAKE_ALL:             0x0f,  // V4Router: takes one currency to msgSender
  SETTLE_PAIR:          0x0d,  // PositionManager only
  TAKE_PAIR:            0x11,  // PositionManager only
  MINT_POSITION:        0x02,
  BURN_POSITION:        0x03,
} as const

// PoolKey ABI type for encodeAbiParameters
const POOL_KEY_TUPLE = {
  type: 'tuple',
  components: [
    { name: 'currency0',   type: 'address' },
    { name: 'currency1',   type: 'address' },
    { name: 'fee',         type: 'uint24'  },
    { name: 'tickSpacing', type: 'int24'   },
    { name: 'hooks',       type: 'address' },
  ],
} as const

// encode a MockV3Pool swap call
export function encodeV3Swap(zeroForOne: boolean, amountIn: bigint, recipient: `0x${string}`): `0x${string}` {
  return encodeFunctionData({ abi: POOL_ABI, functionName: 'swap', args: [zeroForOne, amountIn, recipient] })
}

// encode an ERC20 approve call
export function encodeApprove(spender: `0x${string}`, amount: bigint): `0x${string}` {
  return encodeFunctionData({ abi: ERC20_ABI, functionName: 'approve', args: [spender, amount] })
}

// encode an ERC20 mint call
export function encodeMint(to: `0x${string}`, amount: bigint): `0x${string}` {
  return encodeFunctionData({ abi: ERC20_ABI, functionName: 'mint', args: [to, amount] })
}

// encode MockV3Pool addLiquidity
export function encodeAddLiquidity(amount0: bigint, amount1: bigint): `0x${string}` {
  return encodeFunctionData({ abi: POOL_ABI, functionName: 'addLiquidity', args: [amount0, amount1] })
}

// Typed helper: encode (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes)
// Uses any-cast to bypass viem's strict nested-tuple inference
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const _encodeAbi = encodeAbiParameters as (...args: any[]) => `0x${string}`

// encode PositionManager.modifyLiquidities for MINT_POSITION
export function encodeV4MintPosition(params: {
  tickLower: number
  tickUpper: number
  liquidity: bigint
  amount0Max: bigint
  amount1Max: bigint
  recipient: `0x${string}`
  deadline: bigint
}): `0x${string}` {
  const actions = encodePacked(['uint8', 'uint8'], [ACTIONS.MINT_POSITION, ACTIONS.SETTLE_PAIR])

  const poolKeyArr = [
    POOL_KEY.currency0, POOL_KEY.currency1,
    POOL_KEY.fee, POOL_KEY.tickSpacing, POOL_KEY.hooks,
  ]

  const mintParams = _encodeAbi(
    [
      POOL_KEY_TUPLE,
      { type: 'int24'   },
      { type: 'int24'   },
      { type: 'uint256' },
      { type: 'uint128' },
      { type: 'uint128' },
      { type: 'address' },
      { type: 'bytes'   },
    ],
    [
      poolKeyArr,
      params.tickLower,
      params.tickUpper,
      params.liquidity,
      params.amount0Max,
      params.amount1Max,
      params.recipient,
      '0x',
    ]
  )

  const settlePairParams = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency0, POOL_KEY.currency1]
  )

  const unlockData = encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes[]' }],
    [actions, [mintParams, settlePairParams]]
  )

  return encodeFunctionData({
    abi: POSITION_MGR_ABI,
    functionName: 'modifyLiquidities',
    args: [unlockData, params.deadline],
  })
}

// encode PositionManager.modifyLiquidities for BURN_POSITION
export function encodeV4BurnPosition(params: {
  tokenId: bigint
  recipient: `0x${string}`
  deadline: bigint
}): `0x${string}` {
  const actions = encodePacked(['uint8', 'uint8'], [ACTIONS.BURN_POSITION, ACTIONS.TAKE_PAIR])

  const burnParams = encodeAbiParameters(
    [
      { type: 'uint256' },  // tokenId
      { type: 'uint128' },  // amount0Min
      { type: 'uint128' },  // amount1Min
      { type: 'bytes'   },  // hookData
    ],
    [params.tokenId, 0n, 0n, '0x']
  )

  const takePairParams = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency0, POOL_KEY.currency1, params.recipient]
  )

  const unlockData = encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes[]' }],
    [actions, [burnParams, takePairParams]]
  )

  return encodeFunctionData({
    abi: POSITION_MGR_ABI,
    functionName: 'modifyLiquidities',
    args: [unlockData, params.deadline],
  })
}

// encode UniversalRouter V4 exact-input-single swap
// command 0x10 = V4_SWAP; actions: SWAP_EXACT_IN_SINGLE + SETTLE_ALL + TAKE_ALL
// Note: V4Router does NOT support SETTLE_PAIR/TAKE_PAIR (those are PositionManager-only).
// SETTLE_ALL settles one currency (input) from msgSender via Permit2.
// TAKE_ALL takes one currency (output) and sends to msgSender.
export function encodeV4Swap(params: {
  zeroForOne: boolean
  amountIn: bigint
  recipient: `0x${string}`
  deadline: bigint
}): `0x${string}` {
  const actions = encodePacked(
    ['uint8', 'uint8', 'uint8'],
    [ACTIONS.SWAP_EXACT_IN_SINGLE, ACTIONS.SETTLE_ALL, ACTIONS.TAKE_ALL]
  )

  const poolKeyArr = [
    POOL_KEY.currency0, POOL_KEY.currency1,
    POOL_KEY.fee, POOL_KEY.tickSpacing, POOL_KEY.hooks,
  ]

  const swapParam = _encodeAbi(
    [{
      type: 'tuple',
      components: [
        POOL_KEY_TUPLE,
        { name: 'zeroForOne',       type: 'bool'    },
        { name: 'amountIn',         type: 'uint128' },
        { name: 'amountOutMinimum', type: 'uint128' },
        { name: 'hookData',         type: 'bytes'   },
      ],
    }],
    [[poolKeyArr, params.zeroForOne, params.amountIn, 0n, '0x']]
  )

  // SETTLE_ALL(currency, maxAmount) — settle input currency from msgSender
  const inputCurrency  = params.zeroForOne ? POOL_KEY.currency0 : POOL_KEY.currency1
  const outputCurrency = params.zeroForOne ? POOL_KEY.currency1 : POOL_KEY.currency0

  const settleParam = encodeAbiParameters(
    [{ type: 'address' }, { type: 'uint256' }],
    [inputCurrency, maxUint256]
  )

  // TAKE_ALL(currency, minAmount) — take output currency, send to msgSender
  const takeParam = encodeAbiParameters(
    [{ type: 'address' }, { type: 'uint256' }],
    [outputCurrency, 0n]
  )

  const v4Input = encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes[]' }],
    [actions, [swapParam, settleParam, takeParam]]
  )

  return encodeFunctionData({
    abi: UNIVERSAL_ROUTER_ABI,
    functionName: 'execute',
    args: ['0x10', [v4Input], params.deadline],
  })
}

// encode Permit2 approve
export function encodePermit2Approve(token: `0x${string}`, spender: `0x${string}`): `0x${string}` {
  const MAX_UINT160 = (1n << 160n) - 1n
  // uint48 max = 281474976710655 — safe as JS number (< 2^53)
  const MAX_UINT48_NUM = 281474976710655
  return encodeFunctionData({
    abi: PERMIT2_ABI,
    functionName: 'approve',
    args: [token, spender, MAX_UINT160, MAX_UINT48_NUM],
  })
}

// ── Liquidity math ────────────────────────────────────────────────────────────

// Convert tick to sqrtPriceX96 (floating-point OK for UI purposes)
export function tickToSqrtPriceX96(tick: number): bigint {
  const Q96 = 2n ** 96n
  const sqrtPrice = Math.sqrt(Math.pow(1.0001, tick))
  return BigInt(Math.floor(sqrtPrice * Number(Q96)))
}

// Compute liquidity for amounts — mirrors LiquidityAmounts.getLiquidityForAmounts
export function getLiquidityForAmounts(
  sqrtPriceX96: bigint,
  tickLower: number,
  tickUpper: number,
  amount0: bigint,
  amount1: bigint
): bigint {
  const Q96 = 2n ** 96n
  const sqrtA = tickToSqrtPriceX96(tickLower)
  const sqrtB = tickToSqrtPriceX96(tickUpper)
  const [lo, hi] = sqrtA < sqrtB ? [sqrtA, sqrtB] : [sqrtB, sqrtA]
  const sqrtP = sqrtPriceX96

  const getLiqForAmount0 = (a: bigint, b: bigint, amt: bigint): bigint => {
    if (a === 0n || b === 0n || b <= a) return 0n
    return (amt * a * b) / ((b - a) * Q96)
  }

  const getLiqForAmount1 = (a: bigint, b: bigint, amt: bigint): bigint => {
    if (b <= a) return 0n
    return (amt * Q96) / (b - a)
  }

  if (sqrtP <= lo) {
    return getLiqForAmount0(lo, hi, amount0)
  } else if (sqrtP < hi) {
    const liq0 = getLiqForAmount0(sqrtP, hi, amount0)
    const liq1 = getLiqForAmount1(lo, sqrtP, amount1)
    return liq0 < liq1 ? liq0 : liq1
  } else {
    return getLiqForAmount1(lo, hi, amount1)
  }
}

// ── Window ethereum helpers ───────────────────────────────────────────────────

declare global {
  interface Window {
    ethereum?: {
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>
      on: (event: string, handler: (...args: unknown[]) => void) => void
      removeListener: (event: string, handler: (...args: unknown[]) => void) => void
      isMetaMask?: boolean
    }
  }
}

export async function getAccounts(): Promise<`0x${string}`[]> {
  if (!window.ethereum) throw new Error('MetaMask not found')
  return window.ethereum.request({ method: 'eth_requestAccounts' }) as Promise<`0x${string}`[]>
}

export async function switchChain(chainId: number): Promise<void> {
  const hex = '0x' + chainId.toString(16)
  await window.ethereum!.request({
    method: 'wallet_switchEthereumChain',
    params: [{ chainId: hex }],
  })
}

export async function sendTx(to: `0x${string}`, data: `0x${string}`, from: `0x${string}`, nonce?: string): Promise<`0x${string}`> {
  const tx: Record<string, string> = { from, to, data, gas: '0x' + (1200000).toString(16) }
  if (nonce !== undefined) tx.nonce = nonce
  return window.ethereum!.request({
    method: 'eth_sendTransaction',
    params: [tx],
  }) as Promise<`0x${string}`>
}

export async function waitForTx(hash: `0x${string}`): Promise<void> {
  for (let i = 0; i < 90; i++) {
    await new Promise(r => setTimeout(r, 2000))
    try {
      const receipt = await window.ethereum!.request({
        method: 'eth_getTransactionReceipt',
        params: [hash],
      })
      if (receipt) {
        if ((receipt as { status: string }).status === '0x0') {
          throw new Error('Transaction reverted on-chain')
        }
        return
      }
    } catch (e) {
      if (e instanceof Error && e.message.includes('reverted')) throw e
      /* else continue polling */
    }
  }
  throw new Error('Transaction timeout after 180s')
}

// Explorer links
export function etherscanTx(hash: string): string {
  return `https://sepolia.etherscan.io/tx/${hash}`
}
export function blockscoutTx(hash: string): string {
  return `https://unichain-sepolia.blockscout.com/tx/${hash}`
}

export { parseUnits, maxUint256, encodeFunctionData }

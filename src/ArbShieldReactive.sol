// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AbstractReactive} from "reactive-lib/AbstractReactive.sol";

contract ArbShieldReactive is AbstractReactive {

    // Ethereum (1 or 11155111)
    uint256 public immutable ORIGIN_CHAIN_ID; 
    // Unichain (130 or 1301)  
    uint256 public immutable DEST_CHAIN_ID;     

    uint64 public constant CALLBACK_GAS_LIMIT = 300000;
    // V3 Swap event
    uint256 public constant V3_SWAP_TOPIC_0 = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67;
    // V4 Swap even
    uint256 public constant V4_SWAP_TOPIC_0 = uint256(keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"));
    // V3 Mint event
    uint256 public constant MINT_TOPIC_0 = 0x7a53080ba414158be7ec69b987b5fb7d07dee101fe85488f0853ae16239d0bde;
    // V3 Burn event: 
    uint256 public constant BURN_TOPIC_0 = uint256(keccak256("Burn(address,int24,int24,uint128,uint256,uint256)"));
    uint256 public constant DIVERGENCE_THRESHOLD_BPS = 10;
    // capture 80% of divergence
    uint256 public constant FEE_CAPTURE_PERCENT = 80;
    // 5.00%
    uint24 public constant MAX_FEE = 50000;
    // 5bp hysteresis — suppresses callbacks for small fee changes
    uint24 public constant FEE_CHANGE_THRESHOLD = 500;
    uint8 public constant MIN_DIVERGENCE_STREAK = 3;
    uint256 public constant MIN_LOYALTY_BLOCKS = 50_400;

    address public ethereumPool;
    address public unichainPool;
    address public callbackContract;
    uint256 public lastEthereumPrice;
    uint256 public lastUnichainPrice;
    uint24 public lastEmittedFee;
    uint8 public divergenceStreak;
    
    mapping(bytes32 => uint256) public positionEntryBlock;

    event PriceUpdated(uint256 chain, uint256 price);
    event DivergenceDetected(uint256 divergenceBps, uint24 newFee);
    event PricesConverged();
    event LPMintRecorded(address indexed lp, bytes32 indexed positionKey, uint256 blockNumber);
    event LPDurationQualified(address indexed lp, uint256 durationBlocks);

    constructor(
        address _ethereumPool,
        address _unichainPool,
        address _callbackContract,
        uint256 _originChainId,
        uint256 _destChainId
    ) payable {
        ethereumPool = _ethereumPool;
        unichainPool = _unichainPool;
        callbackContract = _callbackContract;
        ORIGIN_CHAIN_ID = _originChainId;
        DEST_CHAIN_ID = _destChainId;

        // Subscribe to events only when deployed on-chain
        if (!vm) {
            // Subscribe to Ethereum V3 pool swap events (V3 Swap topic)
            service.subscribe(
                _originChainId,
                _ethereumPool,
                V3_SWAP_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );

            // Subscribe to Unichain V4 PoolManager swap events (V4 Swap topic).
            service.subscribe(
                _destChainId,
                _unichainPool,
                V4_SWAP_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );

            // Subscribe to LP Mint events to record position entry blocks.
            service.subscribe(
                _originChainId,
                _ethereumPool,
                MINT_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );

            // Subscribe to LP Burn events to detect position exits and compute hold duration.
            service.subscribe(
                _originChainId,
                _ethereumPool,
                BURN_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == V3_SWAP_TOPIC_0 || log.topic_0 == V4_SWAP_TOPIC_0) {
            _handleSwap(log);
        } else if (log.topic_0 == MINT_TOPIC_0) {
            _handleLPMint(log);
        } else if (log.topic_0 == BURN_TOPIC_0) {
            _handleLPBurn(log);
        }
    }

    // handle swap events for price divergence tracking (works for both V3 and V4 events)
    function _handleSwap(LogRecord calldata log) internal {
        // Decode sqrtPriceX96 from event data using V3 layout (compatible with V4 — see NatSpec)
        (, , uint160 sqrtPriceX96, , ) = abi.decode(
            log.data,
            (int256, int256, uint160, uint128, int24)
        );

        uint256 price = sqrtPriceX96ToPrice(sqrtPriceX96);

        if (log.chain_id == ORIGIN_CHAIN_ID) {
            lastEthereumPrice = price;
            emit PriceUpdated(ORIGIN_CHAIN_ID, price);
        } else if (log.chain_id == DEST_CHAIN_ID) {
            lastUnichainPrice = price;
            emit PriceUpdated(DEST_CHAIN_ID, price);
        }

        // Check divergence and emit callback if needed
        if (lastEthereumPrice > 0 && lastUnichainPrice > 0) {
            _checkDivergenceAndEmitCallback();
        }
    }

    // record LP position entry block on Mint. Loyalty is NOT awarded here —
    function _handleLPMint(LogRecord calldata log) internal {
        address lp = address(uint160(log.topic_1));
        // Position key matches the Burn event's indexed fields for the same position.
        bytes32 posKey = keccak256(abi.encode(log.topic_1, log.topic_2, log.topic_3));
        // Only record on first mint — re-additions to an existing position extend from original entry.
        if (positionEntryBlock[posKey] == 0) {
            positionEntryBlock[posKey] = log.block_number;
            emit LPMintRecorded(lp, posKey, log.block_number);
        }
    }

    // award loyalty on LP exit if the position was held >= MIN_LOYALTY_BLOCKS.
    function _handleLPBurn(LogRecord calldata log) internal {
        bytes32 posKey = keccak256(abi.encode(log.topic_1, log.topic_2, log.topic_3));
        uint256 entryBlock = positionEntryBlock[posKey];
        if (entryBlock == 0) return; // no tracked entry — position pre-dates RSC deployment

        uint256 durationBlocks = log.block_number - entryBlock;
        if (durationBlocks < MIN_LOYALTY_BLOCKS) return; // held less than 7 days — no loyalty

        // Clear entry so a subsequent re-add starts a fresh timer.
        delete positionEntryBlock[posKey];

        address lp = address(uint160(log.topic_1));
        emit LPDurationQualified(lp, durationBlocks);

        // Reuse the existing recordLPActivity interface — LoyaltyRegistry and Callback unchanged.
        bytes memory payload = abi.encodeWithSignature(
            "recordLPActivity(address,address)",
            address(0), // replaced by Reactive Network with RVM ID
            lp
        );
        emit Callback(DEST_CHAIN_ID, callbackContract, CALLBACK_GAS_LIMIT, payload);
    }

    // convert sqrtPriceX96 to a comparable price value (overflow-safe)
    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 sqrtP = uint256(sqrtPriceX96);
        uint256 shifted = sqrtP >> 32;
        return (shifted * shifted) >> 128;
    }

    // calculate divergence and emit callback to update fees
    function _checkDivergenceAndEmitCallback() internal {
        uint256 priceA = lastEthereumPrice;
        uint256 priceB = lastUnichainPrice;

        uint256 diff = priceA > priceB ? priceA - priceB : priceB - priceA;
        uint256 maxPrice = priceA > priceB ? priceA : priceB;

        if (maxPrice == 0) return;

        uint256 divergenceBps = (diff * 10000) / maxPrice;

        if (divergenceBps < DIVERGENCE_THRESHOLD_BPS) {
            // Prices have converged — reset streak and base fee.
            divergenceStreak = 0;
            if (lastEmittedFee > 0) {
                lastEmittedFee = 0;
                emit PricesConverged();

                bytes memory payload = abi.encodeWithSignature(
                    "resetToBaseFee(address)",
                    address(0)
                );
                emit Callback(
                    DEST_CHAIN_ID,
                    callbackContract,
                    CALLBACK_GAS_LIMIT,
                    payload
                );
            }
        } else {
            // Divergence confirmed — increment streak.
            if (divergenceStreak < MIN_DIVERGENCE_STREAK) {
                divergenceStreak++;
                return; // not yet confirmed — wait for more signals
            }

            // Quadratic fee model: fee = divergenceBps² × 80 / 100, capped at MAX_FEE.
            uint256 rawFee = (divergenceBps * divergenceBps * FEE_CAPTURE_PERCENT) / 100;
            uint24 newFee = rawFee > uint256(MAX_FEE) ? MAX_FEE : uint24(rawFee);

            // Hysteresis: only emit if fee changed significantly (suppresses callback spam).
            uint24 feeDiff = newFee > lastEmittedFee
                ? newFee - lastEmittedFee
                : lastEmittedFee - newFee;

            if (feeDiff >= FEE_CHANGE_THRESHOLD) {
                lastEmittedFee = newFee;
                divergenceStreak = 0; // reset after successful emission
                emit DivergenceDetected(divergenceBps, newFee);

                bytes memory payload = abi.encodeWithSignature(
                    "updateDivergenceFee(address,uint24,uint256)",
                    address(0), // replaced by Reactive Network with RVM ID
                    newFee,
                    divergenceBps
                );
                emit Callback(
                    DEST_CHAIN_ID,
                    callbackContract,
                    CALLBACK_GAS_LIMIT,
                    payload
                );
            }
        }
    }
}

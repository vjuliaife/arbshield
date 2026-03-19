// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract LoyaltyRegistry {
    enum LoyaltyTier { NONE, BRONZE, SILVER, GOLD }
    event LPActivityRecorded(address indexed lp, uint256 count);
    event TierUpdated(address indexed lp, LoyaltyTier tier);
    event CallbackContractSet(address indexed callbackContract);
    event TierManuallySet(address indexed lp, LoyaltyTier tier);

    error OnlyOwner();
    error OnlyCallback();
    error CallbackAlreadySet();
    error ZeroAddress();

    mapping(address => uint256) public lpActivityCount;
    mapping(address => LoyaltyTier) public loyaltyTier;

    address public callbackContract;
    address public owner;
    uint256 public totalLoyaltyMembers;

    // Thresholds (number of LP events detected cross-chain)
    uint256 public constant BRONZE_THRESHOLD = 1;
    uint256 public constant SILVER_THRESHOLD = 5;
    uint256 public constant GOLD_THRESHOLD = 10;

    // Fee discounts per tier (percentage of effective fee, in BPS)
    // BRONZE: 10% off, SILVER: 20% off, GOLD: 30% off
    uint24 public constant BRONZE_DISCOUNT = 1000;
    uint24 public constant SILVER_DISCOUNT = 2000;
    uint24 public constant GOLD_DISCOUNT = 3000;

    // --- Modifiers ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyCallback() {
        if (msg.sender != callbackContract) revert OnlyCallback();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setCallbackContract(address _cb) external onlyOwner {
        if (_cb == address(0)) revert ZeroAddress();
        if (callbackContract != address(0)) revert CallbackAlreadySet();
        callbackContract = _cb;
        emit CallbackContractSet(_cb);
    }

    function recordLPActivity(address lp) external onlyCallback {
        lpActivityCount[lp]++;
        emit LPActivityRecorded(lp, lpActivityCount[lp]);
        _updateTier(lp);
    }
    function getFeeDiscount(address user) external view returns (uint24) {
        LoyaltyTier tier = loyaltyTier[user];
        if (tier == LoyaltyTier.GOLD) return GOLD_DISCOUNT;
        if (tier == LoyaltyTier.SILVER) return SILVER_DISCOUNT;
        if (tier == LoyaltyTier.BRONZE) return BRONZE_DISCOUNT;
        return 0;
    }

    function setTier(address user, LoyaltyTier tier) external onlyOwner {
        LoyaltyTier oldTier = loyaltyTier[user];
        if (oldTier == LoyaltyTier.NONE && tier != LoyaltyTier.NONE) {
            totalLoyaltyMembers++;
        } else if (oldTier != LoyaltyTier.NONE && tier == LoyaltyTier.NONE) {
            totalLoyaltyMembers--;
        }
        loyaltyTier[user] = tier;
        emit TierManuallySet(user, tier);
    }
    
    function _updateTier(address lp) internal {
        uint256 count = lpActivityCount[lp];
        LoyaltyTier oldTier = loyaltyTier[lp];
        LoyaltyTier newTier;

        if (count >= GOLD_THRESHOLD) {
            newTier = LoyaltyTier.GOLD;
        } else if (count >= SILVER_THRESHOLD) {
            newTier = LoyaltyTier.SILVER;
        } else if (count >= BRONZE_THRESHOLD) {
            newTier = LoyaltyTier.BRONZE;
        } else {
            newTier = LoyaltyTier.NONE;
        }

        if (newTier != oldTier) {
            if (oldTier == LoyaltyTier.NONE) {
                totalLoyaltyMembers++;
            }
            loyaltyTier[lp] = newTier;
            emit TierUpdated(lp, newTier);
        }
    }
}

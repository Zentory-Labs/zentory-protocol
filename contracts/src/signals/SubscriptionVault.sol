// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SubscriptionVault
/// @notice ERC-721 subscription NFT for ZENT signal network access.
///
///         How it works:
///         1. Subscriber calls subscribe(tierId, months) with ZENT approved
///         2. ZENT is transferred to treasury (operational revenue, not burned)
///         3. Contract mints an ERC-721 NFT representing the subscription
///         4. Subscription NFT has expiry; hasAccess() checks access on-chain
///         5. renewSubscription() charges another period; cancel() refunds prorated remainder
///
///         Tiers (configurable by governance):
///         - BASIC  (0): 100 ZENT/month  — crypto signals only
///         - PRO    (1): 500 ZENT/month  — crypto + equity signals
///         - ELITE  (2): 2000 ZENT/month — all asset classes + priority feed
contract SubscriptionVault {
    using SafeERC20 for IERC20;

    // ─── ERC-721 Metadata ─────────────────────────────────────
    string public constant name_ = "Zentory Signal Subscription";
    string public constant symbol_ = "ZENT-SUB";

    /// @notice Subscription info attached to each token.
    struct SubscriptionInfo {
        address  subscriber;
        uint8    assetClassBitmap; // Bit 0=CRYPTO_SPOT, 1=CRYPTO_PERP, 2=EQUITY, 3=FOREX, 4=COMMODITY
        uint32   duration;          // Total subscription length in seconds
        uint32   expiration;       // block.timestamp + duration
        uint96   pricePaid;        // ZENT amount paid (for proration calculation)
        uint256  tierId;           // Which tier was purchased
    }

    // ─── Tier Config ─────────────────────────────────────────
    struct Tier {
        uint256 monthlyPriceZENT;    // ZENT per 30 days
        uint8  assetClassBitmap;    // Which asset classes this tier covers
        uint32 minDuration;         // Minimum subscription in seconds
    }

    /// @notice Tier definitions keyed by tierId.
    mapping(uint256 => Tier) public tiers;

    /// @notice Subscription info keyed by ERC-721 token ID.
    mapping(uint256 => SubscriptionInfo) public subscriptionInfo;

    /// @notice All token IDs ever minted per subscriber (for enumeration).
    mapping(address => uint256[]) public subscriberTokens;

    // ERC-721 state
    uint256 public nextTokenId;
    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;

    // ─── Config ──────────────────────────────────────────────
    IERC20  public zentToken;
    address public treasury;
    uint256 public constant MONTH = 30 days;

    // ─── Events ─────────────────────────────────────────────
    event Subscribed(
        address indexed subscriber,
        uint256 indexed tokenId,
        uint256 tierId,
        uint32  duration,
        uint256 zentPaid
    );
    event RenewalPaid(uint256 indexed tokenId, uint256 zentPaid, uint32 newExpiration);
    event Cancelled(uint256 indexed tokenId, uint256 refundZENT, uint32 refundSeconds);

    // ERC-721 events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    // ─── Errors ─────────────────────────────────────────────
    error TierNotFound(uint256 tierId);
    error SubscriptionExpired(uint256 tokenId);
    error InsufficientZENT(uint256 required, uint256 available);
    error TransferFailed();
    error NotOwnerOfToken(uint256 tokenId);

    // ─── Constructor ────────────────────────────────────────
    constructor(address _zentToken, address _treasury) {
        if (_zentToken == address(0)) revert();
        if (_treasury == address(0)) revert();
        zentToken = IERC20(_zentToken);
        treasury  = _treasury;

        // Default tier definitions
        tiers[0] = Tier({
            monthlyPriceZENT: 100e18,
            assetClassBitmap: 0x01,  // CRYPTO_SPOT only
            minDuration:       uint32(MONTH)
        });
        tiers[1] = Tier({
            monthlyPriceZENT: 500e18,
            assetClassBitmap: 0x03,  // CRYPTO_SPOT + CRYPTO_PERP
            minDuration:       uint32(MONTH)
        });
        tiers[2] = Tier({
            monthlyPriceZENT: 2000e18,
            assetClassBitmap: 0x1F,  // All asset classes
            minDuration:       uint32(MONTH)
        });
    }

    // ─── Subscribe ──────────────────────────────────────────
    /// @notice Subscribe to a tier for a given number of months.
    /// @param tierId  0=BASIC, 1=PRO, 2=ELITE
    /// @param months  Number of monthly periods (1–12 recommended, no hard cap)
    /// @return tokenId The minted ERC-721 token ID representing this subscription
    function subscribe(uint256 tierId, uint32 months)
        external
        returns (uint256 tokenId)
    {
        Tier storage tier = tiers[tierId];
        if (tier.monthlyPriceZENT == 0) revert TierNotFound(tierId);

        uint256 totalCost = tier.monthlyPriceZENT * months;
        if (zentToken.balanceOf(msg.sender) < totalCost)
            revert InsufficientZENT(totalCost, zentToken.balanceOf(msg.sender));

        // Transfer ZENT to treasury (operational revenue — not burned)
        zentToken.safeTransferFrom(msg.sender, treasury, totalCost);

        tokenId = nextTokenId++;
        uint32 duration = uint32(MONTH) * months;
        uint32 expiration = uint32(block.timestamp) + duration;

        subscriptionInfo[tokenId] = SubscriptionInfo({
            subscriber:       msg.sender,
            assetClassBitmap: tier.assetClassBitmap,
            duration:         duration,
            expiration:       expiration,
            pricePaid:        uint96(totalCost),
            tierId:           tierId
        });

        _mint(msg.sender, tokenId);
        subscriberTokens[msg.sender].push(tokenId);

        emit Subscribed(msg.sender, tokenId, tierId, duration, totalCost);
    }

    // ─── Renew ─────────────────────────────────────────────
    /// @notice Renew an existing subscription for additional months.
    ///         Extends from the current expiration (not from now) to preserve continuity.
    /// @param tokenId Subscription NFT to renew
    /// @param months  Additional monthly periods
    /// @return newExpiration Updated expiration timestamp
    function renewSubscription(uint256 tokenId, uint32 months)
        external
        returns (uint32 newExpiration)
    {
        SubscriptionInfo storage sub = subscriptionInfo[tokenId];
        if (sub.subscriber != msg.sender) revert NotOwnerOfToken(tokenId);
        if (sub.expiration == 0) revert SubscriptionExpired(tokenId);

        Tier memory tier = _getTierForBitmap(sub.assetClassBitmap);
        uint256 cost = tier.monthlyPriceZENT * months;

        zentToken.safeTransferFrom(msg.sender, treasury, cost);

        // Extend from current expiry (or now if already expired) for continuity
        uint32 baseExpiry = sub.expiration < uint32(block.timestamp)
            ? uint32(block.timestamp)
            : sub.expiration;
        newExpiration = baseExpiry + uint32(MONTH) * months;
        sub.expiration = newExpiration;
        sub.duration  += uint32(MONTH) * months;

        emit RenewalPaid(tokenId, cost, newExpiration);
    }

    // ─── Cancel ─────────────────────────────────────────────
    /// @notice Cancel subscription and refund prorated ZENT.
    /// @param tokenId Subscription NFT to cancel
    /// @return refundZENT ZENT refunded to subscriber
    /// @dev Refund = (remaining seconds / total seconds) × pricePaid
    function cancelSubscription(uint256 tokenId) external returns (uint256 refundZENT) {
        SubscriptionInfo storage sub = subscriptionInfo[tokenId];
        if (sub.subscriber != msg.sender) revert NotOwnerOfToken(tokenId);

        uint32 remainingSeconds;
        if (sub.expiration > uint32(block.timestamp)) {
            remainingSeconds = sub.expiration - uint32(block.timestamp);
            uint256 totalSeconds = sub.duration;
            if (totalSeconds > 0) {
                refundZENT = (remainingSeconds * sub.pricePaid) / totalSeconds;
            }
        }

        if (refundZENT > 0) {
            zentToken.safeTransfer(sub.subscriber, refundZENT);
        }

        delete subscriptionInfo[tokenId];
        _burn(tokenId);

        emit Cancelled(tokenId, refundZENT, remainingSeconds);
    }

    // ─── Access Check ────────────────────────────────────────
    /// @notice Check if a wallet has active access to a given asset class.
    /// @param subscriber Wallet address
    /// @param assetClass SignalTypes.AssetClass enum value (0–4)
    /// @return hasAccess_ True if subscriber has an active subscription covering this class
    ///
    /// @dev This is the canonical gate used by SignalRegistry and other contracts:
    ///      require(subscriptionVault.hasAccess(msg.sender, assetClass), "Not subscribed");
    function hasAccess(address subscriber, uint8 assetClass)
        external view returns (bool hasAccess_)
    {
        uint256[] storage tokens = subscriberTokens[subscriber];
        uint256 bit = uint256(1) << assetClass;

        for (uint256 i = 0; i < tokens.length; i++) {
            SubscriptionInfo storage sub = subscriptionInfo[tokens[i]];
            if (sub.expiration > uint32(block.timestamp)) {
                if (_bitmapHas(sub.assetClassBitmap, bit)) return true;
            }
        }
        return false;
    }

    /// @notice Get all active subscription token IDs for a wallet.
    function getActiveSubscriptions(address subscriber)
        external view returns (uint256[] memory tokenIds)
    {
        uint256[] storage all = subscriberTokens[subscriber];
        uint256 count = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (subscriptionInfo[all[i]].expiration > block.timestamp) count++;
        }

        tokenIds = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (subscriptionInfo[all[i]].expiration > block.timestamp) {
                tokenIds[idx++] = all[i];
            }
        }
    }

    // ─── ERC-721 Stub ───────────────────────────────────────
    function name() external pure returns (string memory) { return name_; }
    function symbol() external pure returns (string memory) { return symbol_; }
    function tokenURI(uint256) external pure returns (string memory) { return ""; }

    /// @notice Returns the owner of tokenId.
    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "SubscriptionVault: invalid token");
        return owner;
    }

    /// @notice Balance of subscriber (number of subscription NFTs).
    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "SubscriptionVault: zero address");
        return _balanceOf[owner];
    }

    /// @notice Transfer subscription NFT to a new owner.
    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_ownerOf[tokenId] == from, "SubscriptionVault: not owner");
        require(to != address(0), "SubscriptionVault: zero address");
        _ownerOf[tokenId] = to;
        _balanceOf[from]--;
        _balanceOf[to]++;
        emit Transfer(from, to, tokenId);
    }

    // ─── Internal ───────────────────────────────────────────
    /// @notice Check whether a bitmap includes a given bit.
    function _bitmapHas(uint8 bitmap, uint256 bit) internal pure returns (bool) {
        return (bitmap & uint8(bit)) != 0;
    }

    /// @notice Return the highest tier that matches the given asset class bitmap.
    function _getTierForBitmap(uint8 bitmap) internal view returns (Tier memory tier) {
        for (uint256 i = 2; i >= 0; i--) {
            if (uint8(uint256(tiers[i].assetClassBitmap) & bitmap) != 0) {
                return tiers[i];
            }
        }
        return tiers[0];
    }

    /// @notice ERC-721 mint — assigns ownership and increments balance.
    function _mint(address to, uint256 tokenId) internal {
        _ownerOf[tokenId] = to;
        _balanceOf[to]++;
        emit Transfer(address(0), to, tokenId);
    }

    /// @notice ERC-721 burn — clears ownership and decrements balance.
    function _burn(uint256 tokenId) internal {
        address owner = _ownerOf[tokenId];
        delete _ownerOf[tokenId];
        _balanceOf[owner]--;
        emit Transfer(owner, address(0), tokenId);
    }
}

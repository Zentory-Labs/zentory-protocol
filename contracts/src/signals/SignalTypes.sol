// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SignalTypes
/// @notice Shared types, enums, and events for the multi-asset signal network.
///         Defines the canonical signal format across crypto, equities, forex, and commodities.
library SignalTypes {
    // ─── Asset Class Registry ────────────────────────────────
    enum AssetClass {
        CRYPTO_SPOT,  // 0 — e.g. BTC, ETH on-chain spot
        CRYPTO_PERP,  // 1 — e.g. BTC-PERP on Hyperliquid
        EQUITY,       // 2 — e.g. AAPL, TSLA tokenized on Ondo/Synthetix
        FOREX,        // 3 — e.g. EUR/USD, USD/JPY
        COMMODITY     // 4 — e.g. GOLD, WTI crude
    }

    // ─── Signal Status ──────────────────────────────────────
    enum SignalStatus {
        Submitted,  // Logged, awaiting scoring
        Active,     // Within scoring window, not yet resolved
        Resolved,   // Scored and finalized
        Challenged, // Optimistic challenge window open
        Slashed     // Signal penalized
    }

    // ─── Core Signal ────────────────────────────────────────
    struct Signal {
        bytes32      signalId;
        address      provider;
        AssetClass   assetClass;
        bytes32      assetId;
        int256       direction;     // Normalized: -10000 (strong sell) to +10000 (strong buy)
        uint256      confidence;     // 0–10000 — weight in stake-weighted aggregation
        uint256      submittedAt;
        uint256      expiresAt;
        bytes        signature;     // EIP-191 ECDSA signature from provider's wallet
        SignalStatus status;
    }

    // ─── Epoch Record ───────────────────────────────────────
    struct Epoch {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        bool    settled;
    }

    // ─── Provider Stats ─────────────────────────────────────
    struct ProviderStats {
        uint256 totalSignals;
        uint256 resolvedSignals;
        uint256 totalAccuracy;  // Basis points (10000 = perfect)
        uint256 currentStake;
        uint256 rank;
        uint256 lastSignalTimestamp;
    }

    // ─── Events ─────────────────────────────────────────────
    event SignalSubmitted(
        bytes32          indexed signalId,
        address          indexed provider,
        AssetClass indexed assetClass,
        bytes32          assetId,
        int256           direction,
        uint256          confidence,
        uint256          expiresAt
    );

    event SignalScored(
        bytes32  indexed signalId,
        address  indexed provider,
        uint256  accuracyBps,  // basis points, 10000 = perfect
        int256   payout        // negative = slash, positive = reward
    );

    event EpochStarted(uint256 indexed epochId, uint256 startTime, uint256 endTime);
    event EpochSettled(uint256 indexed epochId, uint256 totalSignals, uint256 totalProviders);

    // ─── Canonical Asset ID Helpers ─────────────────────────
    /// @notice Generate a canonical on-chain asset ID for a crypto symbol.
    function cryptoId(string memory symbol) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("CRYPTO:", symbol));
    }

    /// @notice Generate a canonical on-chain asset ID for an equity symbol.
    function equityId(string memory symbol) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("EQUITY:", symbol));
    }

    /// @notice Generate a canonical on-chain asset ID for a forex pair.
    function forexId(string memory pair) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("FOREX:", pair));
    }

    /// @notice Generate a canonical on-chain asset ID for a commodity name.
    function commodityId(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("COMMODITY:", name));
    }
}

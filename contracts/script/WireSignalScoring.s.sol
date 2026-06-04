// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

/// @title WireSignalScoring
/// @notice One admin txn to activate on-chain signal scoring: point EpochScoring's
///         reference-asset price feed at the (Chainlink-compatible) ShadowPriceOracle.
///         Until this is set, `priceFeeds[referenceAssetId]` is address(0), so
///         `_snapshotReferenceClose` no-ops, `epochClosePrice` stays 0, price
///         movement is 0, and every signal scores neutral. After wiring, each
///         epoch settlement snapshots the BTC close; real accuracy scoring begins
///         once two consecutive snapshots exist (one-epoch warm-up).
///
///         Scoring uses a SINGLE referenceAssetId (BTC) for the whole epoch — a
///         signal's own assetId is metadata, not separately priced. Multi-asset
///         per-signal scoring would require a contract change; noted for mainnet.
///
/// Run by the EpochScoring DEFAULT_ADMIN_ROLE holder (the signal-deploy key in
/// contracts/.env). Idempotent: no-ops if already wired.
contract WireSignalScoring is Script {
    function run() external {
        require(block.chainid == 998, "WireSignalScoring: not HyperEVM testnet (998)");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address epoch  = vm.envOr("EPOCH_SCORING", address(0x659569A6f195698745779E59fef88e3B5Fe0484A));
        address oracle = vm.envOr("ORACLE",        address(0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4));

        IEpochScoringAdmin es = IEpochScoringAdmin(epoch);
        bytes32 refId = es.referenceAssetId();
        address cur = es.priceFeeds(refId);

        console2.log("EpochScoring:", epoch);
        console2.log("referenceAssetId:");
        console2.logBytes32(refId);
        console2.log("current feed:", cur);
        console2.log("target feed (ShadowPriceOracle):", oracle);

        if (cur == oracle) {
            console2.log("== already wired - no-op ==");
            return;
        }

        vm.startBroadcast(pk);
        es.setPriceFeed(refId, oracle);
        vm.stopBroadcast();

        console2.log("== Done == priceFeeds[referenceAssetId] now:", es.priceFeeds(refId));
        console2.log("On-chain scoring active. Real accuracy begins after 2 consecutive epoch snapshots (~one epoch warm-up).");
    }
}

interface IEpochScoringAdmin {
    function referenceAssetId() external view returns (bytes32);
    function priceFeeds(bytes32) external view returns (address);
    function setPriceFeed(bytes32 assetId, address feed) external;
}

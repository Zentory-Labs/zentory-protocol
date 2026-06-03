// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {SignalRegistry} from "../src/signals/SignalRegistry.sol";
import {EpochScoring} from "../src/signals/EpochScoring.sol";

/// @title RedeploySignalStack
/// @notice Fresh redeploy of the signal scoring stack (ZENTStaking + SignalRegistry
///         + EpochScoring) from CURRENT source, with all roles + the BTC price feed
///         wired in one broadcast. Fixes three latent bugs at once:
///
///           1. STALE ZENTSTAKING (the blocker). The live staking 0x4E2e7Fd3… is
///              2026-04-27 bytecode whose getProviderStake REVERTS for any unstaked
///              address. settleEpoch's totalStake loop calls it unguarded, so the
///              keeper bricks on the first non-empty epoch. Current source returns
///              0 safely. EpochScoring.zentStaking is immutable (no setter), so the
///              staking can only be swapped by redeploying EpochScoring too.
///           2. EPOCH OFF-BY-ONE. SignalRegistry now inits currentEpochId = 1, equal
///              to EpochScoring, so a fresh pair is aligned from genesis (no re-sync).
///           3. ROLE HYGIENE. The deployer's bootstrap SCORING_ORACLE is revoked
///              after wiring (least privilege).
///
///         KEEPS the existing SubscriptionVault, ZENT token, and vaults (independent
///         of the scoring stack — no need to redeploy or re-point them).
///
///         Run by the deployer (holds the keys + becomes staking governor):
///           forge script script/RedeploySignalStack.s.sol \
///             --rpc-url $RPC --broadcast
///         Required env: PRIVATE_KEY. Optional (defaults to the live testnet values):
///           ZENT_ADDRESS, KEEPER_ADDRESS, BTC_FEED, MIN_STAKE.
contract RedeploySignalStack is Script {
    // Live testnet defaults (HyperEVM 998).
    address constant DEFAULT_ZENT   = 0x271cd48c1297CacCD810c7B1BCD904f459df7117;
    address constant DEFAULT_KEEPER = 0x2251F2D8541f5D5263316E2921611c74D6d30D94;
    address constant DEFAULT_FEED   = 0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4; // BTC/USD, 8 dp
    uint256 constant DEFAULT_MIN_STAKE = 100e18;

    function run() external {
        require(block.chainid == 998, "RedeploySignalStack: not HyperEVM testnet (998)");

        uint256 pk       = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address zent     = vm.envOr("ZENT_ADDRESS", DEFAULT_ZENT);
        address keeper   = vm.envOr("KEEPER_ADDRESS", DEFAULT_KEEPER);
        address btcFeed  = vm.envOr("BTC_FEED", DEFAULT_FEED);
        uint256 minStake = vm.envOr("MIN_STAKE", DEFAULT_MIN_STAKE);

        console2.log("Deployer (governor):", deployer);
        console2.log("Keeper:", keeper);
        console2.log("ZENT:", zent);
        console2.log("BTC feed:", btcFeed);

        vm.startBroadcast(pk);

        // 1. Fresh ZENTStaking — deployer is governor (DEFAULT_ADMIN_ROLE +
        //    GOVERNOR_ROLE) so it can grant GOVERNOR_ROLE to EpochScoring below.
        //    Current source's getProviderStake returns 0 for unstaked providers
        //    (no revert) — the fix for the keeper-bricking blocker.
        ZENTStaking staking = new ZENTStaking(zent, deployer, minStake);
        console2.log("ZENTStaking:", address(staking));

        // 2. Fresh SignalRegistry — deployer is the bootstrap scoringOracle.
        //    Inits currentEpochId = 1 (source fix), aligned with EpochScoring.
        SignalRegistry registry = new SignalRegistry(address(staking), deployer);
        console2.log("SignalRegistry:", address(registry));

        // 3. Fresh EpochScoring — keeper is scoringOracle + EPOCH_SETTLER.
        //    Inits currentEpochId = 1, equal to the registry above.
        EpochScoring scoring = new EpochScoring(
            address(registry), address(staking), zent, keeper, keeper
        );
        console2.log("EpochScoring:", address(scoring));

        // 4. ROLE WIRING
        // 4a. EpochScoring CONTRACT must hold SCORING_ORACLE on the registry so
        //     settleEpoch can call advanceEpoch()/resolveSignals().
        registry.grantRole(registry.SCORING_ORACLE(), address(scoring));
        // 4b. Keeper SCORING_ORACLE (defensive) + EPOCH_SETTLER on EpochScoring.
        registry.grantRole(registry.SCORING_ORACLE(), keeper);
        scoring.grantRole(scoring.EPOCH_SETTLER(), keeper);
        // 4c. EpochScoring must hold GOVERNOR_ROLE on the staking so reward()/slash()
        //     succeed during settlement/payout (onlyRole(GOVERNOR_ROLE)).
        staking.grantRole(staking.GOVERNOR_ROLE(), address(scoring));
        // 4d. Re-register the BTC price feed (the live EpochScoring had this; a fresh
        //     one starts with priceFeeds empty → _snapshotReferenceClose no-ops →
        //     accuracy scored against a zero price. referenceAssetId == keccak("BTC").
        scoring.setPriceFeed(scoring.referenceAssetId(), btcFeed);
        // 4e. Least privilege: drop the deployer's bootstrap SCORING_ORACLE (guarded
        //     so the keeper's grant survives if deployer == keeper).
        if (deployer != keeper) {
            registry.revokeRole(registry.SCORING_ORACLE(), deployer);
        }

        vm.stopBroadcast();

        // ── Post-deploy assertions (revert the script if any wiring is wrong) ──
        require(registry.currentEpochId() == scoring.currentEpochId(), "epoch counters not aligned");
        require(registry.currentEpochId() == 1, "registry not at genesis epoch 1");
        require(registry.hasRole(registry.SCORING_ORACLE(), address(scoring)), "scoring missing SCORING_ORACLE");
        require(scoring.hasRole(scoring.EPOCH_SETTLER(), keeper), "keeper missing EPOCH_SETTLER");
        require(staking.hasRole(staking.GOVERNOR_ROLE(), address(scoring)), "scoring missing GOVERNOR_ROLE on staking");
        require(scoring.priceFeeds(scoring.referenceAssetId()) == btcFeed, "BTC feed not set");
        require(staking.getProviderStake(deployer) == 0, "staking getProviderStake should return 0, not revert");
        if (deployer != keeper) {
            require(!registry.hasRole(registry.SCORING_ORACLE(), deployer), "deployer bootstrap role not revoked");
        }

        console2.log("");
        console2.log("=== SIGNAL STACK REDEPLOYED (all wiring verified) ===");
        console2.log("ZENT_STAKING=", address(staking));
        console2.log("SIGNAL_REGISTRY=", address(registry));
        console2.log("EPOCH_SCORING=", address(scoring));
        console2.log("(SubscriptionVault + ZENT + vaults unchanged)");
        console2.log("");
        console2.log("NEXT: re-point these to the 3 new addresses, then redeploy the keeper:");
        console2.log(" - Railway keeper env: SIGNAL_REGISTRY_ADDRESS, EPOCH_SCORING_ADDRESS");
        console2.log(" - Engine .env: SIGNAL_REGISTRY_ADDRESS (submitter/seed/indexer)");
        console2.log(" - dApp lib/contracts.ts: SignalRegistry, EpochScoring, ZENTStaking");
        console2.log(" - DEPLOYMENTS.md / STATE.md / memory");
    }
}

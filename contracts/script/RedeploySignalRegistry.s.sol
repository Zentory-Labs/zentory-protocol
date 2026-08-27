// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {SignalRegistry} from "../src/signals/SignalRegistry.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @title  RedeploySignalRegistry
/// @notice Fresh redeploy of `SignalRegistry.sol` only (single-contract redeploy).
///         Designed for the case where the live SignalRegistry is stale bytecode that
///         lacks selectors present in the current source (the M2-F13 audit-readiness
///         gap). Keeps the existing ZENTStaking and EpochScoring in place — they were
///         hardened in the prior `RedeploySignalStack.s.sol` (2026-06-04) and are still
///         wired against each other.
///
///         Why a single-contract redeploy (instead of the full stack)?
///           * ZENTStaking at 0x93A14D1c… is fine: `getProviderStake` returns 0
///             safely (no revert), `currentEpochId` aligned at ~410.
///           * EpochScoring at 0x659569A6… is fine: `currentEpochId` aligned,
///             BTC price feed wired, keeper holds EPOCH_SETTLER.
///           * SignalRegistry at 0xA71cfdA7… is the suspect — its bytecode is
///             8,858 B vs the current source's 10,487 B (Δ = 1,629 B of
///             un-shipped source: _hashTypedDataV4 override, signalProvider/
///             getEpochSignalProvider/Return views, transferAdmin, MAX_BATCH_SIZE
///             guard, etc.). At the older deployment referenced in
///             `services.yaml` (0x7745B22B…, a parallel stale stack with no
///             `getSignalCount` / `SCORING_ORACLE` / `signalIds(uint256)`
///             selectors), the view calls revert outright.
///
///         Wiring performed by this script (one broadcast):
///           1. Deploy fresh `SignalRegistry(staking, deployer)`.
///              Constructor grants `DEFAULT_ADMIN_ROLE` to deployer and
///              `SCORING_ORACLE` to deployer (bootstrap; revoked below).
///           2. `grantRole(SCORING_ORACLE(), existingEpochScoring)` — so the
///              EpochScoring contract can call `advanceEpoch()` / `resolveSignals()`
///              from inside `settleEpoch()` (audit-finding C-2 / M-4 fix).
///           3. `revokeRole(SCORING_ORACLE(), deployer)` — least-privilege:
///              drop the bootstrap grant once the contract-level grant is in place
///              (prevents the deployer EOA from advancing the epoch counter
///              out-of-band and desyncing from EpochScoring — the off-by-one that
///              silently disabled scoring on the 2026-06 testnet deploy).
///
///         Epoch alignment: the new SignalRegistry starts at `currentEpochId = 1`
///         (source-fixed genesis), while the existing EpochScoring is at ~410.
///         Both advance in lockstep because `settleEpoch()` increments EpochScoring
///         and then calls `SignalRegistry.advanceEpoch()`. After ~410 settleEpoch
///         calls (~4h apart ≈ ~68 days at 4h cadence), they realign. Signals
///         submitted during the catch-up window land in low epochIds on the new
///         registry but are still scored correctly once alignment recovers.
///
///         Run by the deployer (holds PRIVATE_KEY, becomes admin):
///           PRIVATE_KEY=0x... forge script script/RedeploySignalRegistry.s.sol \
///             --rpc-url $RPC --broadcast
///         Required env: PRIVATE_KEY, EXPECTED_CHAIN_ID=998.
///         Optional (defaults to the live testnet values):
///           STAKING_ADDRESS, EPOCH_SCORING_ADDRESS.
contract RedeploySignalRegistry is Script {
    // Live testnet defaults (HyperEVM 998).
    address internal constant DEFAULT_STAKING        = 0x93A14D1c60e054038980965CF3CAa50CEB848de9;
    address internal constant DEFAULT_EPOCH_SCORING  = 0x659569A6f195698745779E59fef88e3B5Fe0484A;

    /// @notice Known-bad staking address (the 2026-04-27 deploy whose
    ///         getProviderStake reverts for any unstaked provider). The
    ///         founder's local `.env` may still hold this address; this
    ///         script refuses to redeploy a SignalRegistry pointed at it,
    ///         because doing so would resurrect the epoch-bricking bug the
    ///         2026-06-04 RedeploySignalStack fixed.
    address internal constant KNOWN_BAD_STAKING      = 0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65;

    function run() external {
        requireChainFromEnv(); // F-05

        uint256 pk            = vm.envUint("PRIVATE_KEY");
        address deployer      = vm.addr(pk);
        address staking       = vm.envOr("STAKING_ADDRESS", DEFAULT_STAKING);
        address epochScoring  = vm.envOr("EPOCH_SCORING_ADDRESS", DEFAULT_EPOCH_SCORING);

        // Safety: refuse to point a fresh SignalRegistry at the known-bad
        // 2026-04-27 ZENTStaking (getProviderStake reverts). The founder's
        // local `.env` may still hold this address; explicit override via
        // STAKING_ADDRESS=<0x4E2e7Fd3…> would silently resurrect the
        // epoch-bricking bug the 2026-06-04 RedeploySignalStack fixed.
        require(
            staking != KNOWN_BAD_STAKING,
            "RedeploySignalRegistry: STAKING_ADDRESS is the known-bad 0x4E2e7Fd3 (getProviderStake reverts). Update .env / env var to 0x93A14D1c (the 2026-06-04 redeploy)."
        );

        console2.log("Chain:                ", block.chainid);
        console2.log("Deployer (admin):     ", deployer);
        console2.log("Existing ZENTStaking: ", staking);
        console2.log("Existing EpochScoring:", epochScoring);

        vm.startBroadcast(pk);

        // 1. Deploy fresh SignalRegistry with deployer as bootstrap scoringOracle.
        //    currentEpochId is hardcoded to 1 in the constructor (source-fixed
        //    genesis, aligned with EpochScoring's constructor default).
        SignalRegistry registry = new SignalRegistry(staking, deployer);
        console2.log("New SignalRegistry:   ", address(registry));

        // 2. Wire SCORING_ORACLE on the new registry to the EXISTING EpochScoring
        //    contract so settleEpoch can call advanceEpoch() / resolveSignals().
        registry.grantRole(registry.SCORING_ORACLE(), epochScoring);
        console2.log("Granted SCORING_ORACLE -> EpochScoring ", epochScoring);

        // 3. Drop the deployer's bootstrap SCORING_ORACLE (least privilege).
        //    Guarded on deployer != epochScoring for safety (impossible in practice
        //    because epochScoring is a deployed contract, but explicit is cheap).
        if (deployer != epochScoring) {
            registry.revokeRole(registry.SCORING_ORACLE(), deployer);
            console2.log("Revoked bootstrap SCORING_ORACLE from deployer");
        }

        vm.stopBroadcast();

        // ── Post-deploy assertions (revert the script if any wiring is wrong) ──
        require(registry.stakingContract() == staking, "staking not set");
        require(registry.hasRole(registry.SCORING_ORACLE(), epochScoring), "EpochScoring missing SCORING_ORACLE");
        require(!registry.hasRole(registry.SCORING_ORACLE(), deployer), "deployer bootstrap not revoked");
        require(registry.currentEpochId() == 1, "registry not at genesis epoch 1");

        console2.log("");
        console2.log("=== SIGNAL REGISTRY REDEPLOYED (wiring verified) ===");
        console2.log("SIGNAL_REGISTRY=", address(registry));
        console2.log("");
        console2.log("NEXT: re-point these to the new address, then redeploy the engine indexer:");
        console2.log(" - zentory-engine .env (Railway): SIGNAL_REGISTRY_ADDRESS (submitter / indexer / seed)");
        console2.log(" - zentory-app lib/contracts.ts: addresses.SignalRegistry");
        console2.log(" - DEPLOYMENTS.md: Signal Arena section");
        console2.log(" - Engine indexer: reset last_block in indexer_state to the new deploy block");
        console2.log("");
        console2.log("EPOCH REALIGNMENT: new registry starts at epoch 1; existing EpochScoring is");
        console2.log("at ~410. Both advance in lockstep via settleEpoch() (every 4h). They will");
        console2.log("realign within ~410 epochs (~68 days). Signals submitted during the catch-up");
        console2.log("window are bucketed at low epochIds but are otherwise unaffected.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {SignalRegistry} from "../src/signals/SignalRegistry.sol";
import {EpochScoring} from "../src/signals/EpochScoring.sol";
import {SubscriptionVault} from "../src/signals/SubscriptionVault.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys the full ZentoryToken signal network contracts and wires
///         the cross-contract roles required for the keeper loop to run.
///
/// Required env vars:
///   PRIVATE_KEY       — deployer's private key
///   ZENT_ADDRESS      — deployed ZENT token address
///   STAKING_ADDRESS   — deployed ZENTStaking address
/// Optional:
///   KEEPER_ADDRESS    — keeper bot wallet that grades + settles epochs.
///                       Defaults to the deployer if unset. On testnet this
///                       is 0x2251F2D8541f5D5263316E2921611c74D6d30D94.
///
/// Run:
///   forge script script/deploy_signal_network.s.sol \
///     --rpc-url $RPC \
///     --private-key $PRIVATE_KEY \
///     --broadcast
///
/// @dev WHY THE ROLE GRANTS MATTER (this is the bug that stalled the live loop):
///      EpochScoring.settleEpoch() calls SignalRegistry.advanceEpoch() and
///      resolveSignals(), both gated by SignalRegistry's SCORING_ORACLE role.
///      The CALLER there is the EpochScoring *contract*, so the EpochScoring
///      address — not the deployer EOA — must hold SCORING_ORACLE on the
///      registry. The previous script only granted it to the deployer, so
///      settleEpoch reverted on AccessControl. We grant it explicitly below.
///      Likewise the keeper bot wallet needs EPOCH_SETTLER on EpochScoring.
contract DeploySignalNetwork is Script {
    function run() external {
        requireChainFromEnv(); // F-05
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address keeper = vm.envOr("KEEPER_ADDRESS", deployer);

        ZENT      zent    = ZENT(payable(vm.envAddress("ZENT_ADDRESS")));
        ZENTStaking staking = ZENTStaking(vm.envAddress("STAKING_ADDRESS"));

        console2.log("Deployer:", deployer);
        console2.log("Keeper:  ", keeper);
        console2.log("Chain:", block.chainid);
        console2.log("ZENT:", address(zent));
        console2.log("ZENTStaking:", address(staking));

        vm.startBroadcast(deployerKey);

        // 1. SignalRegistry — deployer is the initial scoringOracle so it can
        //    bootstrap; we then ALSO grant SCORING_ORACLE to the EpochScoring
        //    contract below (required for advanceEpoch/resolveSignals).
        SignalRegistry signalRegistry = new SignalRegistry(address(staking), deployer);
        console2.log("SignalRegistry deployed:", address(signalRegistry));

        // 2. EpochScoring — keeper is both the scoring oracle (grades signals
        //    via setAccuracy) and the EPOCH_SETTLER (calls settleEpoch).
        EpochScoring scoring = new EpochScoring(
            address(signalRegistry),
            address(staking),
            address(zent),
            keeper, // scoringOracle = keeper bot
            keeper  // EPOCH_SETTLER = keeper bot
        );
        console2.log("EpochScoring deployed:", address(scoring));

        // 3. SubscriptionVault
        SubscriptionVault subscriptionVault = new SubscriptionVault(
            address(zent),
            deployer  // treasury = deployer initially; governance can reassign
        );
        console2.log("SubscriptionVault deployed:", address(subscriptionVault));

        // 4. CROSS-CONTRACT ROLE WIRING (the part the old script missed).
        // 4a. EpochScoring contract must hold SCORING_ORACLE on the registry
        //     so settleEpoch can call advanceEpoch() + resolveSignals().
        signalRegistry.grantRole(signalRegistry.SCORING_ORACLE(), address(scoring));
        // 4b. Keeper wallet also holds SCORING_ORACLE on the registry if it
        //     needs to write returns directly (defensive; harmless if unused).
        signalRegistry.grantRole(signalRegistry.SCORING_ORACLE(), keeper);
        // 4c. Ensure the keeper holds EPOCH_SETTLER on EpochScoring (already
        //     granted via constructor when keeper == 5th arg, but explicit is
        //     safe and covers the keeper != deployer case).
        scoring.grantRole(scoring.EPOCH_SETTLER(), keeper);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SIGNAL NETWORK DEPLOYED ===");
        console2.log("SIGNAL_REGISTRY=", address(signalRegistry));
        console2.log("EPOCH_SCORING=", address(scoring));
        console2.log("SUBSCRIPTION_VAULT=", address(subscriptionVault));
        console2.log("");
        console2.log("Post-deploy: update zentory-app/lib/contracts.ts +");
        console2.log("the Railway keeper EPOCH_SCORING_ADDRESS to the new EpochScoring.");
    }
}

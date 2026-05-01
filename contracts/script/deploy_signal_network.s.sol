// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {SignalRegistry} from "../src/signals/SignalRegistry.sol";
import {EpochScoring} from "../src/signals/EpochScoring.sol";
import {SubscriptionVault} from "../src/signals/SubscriptionVault.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";

/// @notice Deploys the full ZentoryToken signal network contracts.
///
/// Required env vars:
///   PRIVATE_KEY       — deployer's private key
///   ZENT_ADDRESS      — deployed ZENT token address
///   STAKING_ADDRESS   — deployed ZENTStaking address
///
/// Run:
///   forge script script/deploy_signal_network.s.sol \
///     --rpc-url $RPC \
///     --private-key $PRIVATE_KEY \
///     --broadcast
contract DeploySignalNetwork is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        ZENT      zent    = ZENT(payable(vm.envAddress("ZENT_ADDRESS")));
        ZENTStaking staking = ZENTStaking(vm.envAddress("STAKING_ADDRESS"));

        console2.log("Deployer:", deployer);
        console2.log("Chain:", block.chainid);
        console2.log("ZENT:", address(zent));
        console2.log("ZENTStaking:", address(staking));

        vm.startBroadcast(deployerKey);

        // 1. SignalRegistry
        SignalRegistry signalRegistry = new SignalRegistry(address(staking), deployer);
        console2.log("SignalRegistry deployed:", address(signalRegistry));

        // 2. EpochScoring
        EpochScoring scoring = new EpochScoring(
            address(signalRegistry),
            address(staking),
            address(zent),
            deployer, // initial scoringOracle; governance can update via setScoringOracle
            deployer  // initial keeper (EPOCH_SETTLER); governance can grant to keeper bot
        );
        console2.log("EpochScoring deployed:", address(scoring));

        // 3. SubscriptionVault
        SubscriptionVault subscriptionVault = new SubscriptionVault(
            address(zent),
            deployer  // treasury = deployer initially; governance can reassign
        );
        console2.log("SubscriptionVault deployed:", address(subscriptionVault));

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SIGNAL NETWORK DEPLOYED ===");
        console2.log("SIGNAL_REGISTRY=", address(signalRegistry));
        console2.log("EPOCH_SCORING=", address(scoring));
        console2.log("SUBSCRIPTION_VAULT=", address(subscriptionVault));
    }
}

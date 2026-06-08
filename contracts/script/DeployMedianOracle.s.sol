// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MedianOracle} from "../src/oracle/MedianOracle.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys the production `MedianOracle` (multi-signer median NAV feed) and
///         registers its initial updater set in one broadcast. Pass the resulting
///         address as `ORACLE` to `DeploySpotStack`.
///
/// Required env:
///   EXPECTED_CHAIN_ID, PRIVATE_KEY,
///   ORACLE_UPDATERS  — comma-separated updater addresses (the independent keeper
///                      keys that will `report` prices; need >= ORACLE_MIN_QUORUM).
/// Optional env (defaults shown):
///   ORACLE_DECIMALS (8), ORACLE_MAX_STALENESS (3600 — match the keeper cadence),
///   ORACLE_MIN_ANSWER (1e8 = $1, 8dec), ORACLE_MAX_ANSWER (1e15 = $10M, 8dec),
///   ORACLE_MIN_QUORUM (2)
///
/// Run:
///   ORACLE_UPDATERS=0xaaa...,0xbbb...,0xccc... \
///   forge script script/DeployMedianOracle.s.sol --rpc-url $RPC --broadcast
///
/// @dev Set sane per-asset [min,max] bounds for the vault's underlying (e.g. tighter
///      bounds for a BTC/USD feed). Admin defaults to the deployer; transfer
///      DEFAULT_ADMIN_ROLE to the Safe alongside the rest of the stack.
contract DeployMedianOracle is Script {
    function run() external {
        requireChainFromEnv();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address[] memory updaters = vm.envAddress("ORACLE_UPDATERS", ",");
        require(updaters.length > 0, "no updaters");

        uint8 dec = uint8(vm.envOr("ORACLE_DECIMALS", uint256(8)));
        uint256 maxStale = vm.envOr("ORACLE_MAX_STALENESS", uint256(3600));
        int256 minAns = vm.envOr("ORACLE_MIN_ANSWER", int256(1e8));          // $1
        int256 maxAns = vm.envOr("ORACLE_MAX_ANSWER", int256(1e15));         // $10,000,000
        uint256 minQuorum = vm.envOr("ORACLE_MIN_QUORUM", uint256(2));
        require(updaters.length >= minQuorum, "updaters < quorum");

        console2.log("Deployer:    ", deployer);
        console2.log("Decimals:    ", uint256(dec));
        console2.log("MaxStaleness:", maxStale);
        console2.log("MinQuorum:   ", minQuorum);
        console2.log("Updaters:    ", updaters.length);
        console2.log("Chain:       ", block.chainid);

        vm.startBroadcast(deployerKey);

        MedianOracle oracle = new MedianOracle(dec, maxStale, minAns, maxAns, minQuorum, deployer);
        for (uint256 i = 0; i < updaters.length; i++) {
            oracle.addUpdater(updaters[i]);
        }

        vm.stopBroadcast();

        require(oracle.updaterCount() == updaters.length, "updater wiring mismatch");

        console2.log("");
        console2.log("=== MEDIAN ORACLE DEPLOYED ===");
        console2.log("ORACLE=", address(oracle));
        console2.log("NEXT: pass ORACLE=<above> to DeploySpotStack; have each updater");
        console2.log("key call oracle.report(price) on the keeper cadence; transfer");
        console2.log("DEFAULT_ADMIN_ROLE to the Safe.");
    }
}

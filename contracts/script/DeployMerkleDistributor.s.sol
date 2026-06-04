// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MerkleDistributor} from "../src/airdrop/MerkleDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys the airdrop MerkleDistributor (M9). No deploy script existed
///         for it before. Chain-parameterized via ChainGuard (testnet 998 AND
///         mainnet — no hardcoded chain id).
///
/// Required env:
///   PRIVATE_KEY      — deployer
///   EXPECTED_CHAIN_ID
///   MERKLE_ROOT      — bytes32 root from scripts/airdrop/snapshot.ts
///   CLAIM_DEADLINE   — unix ts after which unclaimed tokens can be swept
///   AIRDROP_ADMIN    — DEFAULT_ADMIN_ROLE + SWEEPER_ROLE holder; MUST be the
///                      Gnosis Safe on mainnet (the contract is built for a multisig)
/// Optional:
///   ZENT_ADDRESS     — defaults to canonical ZENT
///   AIRDROP_FUND     — "true" to transfer AIRDROP_TOTAL from the deployer into the
///                      distributor in the same broadcast (asserts funded balance)
///   AIRDROP_TOTAL    — exact token amount to fund (sum of all leaf amounts)
///
///   forge script script/DeployMerkleDistributor.s.sol --rpc-url $RPC --broadcast
contract DeployMerkleDistributor is Script {
    address constant DEFAULT_ZENT = 0x271cd48c1297CacCD810c7B1BCD904f459df7117;

    function run() external {
        requireChainFromEnv();
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address zent = vm.envOr("ZENT_ADDRESS", DEFAULT_ZENT);
        bytes32 root = vm.envBytes32("MERKLE_ROOT");
        uint256 deadline = vm.envUint("CLAIM_DEADLINE");
        address admin = vm.envAddress("AIRDROP_ADMIN");
        bool fund = vm.envOr("AIRDROP_FUND", false);
        uint256 total = vm.envOr("AIRDROP_TOTAL", uint256(0));

        require(deadline > block.timestamp, "CLAIM_DEADLINE must be in the future");

        vm.startBroadcast(pk);
        MerkleDistributor dist = new MerkleDistributor(IERC20(zent), root, deadline, admin);
        if (fund) {
            require(total > 0, "AIRDROP_FUND set but AIRDROP_TOTAL is 0");
            IERC20(zent).transfer(address(dist), total);
        }
        vm.stopBroadcast();

        // Post-deploy assertions
        require(address(dist.token()) == zent, "token mismatch");
        require(dist.merkleRoot() == root, "root mismatch");
        require(dist.claimDeadline() == deadline, "deadline mismatch");
        require(dist.hasRole(dist.DEFAULT_ADMIN_ROLE(), admin), "admin not set");
        if (fund) {
            require(IERC20(zent).balanceOf(address(dist)) == total, "funded balance != AIRDROP_TOTAL");
        }

        console2.log("MerkleDistributor:", address(dist));
        console2.log("admin (sweeper):", admin);
        console2.log("claimDeadline:", deadline);
        if (admin.code.length == 0) {
            console2.log("WARNING: admin is an EOA - acceptable on testnet ONLY; use the Safe on mainnet.");
        }
        if (!fund) {
            console2.log("NEXT: fund the distributor with the airdrop total (sum of leaves), then publish proofs to /claim.");
        } else {
            console2.log("Funded with AIRDROP_TOTAL:", total);
        }
    }
}

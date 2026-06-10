// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice One-shot admin wiring so the spot-rebalance loop can actually run. Without
///         this, `executeRebalance` is un-callable (nobody holds KEEPER_ROLE) and the
///         inner `vault.rebalanceTo` reverts (the executor lacks the vault's KEEPER_ROLE).
///
///         Run by the DEFAULT_ADMIN of the StrategyExecutor + SpotVault. It:
///           1. points the executor's `authorizedSigner` at KEEPER (the off-chain key
///              that signs Rebalance messages) — set this to a FRESH, DEDICATED wallet,
///              never a deployer wallet (key-reuse is the audit's #1 risk);
///           2. grants KEEPER on the executor to KEEPER (so it can submit executeRebalance);
///           3. grants KEEPER on the SpotVault to the executor (so it can drive rebalanceTo).
///         All three are idempotent — re-running is safe.
///
/// Required env:
///   EXPECTED_CHAIN_ID, PRIVATE_KEY (the admin key, e.g. 0xe56E… on testnet),
///   KEEPER  — the keeper/signer wallet address (fresh & dedicated; signs + submits)
/// Optional env (testnet defaults shown):
///   STRATEGY_EXECUTOR (0xaCD862eF134D772b0CA53a97f53CCDd00aBC05CF)
///   SPOT_VAULT        (0x504E998B32D165cfd6470a8a0000235550C33cBc)
///
/// Run:
///   KEEPER=0x<fresh-keeper> EXPECTED_CHAIN_ID=998 PRIVATE_KEY=0x<admin> \
///   forge script script/WireSpotKeeper.s.sol --rpc-url $RPC --broadcast
interface IExecutor {
    function KEEPER_ROLE() external view returns (bytes32);
    function authorizedSigner() external view returns (address);
    function setAuthorizedSigner(address) external;
    function grantRole(bytes32, address) external;
    function hasRole(bytes32, address) external view returns (bool);
}

interface IVault {
    function KEEPER_ROLE() external view returns (bytes32);
    function grantRole(bytes32, address) external;
    function hasRole(bytes32, address) external view returns (bool);
}

contract WireSpotKeeper is Script {
    function run() external {
        requireChainFromEnv();

        address executorAddr = vm.envOr("STRATEGY_EXECUTOR", 0xaCD862eF134D772b0CA53a97f53CCDd00aBC05CF);
        address vaultAddr = vm.envOr("SPOT_VAULT", 0x504E998B32D165cfd6470a8a0000235550C33cBc);
        address keeper = vm.envAddress("KEEPER");
        require(keeper != address(0), "KEEPER unset");

        IExecutor exec = IExecutor(executorAddr);
        IVault vault = IVault(vaultAddr);
        bytes32 execKeeperRole = exec.KEEPER_ROLE();
        bytes32 vaultKeeperRole = vault.KEEPER_ROLE();

        console2.log("Executor:", executorAddr);
        console2.log("SpotVault:", vaultAddr);
        console2.log("Keeper/signer:", keeper);
        console2.log("Before: authorizedSigner =", exec.authorizedSigner());
        console2.log("Before: keeper hasRole(exec.KEEPER) =", exec.hasRole(execKeeperRole, keeper));
        console2.log("Before: executor hasRole(vault.KEEPER) =", vault.hasRole(vaultKeeperRole, executorAddr));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        if (exec.authorizedSigner() != keeper) {
            exec.setAuthorizedSigner(keeper);
            console2.log("  -> setAuthorizedSigner(keeper)");
        }
        if (!exec.hasRole(execKeeperRole, keeper)) {
            exec.grantRole(execKeeperRole, keeper);
            console2.log("  -> granted KEEPER_ROLE on executor to keeper");
        }
        if (!vault.hasRole(vaultKeeperRole, executorAddr)) {
            vault.grantRole(vaultKeeperRole, executorAddr);
            console2.log("  -> granted KEEPER_ROLE on SpotVault to executor");
        }

        vm.stopBroadcast();

        // Post-conditions: the full chain a successful rebalance needs.
        require(exec.authorizedSigner() == keeper, "authorizedSigner not set");
        require(exec.hasRole(execKeeperRole, keeper), "keeper missing executor KEEPER_ROLE");
        require(vault.hasRole(vaultKeeperRole, executorAddr), "executor missing vault KEEPER_ROLE");
        console2.log("WIRED: keeper signs+submits, executor drives the vault. Fund the keeper with gas + go.");
    }
}

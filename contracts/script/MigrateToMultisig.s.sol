// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title MigrateToMultisig
/// @notice Migrates DEFAULT_ADMIN_ROLE from the current hot-wallet admin to a
///         Gnosis Safe multisig, across every AccessControl contract that the
///         hot wallet currently administers.
///
///         Modeled on RotateDeployer.s.sol (which performs the same
///         grant-then-renounce pattern when rotating a leaked EOA). The key
///         difference here is SAFETY GATING: this script runs in TWO PHASES,
///         and the renounce phase is OFF by default so the operator cannot
///         lock themselves (or the protocol) out by fat-fingering the Safe
///         address.
///
/// ─── TWO-PHASE DESIGN ────────────────────────────────────────────────────
///   PHASE 1 (default, RENOUNCE_OLD=false):
///     - grantRole(DEFAULT_ADMIN_ROLE, NEW_ADMIN) on every tracked contract
///       where the hot wallet currently holds DEFAULT_ADMIN_ROLE.
///     - The hot wallet KEEPS its admin. Now BOTH the hot wallet and the Safe
///       are admins. Nothing is lost; this is fully reversible.
///     - Operator then independently verifies the Safe works: confirm the Safe
///       can execute an admin call (e.g. a no-op setter) through the Gnosis UI,
///       confirm signer threshold, confirm hasRole returns true for the Safe.
///
///   PHASE 2 (explicit opt-in, RENOUNCE_OLD=true):
///     - renounceRole(DEFAULT_ADMIN_ROLE, hotWallet) on every tracked contract.
///     - After this, ONLY the Safe (plus any governance holders — see below)
///       administers the protocol. The hot wallet has zero admin authority.
///     - Run this ONLY after Phase 1 is verified end-to-end.
///
/// ─── ROLES IN SCOPE ──────────────────────────────────────────────────────
///   This script migrates DEFAULT_ADMIN_ROLE ONLY. DEFAULT_ADMIN_ROLE is the
///   role that can grant/revoke every other role, so whoever holds it can
///   re-derive control of the auxiliary roles below. Migrating it is the
///   correct first move; the auxiliary roles can then be re-pointed by the
///   Safe itself afterwards (or left where they are if they belong to bots).
///
///   AUXILIARY ROLES (NOT touched here — flagged for the operator):
///     - RISK_COUNCIL_ROLE  — BaseVault (all 4 vaults), SpotVault, ModelBonding.
///         Authorizes the circuit breaker (vaults) and provider slashing
///         (ModelBonding). If the hot wallet holds this, the Safe should grant
///         it to the appropriate risk-council signer set and the hot wallet
///         should renounce it. Operational, not custodial — but still privileged.
///     - GUARDIAN_ROLE      — StrategyExecutor. Emergency pause authority.
///         Same treatment: re-point to the Safe or a guardian set.
///     - EPOCH_SETTLER      — EpochScoring. Held by the KEEPER BOT, not the hot
///         wallet. Do NOT migrate to the Safe — the keeper must keep it to
///         settle epochs on its 4-hour cron. Leave as-is.
///     - SCORING_ORACLE     — SignalRegistry. Held by the EpochScoring CONTRACT
///         (a contract address, not the hot wallet). Do NOT migrate. Leave as-is.
///
///   To migrate the auxiliary council/guardian roles too, the cleanest path is
///   a follow-up Safe transaction batch (grantRole + renounceRole per role),
///   authored once the Safe holds DEFAULT_ADMIN_ROLE and can sign them.
///
/// ─── TIMELOCK — READ THIS BEFORE RENOUNCING ──────────────────────────────
///   Timelock is an OpenZeppelin TimelockController. Its DEFAULT_ADMIN_ROLE is
///   the "admin" that can grant/revoke PROPOSER_ROLE / EXECUTOR_ROLE /
///   CANCELLER_ROLE. The intended end state is that the Timelock is governed
///   ONLY by ZentGovernor (which holds PROPOSER_ROLE) — i.e. no standalone
///   admin EOA, all role changes go through a governance proposal subject to
///   the timelock delay.
///
///   ORDERING RISK: if you renounce the hot wallet's Timelock DEFAULT_ADMIN_ROLE
///   in Phase 2 WITHOUT first having granted it to the Safe in Phase 1, AND
///   ZentGovernor is not yet correctly wired as proposer, you can end up with a
///   Timelock that no live signer can re-configure. Mitigations baked in:
///     1. Phase 1 grants the Safe DEFAULT_ADMIN_ROLE on the Timelock too, so a
///        live multisig admin always exists before any renounce.
///     2. Phase 2 renounce on the Timelock is additionally gated behind
///        RENOUNCE_TIMELOCK (default false) so the operator must consciously
///        opt in to relinquishing the Timelock admin EVEN within a renounce run.
///   Recommended sequence: grant (Phase 1) -> verify Safe admin on Timelock AND
///   verify ZentGovernor proposer wiring -> renounce non-Timelock contracts
///   (Phase 2, RENOUNCE_TIMELOCK=false) -> only once governance is proven, do a
///   final run with RENOUNCE_TIMELOCK=true. Net end state: Timelock admin =
///   Safe (and/or governance), hot wallet = nothing.
///
/// ─── USAGE ───────────────────────────────────────────────────────────────
///   Env vars (forge auto-loads contracts/.env):
///     PRIVATE_KEY        — the CURRENT hot-wallet admin key (broadcaster).
///     NEW_ADMIN          — the Gnosis Safe address to receive admin.
///     RENOUNCE_OLD       — "true" to run Phase 2 (renounce). Default false.
///     RENOUNCE_TIMELOCK  — "true" to ALSO renounce Timelock admin in Phase 2.
///                          Default false. Ignored unless RENOUNCE_OLD=true.
///
///   1. Dry-run Phase 1 (no broadcast — prints the grant plan):
///        forge script script/MigrateToMultisig.s.sol --rpc-url $RPC_URL -vvv
///
///   2. Broadcast Phase 1 (grant only — reversible, hot wallet keeps admin):
///        forge script script/MigrateToMultisig.s.sol --rpc-url $RPC_URL \
///          --broadcast --slow --legacy
///      (or just run ./migrate-to-multisig.ps1)
///
///   3. VERIFY the Safe is a working admin (Gnosis UI + hasRole checks):
///        cast call $ZBTC_VAULT "hasRole(bytes32,address)(bool)" \
///          0x0000000000000000000000000000000000000000000000000000000000000000 \
///          $NEW_ADMIN
///      Should print true. Execute one harmless admin call from the Safe.
///
///   4. Broadcast Phase 2 (renounce hot wallet, EXCEPT Timelock):
///        RENOUNCE_OLD=true \
///        forge script script/MigrateToMultisig.s.sol --rpc-url $RPC_URL \
///          --broadcast --slow --legacy
///
///   5. After governance/proposer wiring is proven, final Timelock renounce:
///        RENOUNCE_OLD=true RENOUNCE_TIMELOCK=true \
///        forge script script/MigrateToMultisig.s.sol --rpc-url $RPC_URL \
///          --broadcast --slow --legacy
///
///   Safe to re-run at every step — checks hasRole() before each call and skips
///   no-ops (idempotent).
///
/// NOTE: This script does NOT broadcast on its own. The operator runs it with
///       their key. It is testnet-gated to chain 998.
contract MigrateToMultisig is Script {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    // Auxiliary roles — NOT migrated by this script (see header). Declared here
    // so an operator can quickly grep/probe them with a follow-up tool.
    bytes32 constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE"); // vaults + ModelBonding circuit breaker / slashing
    bytes32 constant GUARDIAN_ROLE     = keccak256("GUARDIAN_ROLE");     // StrategyExecutor emergency pause
    bytes32 constant EPOCH_SETTLER     = keccak256("EPOCH_SETTLER");     // EpochScoring — held by keeper bot, leave as-is
    bytes32 constant SCORING_ORACLE    = keccak256("SCORING_ORACLE");    // SignalRegistry — held by EpochScoring contract, leave as-is

    /// The current hot-wallet admin (post key-rotation). The broadcaster's
    /// PRIVATE_KEY must derive to this address, or the script aborts. Stored as
    /// a string + parsed via _addr() so Solidity's EIP-55 literal-checksum
    /// validation doesn't reject the mixed-case form.
    string constant HOT_WALLET_STR = "0xe56E7B7243C5820E1d59319937413C1462Ed5B5c";

    uint256 constant CHAIN_ID = 998; // HyperEVM testnet

    /// All contracts holding DEFAULT_ADMIN_ROLE that should migrate to the Safe.
    /// Addresses parsed via _addr() so EIP-55 checksum-strictness in Solidity
    /// literals doesn't bite. Source of truth: DEPLOYMENTS.md / STATE.md.
    address[] internal CONTRACTS;
    string[]  internal LABELS;

    /// The single per-contract flag set in Phase 2 to spare the Timelock.
    bool[] internal IS_TIMELOCK;

    function _addr(string memory hexStr) internal pure returns (address a) {
        bytes memory b = bytes(hexStr);
        require(b.length == 42 && b[0] == "0" && b[1] == "x", "bad addr");
        uint256 v = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) c -= 48;
            else if (c >= 65 && c <= 70) c -= 55;
            else if (c >= 97 && c <= 102) c -= 87;
            else revert("invalid hex");
            v = v * 16 + c;
        }
        return address(uint160(v));
    }

    function _add(address c, string memory l, bool isTimelock) internal {
        CONTRACTS.push(c);
        LABELS.push(l);
        IS_TIMELOCK.push(isTimelock);
    }

    function _buildRegistry() internal {
        // ─── Vaults (BaseVault) — DEFAULT_ADMIN_ROLE granted to admin_ in ctor ──
        _add(_addr("0x93669daC07321FF397cf5734Ae8364EA24addF45"), "zBTCVault", false);
        _add(_addr("0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e"), "zETHVault", false);
        _add(_addr("0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052"), "zSOLVault", false);
        _add(_addr("0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0"), "zXRPVault", false);

        // ─── Staking + bonding ───────────────────────────────────────────────
        _add(_addr("0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65"), "ZENTStaking", false);
        _add(_addr("0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007"), "ModelBonding", false);

        // ─── Fee distributors (one per vault) ────────────────────────────────
        // Labels follow DEPLOYMENTS.md "Distributor for <vault>" mapping.
        _add(_addr("0x8fb48f84aa69e89e0360e6d2d26c447aa57dcf73"), "FeeDistributor_zBTC", false);
        _add(_addr("0x403e8c79653b1cb7a5c0eaa313ec0c7d0cac7e2c"), "FeeDistributor_zETH", false);
        _add(_addr("0xc69f8a8014b4d17ee2e7457109ff1db33c0c7d7f"), "FeeDistributor_zSOL", false);
        _add(_addr("0xe990bfbc5c1e5779cb54cb95150edbbb2c2800d0"), "FeeDistributor_zXRP", false);

        // ─── Strategy execution ──────────────────────────────────────────────
        _add(_addr("0xacd862ef134d772b0ca53a97f53ccdd00abc05cf"), "StrategyExecutor", false);

        // ─── Governance — Timelock (TimelockController) ──────────────────────
        // Flagged IS_TIMELOCK=true so Phase 2 spares it unless RENOUNCE_TIMELOCK.
        // See the TIMELOCK section in the header for the ordering risk.
        _add(_addr("0x1504cA3C050C88CcCa67696d642F634fc381fD03"), "Timelock", true);
    }

    function run() external {
        require(
            block.chainid == CHAIN_ID,
            "wrong chain - MigrateToMultisig is gated to HyperEVM testnet (998)"
        );

        uint256 key = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(key);
        address hotWallet = _addr(HOT_WALLET_STR);
        require(
            broadcaster == hotWallet,
            "PRIVATE_KEY does not derive to the expected hot-wallet admin 0xe56E7B7243C5820E1d59319937413C1462Ed5B5c"
        );

        address newAdmin = vm.envAddress("NEW_ADMIN");
        require(newAdmin != address(0), "NEW_ADMIN required - the Gnosis Safe address");
        require(newAdmin != broadcaster, "NEW_ADMIN must differ from the hot wallet");

        // Phase gating. RENOUNCE_OLD defaults false -> grant-only (Phase 1).
        bool renounceOld = _envBoolOr("RENOUNCE_OLD", false);
        // Within a renounce run, the Timelock is ADDITIONALLY gated.
        bool renounceTimelock = _envBoolOr("RENOUNCE_TIMELOCK", false);

        _buildRegistry();

        console2.log("=== MigrateToMultisig ===");
        console2.log("Chain:", block.chainid);
        console2.log("Hot wallet (current admin):", broadcaster);
        console2.log("New admin (Gnosis Safe):", newAdmin);
        console2.log("Contracts tracked:", CONTRACTS.length);
        console2.log("Phase:", renounceOld ? "2 (GRANT verify + RENOUNCE hot wallet)" : "1 (GRANT only - reversible)");
        if (renounceOld) {
            console2.log("Renounce Timelock admin this run?:", renounceTimelock ? "YES" : "no (spared)");
        }
        console2.log("");

        // ─── Pre-flight read ──────────────────────────────────────────────────
        // For each contract record: does the hot wallet hold admin, does the Safe?
        bool[] memory hotHasAdmin = new bool[](CONTRACTS.length);
        bool[] memory safeHasAdmin = new bool[](CONTRACTS.length);
        uint256 hotAdminCount = 0;
        for (uint256 i = 0; i < CONTRACTS.length; i++) {
            try IAccessControl(CONTRACTS[i]).hasRole(DEFAULT_ADMIN_ROLE, broadcaster) returns (bool has) {
                hotHasAdmin[i] = has;
                if (has) {
                    hotAdminCount++;
                    console2.log("HOT-WALLET-ADMIN:", LABELS[i]);
                }
            } catch {
                console2.log("WARN: hasRole reverted (not AccessControl?):", LABELS[i]);
            }
            try IAccessControl(CONTRACTS[i]).hasRole(DEFAULT_ADMIN_ROLE, newAdmin) returns (bool has) {
                safeHasAdmin[i] = has;
            } catch {}
        }
        console2.log("");
        console2.log("Hot wallet holds DEFAULT_ADMIN_ROLE on:", hotAdminCount, "of", CONTRACTS.length);
        console2.log("");

        // ─── Execute (operator's key) ─────────────────────────────────────────
        vm.startBroadcast(key);

        // PHASE 1 — grant DEFAULT_ADMIN_ROLE to the Safe everywhere the hot
        // wallet holds it. Always runs (Phase 2 includes Phase 1's intent, and
        // grants are idempotent). This is the reversible step.
        uint256 granted = 0;
        for (uint256 i = 0; i < CONTRACTS.length; i++) {
            if (!hotHasAdmin[i]) {
                console2.log("SKIP-grant (hot wallet not admin here):", LABELS[i]);
                continue;
            }
            if (safeHasAdmin[i]) {
                console2.log("SKIP-grant (Safe already admin):", LABELS[i]);
                continue;
            }
            try IAccessControl(CONTRACTS[i]).grantRole(DEFAULT_ADMIN_ROLE, newAdmin) {
                console2.log("GRANT admin -> Safe:", LABELS[i]);
                granted++;
                safeHasAdmin[i] = true; // reflect for the renounce-safety check below
            } catch Error(string memory reason) {
                console2.log("FAIL-grant:", LABELS[i]);
                console2.log("       reason:", reason);
            } catch {
                console2.log("FAIL-grant (unknown revert):", LABELS[i]);
            }
        }
        console2.log("");

        // PHASE 2 — renounce the hot wallet's DEFAULT_ADMIN_ROLE. Gated.
        uint256 renounced = 0;
        if (renounceOld) {
            console2.log("--- PHASE 2: renouncing hot-wallet admin ---");
            for (uint256 i = 0; i < CONTRACTS.length; i++) {
                if (!hotHasAdmin[i]) continue; // hot wallet had nothing to renounce

                // SAFETY: never renounce unless the Safe verifiably holds admin
                // on THIS contract. Prevents bricking a contract whose grant
                // silently failed.
                if (!safeHasAdmin[i]) {
                    console2.log("ABORT-renounce (Safe is NOT admin here - would brick):", LABELS[i]);
                    continue;
                }

                // Timelock is additionally gated. Spare it unless explicitly told.
                if (IS_TIMELOCK[i] && !renounceTimelock) {
                    console2.log("SKIP-renounce (Timelock spared - set RENOUNCE_TIMELOCK=true to relinquish):", LABELS[i]);
                    continue;
                }
                if (IS_TIMELOCK[i] && renounceTimelock) {
                    console2.log("CAUTION: renouncing Timelock admin. Ensure ZentGovernor proposer wiring is proven.");
                }

                try IAccessControl(CONTRACTS[i]).renounceRole(DEFAULT_ADMIN_ROLE, broadcaster) {
                    console2.log("RENOUNCE admin (hot wallet):", LABELS[i]);
                    renounced++;
                } catch Error(string memory reason) {
                    console2.log("FAIL-renounce:", LABELS[i]);
                    console2.log("       reason:", reason);
                } catch {
                    console2.log("FAIL-renounce (unknown revert):", LABELS[i]);
                }
            }
            console2.log("");
        }

        vm.stopBroadcast();

        // ─── Summary ──────────────────────────────────────────────────────────
        console2.log("==========================================");
        console2.log("  MIGRATE-TO-MULTISIG SUMMARY");
        console2.log("==========================================");
        console2.log("Admin grants to Safe this run:", granted);
        if (renounceOld) {
            console2.log("Hot-wallet renunciations this run:", renounced);
        }
        console2.log("");
        if (!renounceOld) {
            console2.log("PHASE 1 DONE (grant-only). Hot wallet STILL holds admin.");
            console2.log("NEXT:");
            console2.log("  1. Verify the Safe is a working admin (Gnosis UI + hasRole).");
            console2.log("  2. Execute one harmless admin call from the Safe.");
            console2.log("  3. Re-run with RENOUNCE_OLD=true to relinquish the hot wallet.");
            console2.log("     (Timelock stays admin'd by the hot wallet until you also");
            console2.log("      pass RENOUNCE_TIMELOCK=true on a later, governance-proven run.)");
        } else {
            console2.log("PHASE 2 DONE (renounce). Hot wallet relinquished admin where the");
            console2.log("Safe verifiably held it.");
            if (!renounceTimelock) {
                console2.log("Timelock admin was SPARED. Final step once ZentGovernor proposer");
                console2.log("wiring is proven: re-run with RENOUNCE_TIMELOCK=true so the");
                console2.log("Timelock ends up controlled ONLY by the Safe and ZentGovernor.");
            } else {
                console2.log("Timelock admin renounced. Timelock is now controlled only by the");
                console2.log("Safe (DEFAULT_ADMIN_ROLE) and ZentGovernor (PROPOSER_ROLE).");
            }
            console2.log("");
            console2.log("REMINDER: auxiliary roles (RISK_COUNCIL_ROLE, GUARDIAN_ROLE) were");
            console2.log("NOT migrated. Re-point them from the Safe in a follow-up batch.");
            console2.log("EPOCH_SETTLER (keeper) and SCORING_ORACLE (EpochScoring contract)");
            console2.log("are intentionally left untouched.");
        }
    }

    /// vm.envOr for bools isn't available on older forge-std; parse manually so
    /// an unset env var cleanly defaults instead of reverting.
    function _envBoolOr(string memory name, bool dflt) internal view returns (bool) {
        try vm.envBool(name) returns (bool v) {
            return v;
        } catch {
            return dflt;
        }
    }
}

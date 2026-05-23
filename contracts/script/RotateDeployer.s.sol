// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title RotateDeployer
/// @notice Two-step rotation: grants DEFAULT_ADMIN_ROLE to a fresh NEW_ADMIN
///         wallet, then renounces every AccessControl role held by the leaked
///         deployer. Net effect: you keep admin power via a clean key, the
///         leaked key has zero remaining authority.
///
///         Pass NEW_ADMIN == DEPLOYER_ADDR to skip the grant step and do a
///         pure renunciation (only ZentGovernor + Timelock retain admin —
///         appropriate post-audit, not pre-mainnet).
///
///         Safe to re-run — checks hasRole() before each call and skips
///         no-ops.
///
/// PRECONDITION: ZentGovernor + Timelock independently hold DEFAULT_ADMIN_ROLE
///   on the contracts that require it (Phase5Only.s.sol set this up). This
///   script touches ONLY the deployer EOA's grants; governance keeps its
///   admin independently.
///
/// USAGE:
///   1. Generate a fresh admin wallet (store the key in a hardware wallet or
///      encrypted password manager — DO NOT commit it):
///        cast wallet new
///      Note the address; that's NEW_ADMIN.
///
///   2. Fund NEW_ADMIN with a small amount of testnet HYPE for gas (only
///      needed if you'll call admin functions from it later; not required
///      for the rotation itself).
///
///   3. Set env vars:
///        export PRIVATE_KEY=<leaked deployer key — 0xdc4289...aaf8>
///        export DEPLOYER_ADDR=<address of that key>
///        export NEW_ADMIN=<address from step 1>
///
///   4. Dry-run first (no broadcast — prints which roles will be touched):
///        forge script script/RotateDeployer.s.sol --rpc-url $RPC_URL -vvv
///
///   5. If output looks correct, broadcast:
///        forge script script/RotateDeployer.s.sol --rpc-url $RPC_URL \
///          --broadcast --slow --legacy
///
///   6. Post-run verification (dry-run again — should print "Deployer holds
///      NO roles"):
///        forge script script/RotateDeployer.s.sol --rpc-url $RPC_URL -vvv
///
///   7. Verify NEW_ADMIN can now hit admin functions on at least one vault:
///        cast call $ZBTC_VAULT "hasRole(bytes32,address)(bool)" \
///          0x0000...0000 $NEW_ADMIN
///      Should print "true".
///
///   8. Burn the leaked deployer key. Securely back up NEW_ADMIN's key.
contract RotateDeployer is Script {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant KEEPER_ROLE     = keccak256("KEEPER_ROLE");
    bytes32 constant GOVERNOR_ROLE   = keccak256("GOVERNOR_ROLE");
    bytes32 constant GUARDIAN_ROLE   = keccak256("GUARDIAN_ROLE");
    bytes32 constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");

    /// All contracts that descend from OpenZeppelin AccessControl, in the
    /// order they were deployed. Address strings are parsed via _addr() so
    /// EIP-55 checksum-strictness in Solidity literals doesn't bite.
    address[] internal CONTRACTS;
    string[]  internal LABELS;

    /// All roles the script will probe + renounce. DEFAULT_ADMIN_ROLE is the
    /// dangerous one — the rest are defensive (cheap probe).
    bytes32[] internal ROLES;
    string[]  internal ROLE_LABELS;

    function _addr(string memory hexStr) internal pure returns (address a) {
        bytes memory b = bytes(hexStr);
        require(b.length == 42 && b[0] == "0" && b[1] == "x", "bad addr");
        uint256 v = 0;
        for (uint i = 2; i < 42; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) c -= 48;
            else if (c >= 65 && c <= 70) c -= 55;
            else if (c >= 97 && c <= 102) c -= 87;
            else revert("invalid hex");
            v = v * 16 + c;
        }
        return address(uint160(v));
    }

    function _add(address c, string memory l) internal {
        CONTRACTS.push(c);
        LABELS.push(l);
    }

    function _addRole(bytes32 r, string memory l) internal {
        ROLES.push(r);
        ROLE_LABELS.push(l);
    }

    function _buildRegistries() internal {
        // Core token + vesting (ZENT has no admin role but ZENTVesting may)
        _add(_addr("0xf7c45f45768d790F388215A44d6E01f6f2568774"), "ZENTVesting");

        // Vaults — DEFAULT_ADMIN_ROLE granted to admin_ in constructor (likely deployer)
        _add(_addr("0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e"), "zETHVault");
        _add(_addr("0x93669daC07321FF397cf5734Ae8364EA24addF45"), "zBTCVault");
        _add(_addr("0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052"), "zSOLVault");
        _add(_addr("0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0"), "zXRPVault");

        // Staking + bonding
        _add(_addr("0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65"), "ZENTStaking");
        _add(_addr("0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007"), "ModelBonding");

        // Fee distributors (one per vault)
        _add(_addr("0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73"), "zETH_FeeDistributor");
        _add(_addr("0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c"), "zBTC_FeeDistributor");
        _add(_addr("0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F"), "zXRP_FeeDistributor");
        _add(_addr("0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0"), "zSOL_FeeDistributor");

        // Strategy execution (Phase 5 — note transferAdmin may have already
        // moved DEFAULT_ADMIN_ROLE off the deployer; script handles gracefully)
        _add(_addr("0xdad9175f6d2Da1709bA3F73711E69022538d21a7"), "HyperCoreAdapter");
        _add(_addr("0xaCD862eF134D772b0CA53a97f53CCDd00aBC05CF"), "StrategyExecutor");

        // Research Network
        _add(_addr("0x7745B22B2C73E422154Fcd1ECD283765c4BF6e8c"), "SignalRegistry");
        _add(_addr("0xC9F7345574e8734247556Ed4e30B11851E285bA4"), "EpochScoring");
        _add(_addr("0xd7d346f6d1F2CEcc3E67d9749B5121549F3dd80d"), "SubscriptionVault");

        // Governance (these are intentionally admin-less or self-admined after
        // Timelock takeover, but probe anyway in case deployer still holds)
        _add(_addr("0x24f9401284CE16CFe61e40C1F9e3fb37d15B878E"), "Zentroller");
        _add(_addr("0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118"), "ZentGovernor");
        _add(_addr("0x1504cA3C050C88CcCa67696d642F634fc381fD03"), "Timelock");

        // ─── Roles to probe + renounce ──────────────────────────────────
        _addRole(DEFAULT_ADMIN_ROLE,    "DEFAULT_ADMIN_ROLE");
        _addRole(KEEPER_ROLE,           "KEEPER_ROLE");
        _addRole(GOVERNOR_ROLE,         "GOVERNOR_ROLE");
        _addRole(GUARDIAN_ROLE,         "GUARDIAN_ROLE");
        _addRole(RISK_COUNCIL_ROLE,     "RISK_COUNCIL_ROLE");
    }

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address declaredDeployer = vm.envAddress("DEPLOYER_ADDR");
        require(
            deployer == declaredDeployer,
            "PRIVATE_KEY does not match DEPLOYER_ADDR - double-check both env vars before broadcasting"
        );

        // NEW_ADMIN receives DEFAULT_ADMIN_ROLE on every contract where the
        // (leaked) deployer currently holds it. This preserves your ability to
        // hotfix vault parameters during the pre-mainnet phase without leaving
        // the leaked key active. Pass DEPLOYER_ADDR as NEW_ADMIN to skip the
        // transfer step (e.g. for a pure renunciation post-audit).
        address newAdmin = vm.envAddress("NEW_ADMIN");
        require(newAdmin != address(0), "NEW_ADMIN required - cannot be zero address");
        bool transferAdmin = (newAdmin != deployer);

        _buildRegistries();

        console2.log("=== RotateDeployer ===");
        console2.log("Chain:", block.chainid);
        console2.log("Deployer (to revoke):", deployer);
        console2.log("New admin (to grant):", newAdmin);
        console2.log("Contracts:", CONTRACTS.length);
        console2.log("Roles per contract:", ROLES.length);
        console2.log("");

        // ─── Pre-flight: read which roles the deployer currently holds ──
        uint256 totalHeld = 0;
        uint256 adminHeld = 0;
        bool[][] memory heldMatrix = new bool[][](CONTRACTS.length);
        for (uint256 i = 0; i < CONTRACTS.length; i++) {
            heldMatrix[i] = new bool[](ROLES.length);
            for (uint256 r = 0; r < ROLES.length; r++) {
                // try/catch — not every contract implements AccessControl; some
                // (e.g. ZENT token) have no role machinery. hasRole reverts on
                // those, which we swallow.
                try IAccessControl(CONTRACTS[i]).hasRole(ROLES[r], deployer) returns (bool has) {
                    heldMatrix[i][r] = has;
                    if (has) {
                        totalHeld++;
                        if (ROLES[r] == DEFAULT_ADMIN_ROLE) adminHeld++;
                        console2.log("HOLD:", LABELS[i], ROLE_LABELS[r]);
                    }
                } catch {
                    // Contract doesn't expose hasRole — not an AccessControl
                    // contract or proxy returns garbage. Skip.
                }
            }
        }

        if (totalHeld == 0) {
            console2.log("");
            console2.log("Deployer holds NO roles on any tracked contract.");
            console2.log("Either rotation already complete, or wrong DEPLOYER_ADDR.");
            return;
        }

        console2.log("");
        if (transferAdmin) {
            console2.log("Step 1: grant DEFAULT_ADMIN_ROLE to NEW_ADMIN where deployer holds it");
            console2.log("Step 2: renounce ALL roles from deployer");
        } else {
            console2.log("NEW_ADMIN == deployer; pure renunciation, no grants");
        }
        console2.log("");

        // ─── Execute ─────────────────────────────────────────────────────
        vm.startBroadcast(key);
        uint256 granted = 0;
        uint256 renounced = 0;

        // Step 1: grant DEFAULT_ADMIN_ROLE to newAdmin everywhere deployer has it
        if (transferAdmin) {
            for (uint256 i = 0; i < CONTRACTS.length; i++) {
                // ROLES[0] is DEFAULT_ADMIN_ROLE by construction (see _buildRegistries order)
                if (!heldMatrix[i][0]) continue;
                // Skip if newAdmin already has it (idempotent)
                try IAccessControl(CONTRACTS[i]).hasRole(DEFAULT_ADMIN_ROLE, newAdmin) returns (bool already) {
                    if (already) {
                        console2.log("SKIP-grant (newAdmin already admin):", LABELS[i]);
                        continue;
                    }
                } catch {}
                try IAccessControl(CONTRACTS[i]).grantRole(DEFAULT_ADMIN_ROLE, newAdmin) {
                    console2.log("GRANT:", LABELS[i], "-> newAdmin");
                    granted++;
                } catch Error(string memory reason) {
                    console2.log("FAIL-grant:", LABELS[i]);
                    console2.log("       reason:", reason);
                } catch {
                    console2.log("FAIL-grant (unknown revert):", LABELS[i]);
                }
            }
            console2.log("");
        }

        // Step 2: renounce every role deployer holds
        for (uint256 i = 0; i < CONTRACTS.length; i++) {
            for (uint256 r = 0; r < ROLES.length; r++) {
                if (!heldMatrix[i][r]) continue;
                try IAccessControl(CONTRACTS[i]).renounceRole(ROLES[r], deployer) {
                    console2.log("RENOUNCE:", LABELS[i], ROLE_LABELS[r]);
                    renounced++;
                } catch Error(string memory reason) {
                    console2.log("FAIL-renounce:", LABELS[i], ROLE_LABELS[r]);
                    console2.log("       reason:", reason);
                } catch {
                    console2.log("FAIL-renounce (unknown revert):", LABELS[i], ROLE_LABELS[r]);
                }
            }
        }
        vm.stopBroadcast();

        console2.log("");
        console2.log("==========================================");
        console2.log("  DEPLOYER ROTATION COMPLETE");
        console2.log("==========================================");
        console2.log("Admin grants to newAdmin:", granted, "of", adminHeld);
        console2.log("Role renunciations from deployer:", renounced, "of", totalHeld);
        console2.log("");
        console2.log("VERIFY:");
        console2.log("  Re-run this script (dry-run, no --broadcast) and");
        console2.log("  confirm it prints 'Deployer holds NO roles'.");
        console2.log("");
        console2.log("THEN:");
        console2.log("  Securely back up the NEW_ADMIN key (hardware wallet,");
        console2.log("  encrypted password manager, multisig). Burn the leaked");
        console2.log("  deployer key - it has zero power on the protocol now.");
        console2.log("  ZentGovernor + Timelock retain their existing admin");
        console2.log("  rights independently; this rotation only touches the");
        console2.log("  EOA side of the access-control matrix.");
    }
}

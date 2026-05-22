// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title RotateDeployer
/// @notice Revokes every AccessControl role held by the (leaked) deployer
///         address across all 26 deployed contracts. Safe to re-run — checks
///         hasRole() before each renounceRole() and skips no-ops.
///
/// PRECONDITION: ZentGovernor + Timelock must already hold DEFAULT_ADMIN_ROLE
///   on every contract that requires it. Phase5Only.s.sol set this up via
///   grantRole(DEFAULT_ADMIN_ROLE, zentGovernor) — verify before running this
///   script, otherwise you risk locking out admin entirely.
///
/// USAGE:
///   1. Verify governance already has admin (cast call from contracts/):
///        cast call $ZENT_GOVERNOR "hasRole(bytes32,address)(bool)" \
///          0x0000...0000 $ZENT_GOVERNOR_ADDR
///      Repeat for each vault, executor, adapter, staking, etc.
///
///   2. Set env vars:
///        export PRIVATE_KEY=<leaked deployer key — 0xdc4289...aaf8>
///        export DEPLOYER_ADDR=<address of that key>
///
///   3. Dry-run first (no broadcast):
///        forge script script/RotateDeployer.s.sol --rpc-url $RPC_URL -vvv
///
///   4. If output looks correct, broadcast:
///        forge script script/RotateDeployer.s.sol --rpc-url $RPC_URL \
///          --broadcast --slow --legacy
///
///   5. Post-run verification (each line must print false):
///        cast call $ZENT "hasRole(bytes32,address)(bool)" \
///          0x0000...0000 $DEPLOYER_ADDR
///      etc.
///
///   6. Burn the leaked key — it has no remaining power on the protocol.
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

        _buildRegistries();

        console2.log("=== RotateDeployer ===");
        console2.log("Chain:", block.chainid);
        console2.log("Deployer (to renounce):", deployer);
        console2.log("Contracts:", CONTRACTS.length);
        console2.log("Roles per contract:", ROLES.length);
        console2.log("");

        // ─── Pre-flight: read which roles the deployer currently holds ──
        uint256 totalHeld = 0;
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
        console2.log("Renouncing", totalHeld, "role grants...");
        console2.log("");

        // ─── Execute: renounce each held role ───────────────────────────
        vm.startBroadcast(key);
        uint256 renounced = 0;
        for (uint256 i = 0; i < CONTRACTS.length; i++) {
            for (uint256 r = 0; r < ROLES.length; r++) {
                if (!heldMatrix[i][r]) continue;
                try IAccessControl(CONTRACTS[i]).renounceRole(ROLES[r], deployer) {
                    console2.log("DONE:", LABELS[i], ROLE_LABELS[r]);
                    renounced++;
                } catch Error(string memory reason) {
                    console2.log("FAIL:", LABELS[i], ROLE_LABELS[r]);
                    console2.log("       reason:", reason);
                } catch {
                    console2.log("FAIL (unknown revert):", LABELS[i], ROLE_LABELS[r]);
                }
            }
        }
        vm.stopBroadcast();

        console2.log("");
        console2.log("==========================================");
        console2.log("  DEPLOYER ROTATION COMPLETE");
        console2.log("==========================================");
        console2.log("Renounced:", renounced, "of", totalHeld);
        console2.log("");
        console2.log("VERIFY:");
        console2.log("  Re-run this script (dry-run, no --broadcast) and");
        console2.log("  confirm it prints 'Deployer holds NO roles'.");
        console2.log("");
        console2.log("THEN:");
        console2.log("  Burn the leaked key. It now has zero power on the");
        console2.log("  protocol. Future deploys: generate a fresh key with");
        console2.log("  `cast wallet new`, fund with testnet HYPE, use as");
        console2.log("  PRIVATE_KEY for future Foundry scripts.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

/// @title PauseZVaults
/// @notice Tier 0 Q11 deprecation broadcast. The founder (testnet deployer +
///         RISK_COUNCIL_ROLE holder on each z-vault) runs this once to pause
///         new deposits on zBTC / zETH / zSOL / zXRP — the four legacy
///         BaseVault subclasses that audit finding #7 flagged as charging
///         a 20% perf fee and advertising 3x leverage while running no
///         active strategy.
///
///         Withdrawals continue to work after activation (the existing
///         `BaseVault.onlyWhenCircuitBreakerInactive` modifier gates only
///         `deposit()` and `mint()`; `redeem()` / `withdraw()` are
///         unaffected). See `docs/decisions/2026-08-21-q11-zvaults-deprecate.md`
///         for the decision record and the known residual (legacy vaults
///         keep an immutable perf fee that can still fire on a withdraw of
///         a price-appreciated position).
///
/// @dev    Run by the founder (deployer key holds RISK_COUNCIL_ROLE on each
///         z-vault — granted at the original vault deploy):
///           forge script script/PauseZVaults.s.sol \
///             --rpc-url $RPC \
///             --broadcast
///         Required env: PRIVATE_KEY. Optional override (defaults to the
///         canonical testnet addresses from DEPLOYMENTS.md):
///           ZBTC_VAULT, ZETH_VAULT, ZSOL_VAULT, ZXRP_VAULT.
contract PauseZVaults is Script {
    // Live testnet defaults (HyperEVM 998) — canonical addresses from
    // `DEPLOYMENTS.md`. Stored as `bytes20` hex literals then cast to
    // `address` so Solidity 0.8.28's strict-checksum enforcement on literal
    // addresses does not fight us (hex literal -> bytes20 has no checksum
    // gate; `address(bytes20(...))` is a pure runtime cast).
    bytes20 constant DEFAULT_ZBTC_VAULT_BYTES = hex"93669daC07321FF397cf5734Ae8364EA24addF45";
    bytes20 constant DEFAULT_ZETH_VAULT_BYTES = hex"be8a9d22560A1b126554B70Aaca2D763B2E70C4e";
    bytes20 constant DEFAULT_ZSOL_VAULT_BYTES = hex"b62BA9d0a14aC9f9601891179B3Da52bE71Ce052";
    bytes20 constant DEFAULT_ZXRP_VAULT_BYTES = hex"8B15204D88a9Bb155bE6798522983A3B5F7d7cB0";

    bytes32 public constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");

    string constant CB_REASON = "Q11 deprecation: legacy perf fee + leverage no longer justified";

    function run() external {
        require(block.chainid == 998, "PauseZVaults: not HyperEVM testnet (998)");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(pk);

        address zbtcDefault = address(DEFAULT_ZBTC_VAULT_BYTES);
        address zethDefault = address(DEFAULT_ZETH_VAULT_BYTES);
        address zsolDefault = address(DEFAULT_ZSOL_VAULT_BYTES);
        address zxrpDefault = address(DEFAULT_ZXRP_VAULT_BYTES);

        address zbtc = vm.envOr("ZBTC_VAULT", zbtcDefault);
        address zeth = vm.envOr("ZETH_VAULT", zethDefault);
        address zsol = vm.envOr("ZSOL_VAULT", zsolDefault);
        address zxrp = vm.envOr("ZXRP_VAULT", zxrpDefault);

        console2.log("Broadcaster (must hold RISK_COUNCIL_ROLE on each vault):", broadcaster);
        console2.log("zBTCVault:", zbtc);
        console2.log("zETHVault:", zeth);
        console2.log("zSOLVault:", zsol);
        console2.log("zXRPVault:", zxrp);

        // Pre-check: the broadcaster must hold RISK_COUNCIL_ROLE on each vault.
        // We use a low-level `hasRole` probe (sig: hasRole(bytes32,address))
        // so this script does not depend on the BaseVault import (cheaper deploy).
        bytes memory probe = abi.encodeWithSignature("hasRole(bytes32,address)", RISK_COUNCIL_ROLE, broadcaster);
        _requireRole(zbtc, probe, "zBTCVault: broadcaster missing RISK_COUNCIL_ROLE");
        _requireRole(zeth, probe, "zETHVault: broadcaster missing RISK_COUNCIL_ROLE");
        _requireRole(zsol, probe, "zSOLVault: broadcaster missing RISK_COUNCIL_ROLE");
        _requireRole(zxrp, probe, "zXRPVault: broadcaster missing RISK_COUNCIL_ROLE");

        vm.startBroadcast(pk);

        _activate(zbtc, "zBTC");
        _activate(zeth, "zETH");
        _activate(zsol, "zSOL");
        _activate(zxrp, "zXRP");

        vm.stopBroadcast();

        // Post-deploy assertions: each vault reports isCircuitBreakerActive()==true.
        require(_isCbActive(zbtc), "zBTCVault: CB not active after broadcast");
        require(_isCbActive(zeth), "zETHVault: CB not active after broadcast");
        require(_isCbActive(zsol), "zSOLVault: CB not active after broadcast");
        require(_isCbActive(zxrp), "zXRPVault: CB not active after broadcast");

        console2.log("");
        console2.log("=== Z-VAULTS PAUSED (Q11 deprecation) ===");
        console2.log("zBTCVault CB active:", _isCbActive(zbtc));
        console2.log("zETHVault CB active:", _isCbActive(zeth));
        console2.log("zSOLVault CB active:", _isCbActive(zsol));
        console2.log("zXRPVault CB active:", _isCbActive(zxrp));
        console2.log("");
        console2.log("Next: re-point the dApp to render the legacy 'Paused (Q11)' badge and disable 'Deposit'.");
    }

    /// @notice Dry-run helper used by the regression test (`ZVaultDeprecation.t.sol`).
    ///         Activates the circuit breaker on a single vault address as
    ///         `caller` (uses `vm.startPrank` so the test contract can grant
    ///         RISK_COUNCIL_ROLE to itself and exercise the activation path
    ///         deterministically). Returns when the activation has been
    ///         observed in the current state.
    function runWithVaultAs(address caller, address vault, string calldata reason) external {
        require(vault != address(0), "PauseZVaults: zero vault address");
        require(caller != address(0), "PauseZVaults: zero caller address");
        vm.startPrank(caller);
        (bool ok, bytes memory ret) = vault.call(abi.encodeWithSignature("activateCircuitBreaker(string)", reason));
        vm.stopPrank();
        require(ok, string.concat("activateCircuitBreaker revert: ", _tryRevert(ret)));
        require(_isCbActive(vault), "CB not active after activateCircuitBreaker");
    }

    // ─── internal probes (low-level staticcall so the script does not import BaseVault) ───

    function _activate(address vault, string memory label) internal {
        console2.log(string.concat("[", label, "] activating CB..."));
        (bool ok, bytes memory ret) = vault.call(abi.encodeWithSignature("activateCircuitBreaker(string)", CB_REASON));
        require(ok, string.concat(label, ": activateCircuitBreaker revert: ", _tryRevert(ret)));
    }

    function _isCbActive(address vault) internal view returns (bool) {
        (bool ok, bytes memory ret) = vault.staticcall(abi.encodeWithSignature("isCircuitBreakerActive()(bool)"));
        if (!ok || ret.length < 32) return false;
        return abi.decode(ret, (bool));
    }

    function _requireRole(address vault, bytes memory probe, string memory err) internal view {
        (bool ok, bytes memory ret) = vault.staticcall(probe);
        require(ok, string.concat(err, " (probe failed)"));
        require(ret.length >= 32, string.concat(err, " (probe short)"));
        bool has = abi.decode(ret, (bool));
        require(has, err);
    }

    function _tryRevert(bytes memory ret) internal pure returns (string memory) {
        if (ret.length < 4) return "<no revert data>";
        // Best-effort: return hex so the founder can correlate to a custom error.
        return _toHex(ret);
    }

    function _toHex(bytes memory data) internal pure returns (string memory) {
        bytes16 alphabet = "0123456789abcdef";
        bytes memory out = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            out[i * 2] = alphabet[uint8(data[i]) >> 4];
            out[i * 2 + 1] = alphabet[uint8(data[i]) & 0x0f];
        }
        return string(out);
    }
}

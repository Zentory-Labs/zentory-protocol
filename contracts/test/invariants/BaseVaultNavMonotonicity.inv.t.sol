// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {PassiveVault} from "../../src/vaults/PassiveVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title BaseVaultNavMonotonicityInvariant
/// @notice Tier 0 Q11 / audit finding #7 invariant — for a passive BaseVault
///         subclass (i.e. `PassiveVault` with `maxLeverage == 0`,
///         `performanceFee == 0`), `getNavPerShare()` is invariant in the
///         absence of an external token transfer to the vault.
///
///         Rationale (from `docs/decisions/2026-08-21-q11-zvaults-deprecate.md`):
///         with no strategy running and no leverage cap to honour,
///         `totalAssets()` reflects the vault's idle ERC20 balance 1:1, and
///         `getNavPerShare()` is `totalAssets() * shareUnit / totalSupply()` —
///         a ratio that cannot move unless either side of the fraction moves.
///         No external actor can shift the idle balance; only a direct
///         ERC20 transfer to the vault OR a deposit/withdraw cycle can.
///
/// @dev    The fuzzer is bound (`targetSelectors`) to the vault's no-op view
///         and free-fee paths only:
///           * `evaluateFees()` — public, but with performanceFee=0 the fee
///             math is a no-op, so NAV should not move.
///           * `checkCircuitBreaker()` — view-only, public.
///           * `getNavPerShare()` read itself — pure view.
///         Anything that can move NAV (deposit, withdraw, transfer-in to the
///         vault) is excluded from the fuzzer target set, which is the
///         whole point — what we are locking in is "no NAV drift under
///         repeated no-op calls".
contract BaseVaultNavMonotonicityInvariant is StdInvariant, Test {
    PassiveVault vault;
    MockERC20 asset;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 internal navSnapshot;

    function setUp() external {
        asset = new MockERC20("Mock WBTC", "WBTC", 18);
        vault = new PassiveVault(address(asset), "zBTC", "zBTC", address(this), address(this));

        asset.mint(alice, 1_000_000e18);
        asset.mint(bob, 1_000_000e18);

        // Seed the vault with a single depositor so totalSupply() != 0 and
        // getNavPerShare() returns the live idle-balance ratio.
        vm.startPrank(alice);
        asset.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        navSnapshot = vault.getNavPerShare();
        assertGt(navSnapshot, 0, "nav must be > 0 after seed deposit");

        // Restrict the fuzzer's target selector set to the no-op surface of
        // the vault. We do NOT target `deposit` / `mint` / `withdraw` /
        // `redeem` because those legitimately change the NAV ratio (and the
        // auditor would expect them to). The whole assertion under test is
        // "the no-op surface does not move NAV".
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = BaseVault.evaluateFees.selector;
        selectors[1] = BaseVault.checkCircuitBreaker.selector;
        targetSelector(FuzzSelector({addr: address(vault), selectors: selectors}));

        // Exclude the mock asset from the fuzzer's targets: a `burn` on the
        // vault's idle balance (or a direct `transfer` to the vault address)
        // would intentionally change `totalAssets()` and thus NAV-per-share,
        // which is what the invariant is designed to detect. We want the
        // *vault's no-op surface* to be the only thing changing state under
        // fuzz, so the MockERC20's external mutators are excluded entirely.
        excludeContract(address(asset));
    }

    /// @notice NAV-per-share is invariant across an arbitrary number of
    ///         "no-transfer / no-trade / no-claim" calls.
    function invariant_passiveVaultNavIsMonotonicInAbsenceOfTransferOrDeposit() external view {
        assertEq(
            vault.getNavPerShare(),
            navSnapshot,
            "PassiveVault.getNavPerShare() moved without a transfer-in or deposit/withdraw"
        );
    }
}


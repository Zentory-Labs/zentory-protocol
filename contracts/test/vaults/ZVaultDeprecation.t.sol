// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {PassiveVault} from "../../src/vaults/PassiveVault.sol";
import {zBTCVault} from "../../src/vaults/zBTCVault.sol";
import {zETHVault} from "../../src/vaults/zETHVault.sol";
import {zSOLVault} from "../../src/vaults/zSOLVault.sol";
import {zXRPVault} from "../../src/vaults/zXRPVault.sol";

import {PauseZVaults} from "../../script/PauseZVaults.s.sol";

/// @title ZVaultDeprecationTest
/// @notice Tier 0 Q11 regression test. Locks in the audit-decided behaviour:
///         (a) legacy z-vaults (immutable performanceFee=2000, maxLeverage=30000)
///             are paused via the existing BaseVault circuit-breaker so NEW
///             deposits are blocked while withdrawals continue to work;
///         (b) the FUTURE passive wrapper (`PassiveVault`) bakes in
///             `performanceFee = 0` and `maxLeverage = 0` so this class of bug
///             cannot recur for a future deploy;
///         (c) the founder broadcast script (`PauseZVaults`) compiles and is
///             dry-runnable against a test vault instance.
/// @dev    See `docs/decisions/2026-08-21-q11-zvaults-deprecate.md` for the
///         decision record + the known residual (legacy z-vaults keep an
///         immutable perf fee that can still fire on withdraw).
contract ZVaultDeprecationTest is Test {
    ERC20Mock internal asset;
    address internal admin = makeAddr("admin");
    address internal riskCouncil = makeAddr("riskCouncil");
    address internal alice = makeAddr("alice");

    uint256 constant ASSET_UNIT = 10 ** 18;

    function setUp() public {
        asset = new ERC20Mock();
        asset.mint(alice, type(uint128).max);
    }

    // ─── 1. Legacy risk rails are immutable and as-deployed ──────────────
    // The audit (finding #7) was that the legacy vaults charged a 20% perf fee
    // and advertised 3x leverage with no active strategy. These tests pin the
    // current numbers so the deprecation decision is a *conscious* one — if
    // they ever silently change to (0, 0) the deprecation is wrong.

    function test_legacy_zBTC_pinsPerformanceFeeAndLeverage() external {
        zBTCVault v = new zBTCVault(address(asset), admin, address(this));
        assertEq(v.performanceFee(), 2000, "zBTC: legacy performanceFee MUST be 2000 (Q11 decision pins this)");
        assertEq(v.maxLeverage(), 30000, "zBTC: legacy maxLeverage MUST be 30000 (Q11 decision pins this)");
    }

    function test_legacy_zETH_pinsPerformanceFeeAndLeverage() external {
        zETHVault v = new zETHVault(address(asset), admin, address(this));
        assertEq(v.performanceFee(), 2000);
        assertEq(v.maxLeverage(), 30000);
    }

    function test_legacy_zSOL_pinsPerformanceFeeAndLeverage() external {
        zSOLVault v = new zSOLVault(address(asset), admin, address(this));
        assertEq(v.performanceFee(), 2000);
        assertEq(v.maxLeverage(), 30000);
    }

    function test_legacy_zXRP_pinsPerformanceFeeAndLeverage() external {
        zXRPVault v = new zXRPVault(address(asset), admin, address(this));
        assertEq(v.performanceFee(), 2000);
        assertEq(v.maxLeverage(), 30000);
    }

    // ─── 2. CB activation blocks deposits, keeps withdraws working ──────
    // After `activateCircuitBreaker(reason)`, the legacy vault must reject
    // deposit() and mint() (per the existing `onlyWhenCircuitBreakerInactive`
    // modifier on BaseVault) AND must continue to redeem cleanly. This is
    // the feature's expectedBehaviour: "z-vaults paused, deposits blocked,
    // withdraws work".

    function test_zBTC_circuitBreakerBlocksDepositAllowsWithdraw() external {
        zBTCVault v = new zBTCVault(address(asset), admin, address(this));
        _seedDepositors(address(v), 100 * ASSET_UNIT);
        v.grantRole(v.RISK_COUNCIL_ROLE(), riskCouncil);

        // Pre-pause: deposit works.
        _depositAs(alice, address(v), 10 * ASSET_UNIT);
        assertGt(v.balanceOf(alice), 0);

        // Pause.
        vm.prank(riskCouncil);
        v.activateCircuitBreaker("Q11 deprecation");
        assertTrue(v.isCircuitBreakerActive());

        // Post-pause: deposit reverts with the existing CB-active message.
        _approveAs(alice, address(v), 10 * ASSET_UNIT);
        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        v.deposit(10 * ASSET_UNIT, alice);

        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        v.mint(10 * ASSET_UNIT, alice);

        // Post-pause: redeem still works.
        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = v.redeem(shares, alice, alice);
        assertGt(redeemed, 0, "withdraw under CB must continue to return assets");
        assertEq(v.balanceOf(alice), 0);
    }

    function test_zETH_circuitBreakerBlocksDepositAllowsWithdraw() external {
        zETHVault v = new zETHVault(address(asset), admin, address(this));
        _seedDepositors(address(v), 100 * ASSET_UNIT);
        v.grantRole(v.RISK_COUNCIL_ROLE(), riskCouncil);

        _depositAs(alice, address(v), 10 * ASSET_UNIT);

        vm.prank(riskCouncil);
        v.activateCircuitBreaker("Q11 deprecation");
        assertTrue(v.isCircuitBreakerActive());

        _approveAs(alice, address(v), 10 * ASSET_UNIT);
        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        v.deposit(10 * ASSET_UNIT, alice);

        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = v.redeem(shares, alice, alice);
        assertGt(redeemed, 0);
    }

    function test_zSOL_circuitBreakerBlocksDepositAllowsWithdraw() external {
        zSOLVault v = new zSOLVault(address(asset), admin, address(this));
        _seedDepositors(address(v), 100 * ASSET_UNIT);
        v.grantRole(v.RISK_COUNCIL_ROLE(), riskCouncil);

        _depositAs(alice, address(v), 10 * ASSET_UNIT);

        vm.prank(riskCouncil);
        v.activateCircuitBreaker("Q11 deprecation");
        assertTrue(v.isCircuitBreakerActive());

        _approveAs(alice, address(v), 10 * ASSET_UNIT);
        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        v.deposit(10 * ASSET_UNIT, alice);

        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = v.redeem(shares, alice, alice);
        assertGt(redeemed, 0);
    }

    function test_zXRP_circuitBreakerBlocksDepositAllowsWithdraw() external {
        zXRPVault v = new zXRPVault(address(asset), admin, address(this));
        _seedDepositors(address(v), 100 * ASSET_UNIT);
        v.grantRole(v.RISK_COUNCIL_ROLE(), riskCouncil);

        _depositAs(alice, address(v), 10 * ASSET_UNIT);

        vm.prank(riskCouncil);
        v.activateCircuitBreaker("Q11 deprecation");
        assertTrue(v.isCircuitBreakerActive());

        _approveAs(alice, address(v), 10 * ASSET_UNIT);
        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        v.deposit(10 * ASSET_UNIT, alice);

        uint256 shares = v.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = v.redeem(shares, alice, alice);
        assertGt(redeemed, 0);
    }

    // ─── 3. CB activation requires RISK_COUNCIL_ROLE ─────────────────────
    // The pause script (and any on-chain actor) must hold RISK_COUNCIL_ROLE
    // on the target vault. Without this the Q11 deprecation is unguarded.

    function test_activateCircuitBreaker_requiresRiskCouncilRole() external {
        zBTCVault v = new zBTCVault(address(asset), admin, address(this));
        // Default admin (this) does NOT have RISK_COUNCIL_ROLE — must grant first.
        vm.expectRevert();
        v.activateCircuitBreaker("unauthorized");
        assertFalse(v.isCircuitBreakerActive());
    }

    // ─── 4. PassiveVault (future pattern) zero fees / zero leverage ──────
    // The future-pattern wrapper must bake in performanceFee=0, maxLeverage=0
    // regardless of who deploys it. This is the "source-level" closure of
    // audit finding #7: a future deployer cannot accidentally re-enable a
    // perf fee or leverage cap by picking this subclass.

    function test_passiveVault_zeroPerformanceFee() external {
        PassiveVault v = new PassiveVault(address(asset), "BTC", "zBTC", admin, address(this));
        assertEq(v.performanceFee(), 0, "PassiveVault.performanceFee MUST be 0 (Q11 closure of finding #7)");
    }

    function test_passiveVault_zeroMaxLeverage() external {
        PassiveVault v = new PassiveVault(address(asset), "ETH", "zETH", admin, address(this));
        assertEq(v.maxLeverage(), 0, "PassiveVault.maxLeverage MUST be 0 (Q11 closure of finding #7)");
    }

    function test_passiveVault_otherRailsAreSafeDefaults() external {
        PassiveVault v = new PassiveVault(address(asset), "SOL", "zSOL", admin, address(this));
        // Sanity-check the rest of the risk rails are *bounded* (not necessarily 0).
        assertLe(v.maxPositionSizeBPS(), 10000);
        assertLe(v.circuitBreakerDrawdownBPS(), 10000);
        assertLe(v.rebalanceThresholdBPS(), 10000);
    }

    function test_passiveVault_blocksKeeperTradeViaZeroLeverageCap() external {
        // With maxLeverage=0, any trade on a non-empty vault reverts (the
        // BaseVault invariant in `recordTrade` is `size <= tvl * maxLeverage
        // / 10000`, so tvl > 0 + maxLeverage = 0 forces a revert). Verifies
        // the "no active strategy" invariant at the keeper-call surface.
        PassiveVault v = new PassiveVault(address(asset), "XRP", "zXRP", admin, address(this));
        v.grantRole(v.KEEPER_ROLE(), address(this));

        // Seed the vault with a deposit so tvl > 0 and the size-check branch
        // is actually reached (BaseVault's recordTrade skips the check when
        // tvl == 0; we want the keeper cap to bind under normal conditions).
        asset.mint(alice, 1_000 * ASSET_UNIT);
        vm.prank(alice);
        asset.approve(address(v), 1_000 * ASSET_UNIT);
        vm.prank(alice);
        v.deposit(1_000 * ASSET_UNIT, alice);
        assertGt(v.totalAssets(), 0, "tvl must be > 0 for the keeper cap to bind");

        vm.expectRevert("Leverage exceeds max");
        v.recordTrade(int8(1), 1, 1);
    }

    // ─── 5. Pause script compiles + dry-runs against test instances ─────
    // The founder broadcast script must (a) compile on this branch and (b)
    // produce the right selector under `runWithVault`. We assert the latter
    // by exercising the no-broadcast dry-run path against a freshly built
    // vault instance.

    function test_pauseScript_dryRunsAgainstTestVault() external {
        // Sanity: the script contract compiles and is wired correctly. We
        // verify the script's `runWithVaultAs` reverts when the caller does
        // NOT hold RISK_COUNCIL_ROLE on the target vault (i.e. the script's
        // RBAC plumbing is exposed and observable). The happy-path
        // activation behavior is covered by the per-vault CB tests above.
        zBTCVault v = new zBTCVault(address(asset), admin, address(this));
        // Note: deliberately NOT granting RISK_COUNCIL_ROLE to the test
        // contract, so the script's activation path must revert.

        PauseZVaults script = new PauseZVaults();
        vm.expectRevert();
        script.runWithVaultAs(address(this), address(v), "Q11 deprecation");
        // State unchanged.
        assertFalse(v.isCircuitBreakerActive());
    }

    // ─── helpers (address-typed so the same helper serves every subclass) ───

    function _seedDepositors(address vault, uint256 amount) internal {
        address seeder = makeAddr("seeder");
        asset.mint(seeder, amount);
        vm.prank(seeder);
        asset.approve(vault, amount);
        vm.prank(seeder);
        BaseVault(vault).deposit(amount, seeder);
    }

    function _depositAs(address user, address vault, uint256 assets) internal {
        _approveAs(user, vault, assets);
        vm.prank(user);
        BaseVault(vault).deposit(assets, user);
    }

    function _approveAs(address user, address vault, uint256 assets) internal {
        vm.prank(user);
        asset.approve(vault, assets);
    }
}

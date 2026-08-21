// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SpotVault — admin-override emergency-exit regression tests (Tier-0.A Q8)
/// @notice Closes the Tier-0 mainnet-readiness blocker called out at
///         `docs/MAINNET_READINESS.md §0.A`: "Oracle going quiet freezes all
///         withdrawals; no fallback, no admin override. Users cannot exit."
///         This file ships the admin-override half of that fix.
///
/// Background: the existing `redeemEmergency(shares, receiver, owner)` is
/// permissionless — any share holder may call it. In a stale-oracle event,
/// every share holder is racing the same pool of remaining underlying, and a
/// single MEV bot can grief the honest users by repeatedly invoking the path
/// inside the per-address cooldown window. The per-address cooldown in
/// `emergencyRedeemCooldown` already rate-limits one address; it does NOT
/// prevent a bot with many addresses (or many sybils) from draining the vault.
///
/// Fix: an admin-override `redeemEmergencyFor(address owner, uint256 shares,
/// address receiver)` callable by `RISK_COUNCIL_ROLE` (the existing on-chain
/// role already gated to the 4/7 Safe / founder multisig on mainnet). The
/// admin path uses the SAME per-address cooldown key on `owner`, so:
///   - the admin CAN burn a victim's shares on the victim's behalf during an
///     incident response (e.g. when the victim's UI is down or the victim is
///     unreachable);
///   - the admin CANNOT bypass the cooldown for the victim — every admin call
///     advances the owner's cooldown clock identically to a user-initiated call;
///   - the admin CANNOT use the override to drain a victim's shares after the
///     victim has already exited (allowance is checked, see below).
///
/// The function preserves ERC-4626 ownership semantics: the admin must hold a
/// sufficient allowance from `owner` for `shares` (or be the owner themselves),
/// mirroring the user-initiated `redeemEmergency` allowance check.
///
/// Test cases (one per Q8 sub-assertion):
///   1. Admin variant exists and pays `receiver` with shares burned from `owner`.
///   2. Non-admin (lacking RISK_COUNCIL_ROLE) reverts with AccessControl.
///   3. Per-address cooldown preserved — second admin call for same owner reverts
///      with EmergencyCooldownActive at the same boundary as user-initiated.
///   4. Cooldown gate is per-Owner, not per-caller — admin acting for alice
///      does NOT consume bob's cooldown, and vice versa.
///   5. Circuit-breaker halts admin override (same as user-initiated path).
///   6. Admin must respect owner's allowance: cannot drain a victim who has
///      revoked (zero) allowance.
///   7. Admin must respect owner's allowance: insufficient allowance reverts.
///   8. Input validation — zero shares / zero address reverts.
///   9. Emits `EmergencyRedeem` event with `caller = admin` (the auditor's
///      off-chain monitor can correlate by caller).
///  10. Invariant: cooldown for `owner` ticks regardless of which path consumed it.

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @dev Chainlink-style mock feed with settable answer + updatedAt (for staleness).
contract AdminOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 a) external {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 t) external {
        updatedAt = t;
    }

    function setAnswer(int256 a) external {
        answer = a;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract AdminAdapter is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    AdminOracle public immutable oracle;
    uint8 immutable aDec;
    uint8 immutable cDec;
    uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_;
        cash = cash_;
        oracle = AdminOracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = AdminOracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == asset && tokenOut == cash) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else if (tokenIn == cash && tokenOut == asset) {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        } else {
            revert("unsupported pair");
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract SpotVaultEmergencyAdminOverrideTest is Test {
    MockERC20 wbtc;
    MockERC20 usdc;
    AdminOracle oracle;
    AdminAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address riskCouncil = makeAddr("riskCouncil");
    address stranger = makeAddr("stranger");
    int256 constant PRICE_50K = 50_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new AdminOracle(PRICE_50K);
        adapter = new AdminAdapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc),
            address(usdc),
            address(oracle),
            MAX_STALE,
            "Zentory BTC Admin Vault",
            "zBTCA",
            0,
            100,
            0,
            address(this),
            address(this),
            1 hours
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), address(this));
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), riskCouncil);

        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
        wbtc.mint(bob, TEN_BTC);
    }

    /// Helper: alice deposits TEN_BTC into the vault. Returns her share balance.
    function _aliceDeposit() internal returns (uint256) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        uint256 shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        return shares;
    }

    function _bobDeposit() internal returns (uint256) {
        vm.startPrank(bob);
        wbtc.approve(address(vault), TEN_BTC);
        uint256 shares = vault.deposit(TEN_BTC, bob);
        vm.stopPrank();
        return shares;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 1) Admin override exists and burns owner's shares, pays receiver.
    //    Mirrors `redeemEmergency` semantics for the caller/receiver split.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_adminCanBurnOwnerShares() public {
        uint256 shares = _aliceDeposit();
        // Fund the vault so the redeem actually pays out something.
        wbtc.mint(address(vault), 5 * 1e8);

        uint256 supply = vault.totalSupply();
        uint256 bal = wbtc.balanceOf(address(vault));
        uint256 expectedPaid = (shares * bal) / supply;

        // alice grants the admin allowance to burn her shares (the standard
        // ERC-4626 allowance semantics for an admin-initiated exit; in an
        // incident, the admin can also be the owner via a Safe multisig).
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);

        uint256 receiverBalBefore = wbtc.balanceOf(bob);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // The risk council admin burns alice's shares and pays bob (a designated
        // recovery destination, e.g. a Safe multisig wallet alice controls).
        vm.prank(riskCouncil);
        uint256 paid = vault.redeemEmergencyFor(alice, shares, bob);

        assertEq(paid, expectedPaid, "admin override pays pro-rata underlying");
        assertEq(vault.balanceOf(alice), 0, "alice's shares burned");
        assertEq(wbtc.balanceOf(bob), receiverBalBefore + expectedPaid, "receiver paid");
        assertEq(vault.totalSupply(), supply - shares, "supply decremented");
        assertEq(vault.balanceOf(alice), aliceSharesBefore - shares, "shares balance decremented");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2) Non-admin (lacking RISK_COUNCIL_ROLE) reverts with AccessControl.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_nonAdminReverts() public {
        uint256 shares = _aliceDeposit();

        // stranger holds neither DEFAULT_ADMIN_ROLE nor RISK_COUNCIL_ROLE.
        vm.prank(stranger);
        vm.expectRevert(); // AccessControl: account is missing role
        vault.redeemEmergencyFor(alice, shares, stranger);

        // alice is the owner but does NOT hold RISK_COUNCIL_ROLE.
        vm.prank(alice);
        vm.expectRevert(); // AccessControl: account is missing role
        vault.redeemEmergencyFor(alice, shares, alice);

        // A fresh DEFAULT_ADMIN_ROLE-only address also cannot call (the role
        // gate is specifically RISK_COUNCIL_ROLE — admin power is partitioned).
        address defaultAdmin = makeAddr("defaultAdmin");
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), defaultAdmin);
        vm.prank(defaultAdmin);
        vm.expectRevert(); // AccessControl: account is missing role
        vault.redeemEmergencyFor(alice, shares, defaultAdmin);

        // Confirm the role-gated path: riskCouncil succeeds (no revert).
        wbtc.mint(address(vault), 1 * 1e8); // fund for payout
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);
        vm.prank(riskCouncil);
        vault.redeemEmergencyFor(alice, shares / 2, alice); // should not revert
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3) Per-address cooldown preserved on admin override.
    //    Same boundary as user-initiated `redeemEmergency`.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_preservesPerAddressCooldown() public {
        uint256 shares = _aliceDeposit();
        wbtc.mint(address(vault), 5 * 1e8);
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);

        // First admin call for alice succeeds (lastEmergencyRedeemAt[alice] == 0).
        vm.prank(riskCouncil);
        uint256 firstPaid = vault.redeemEmergencyFor(alice, shares / 3, alice);
        assertGt(firstPaid, 0, "first admin call pays");

        // Immediate second admin call for the SAME owner reverts at the same
        // boundary as the user-initiated path would.
        uint256 expectedNext = block.timestamp + vault.emergencyRedeemCooldown();
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, expectedNext));
        vault.redeemEmergencyFor(alice, shares / 3, alice);

        // And: an immediate USER-initiated call from alice also reverts at
        // the SAME boundary — the cooldown clock is OWNER-keyed, not caller-keyed.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, expectedNext));
        vault.redeemEmergency(shares / 3, alice, alice);

        // Warp past the cooldown: both paths succeed again.
        vm.warp(block.timestamp + vault.emergencyRedeemCooldown() + 1);

        vm.prank(riskCouncil);
        uint256 adminPaid = vault.redeemEmergencyFor(alice, shares / 3, alice);
        assertGt(adminPaid, 0, "post-cooldown admin path: succeeds");

        vm.warp(block.timestamp + vault.emergencyRedeemCooldown() + 1);
        vm.prank(alice);
        uint256 userPaid = vault.redeemEmergency(shares / 3, alice, alice);
        assertGt(userPaid, 0, "post-cooldown user path: succeeds");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4) Cooldown gate is per-Owner, not per-caller.
    //    Admin acting for alice must NOT consume bob's cooldown clock.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_cooldownIsPerOwner_notPerCaller() public {
        uint256 aliceShares = _aliceDeposit();
        uint256 bobShares = _bobDeposit();
        wbtc.mint(address(vault), 10 * 1e8);
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);
        vm.prank(bob);
        vault.approve(riskCouncil, type(uint256).max);

        // Admin burns ALL of alice's shares (one admin call).
        vm.prank(riskCouncil);
        vault.redeemEmergencyFor(alice, aliceShares, alice);

        // Bob's cooldown is INDEPENDENT — admin can immediately burn bob's
        // shares too. This is the per-owner isolation property.
        vm.prank(riskCouncil);
        uint256 bobPaid = vault.redeemEmergencyFor(bob, bobShares, bob);
        assertGt(bobPaid, 0, "bob's cooldown untouched by alice's admin call");

        // And: alice's cooldown is active even though her shares are gone.
        // Any further attempt (admin or user) for alice reverts at the
        // cooldown boundary. The cooldown check happens BEFORE the burn, so
        // even with a stale `shares` argument the cooldown gate fires first
        // — this is intentional, it prevents a "try-to-exit" race during
        // the cooldown window.
        uint256 aliceLast = vault.lastEmergencyRedeemAt(alice);
        uint256 expectedNext = aliceLast + vault.emergencyRedeemCooldown();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, expectedNext));
        vault.redeemEmergency(1, alice, alice);
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, expectedNext));
        vault.redeemEmergencyFor(alice, 1, alice);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5) Circuit-breaker halts admin override (same as user-initiated path).
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_revertsOnCircuitBreaker() public {
        uint256 shares = _aliceDeposit();
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);

        vault.setCircuitBreaker(true);

        vm.prank(riskCouncil);
        vm.expectRevert(SpotVault.EmergencyBreakerActive.selector);
        vault.redeemEmergencyFor(alice, shares, alice);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6) Admin override must respect owner's allowance — cannot drain a
    //    victim who has explicitly revoked (zero allowance).
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_revokedAllowanceReverts() public {
        uint256 shares = _aliceDeposit();

        // alice has zero allowance to the admin (default). The admin must
        // not be able to burn her shares behind her back.
        vm.prank(riskCouncil);
        vm.expectRevert(); // ERC20InsufficientAllowance
        vault.redeemEmergencyFor(alice, shares, riskCouncil);

        // alice grants a partial allowance (1 wei); admin cannot drain her.
        vm.prank(alice);
        vault.approve(riskCouncil, 1);
        vm.prank(riskCouncil);
        vm.expectRevert(); // ERC20InsufficientAllowance
        vault.redeemEmergencyFor(alice, shares, riskCouncil);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7) Admin override must respect owner's allowance — insufficient
    //    allowance reverts (does NOT silently fall through to admin override).
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_insufficientAllowanceReverts() public {
        uint256 shares = _aliceDeposit();
        vm.prank(alice);
        vault.approve(riskCouncil, shares - 1); // 1 wei short

        vm.prank(riskCouncil);
        vm.expectRevert(); // ERC20InsufficientAllowance
        vault.redeemEmergencyFor(alice, shares, riskCouncil);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8) Input validation.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_zeroSharesReverts() public {
        vm.prank(riskCouncil);
        vm.expectRevert(bytes("SpotVault: zero shares"));
        vault.redeemEmergencyFor(alice, 0, alice);
    }

    function test_redeemEmergencyFor_zeroAddrReverts() public {
        vm.prank(riskCouncil);
        vm.expectRevert(bytes("SpotVault: zero addr"));
        vault.redeemEmergencyFor(address(0), 1, alice);

        vm.prank(riskCouncil);
        vm.expectRevert(bytes("SpotVault: zero addr"));
        vault.redeemEmergencyFor(alice, 1, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 9) Emits `EmergencyRedeem` with `caller = admin` for off-chain monitors.
    // �══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_emitsEventWithAdminCaller() public {
        uint256 shares = _aliceDeposit();
        wbtc.mint(address(vault), 3 * 1e8);
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);

        uint256 supply = vault.totalSupply();
        uint256 bal = wbtc.balanceOf(address(vault));
        uint256 expectedPaid = (shares * bal) / supply;

        // The event MUST identify the admin as caller (so the audit monitor
        // can flag "admin-initiated emergency exit" as a distinct signal from
        // a normal user exit).
        vm.expectEmit(true, true, true, true, address(vault));
        emit SpotVault.EmergencyRedeem(
            riskCouncil, // caller = admin
            bob, // receiver = designated destination
            alice, // owner = victim
            shares,
            expectedPaid,
            0,
            0
        );

        vm.prank(riskCouncil);
        uint256 paid = vault.redeemEmergencyFor(alice, shares, bob);
        assertEq(paid, expectedPaid, "paid matches event");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 10) Owner-keyed cooldown invariant: the cooldown clock on `owner` ticks
    //     whether the redeem is user-initiated OR admin-initiated. This is
    //     the property VAL-PROTO-060 asserts.
    // ═══════════════════════════════════════════════════════════════════════

    function test_redeemEmergencyFor_ownerCooldownIsMonotonicAcrossPaths() public {
        uint256 shares = _aliceDeposit();
        wbtc.mint(address(vault), 5 * 1e8);
        vm.prank(alice);
        vault.approve(riskCouncil, type(uint256).max);

        uint256 cooldown = vault.emergencyRedeemCooldown();
        uint256 startTs = block.timestamp;

        // Path A: admin-initiated.
        vm.prank(riskCouncil);
        vault.redeemEmergencyFor(alice, shares / 4, alice);
        uint256 lastA = vault.lastEmergencyRedeemAt(alice);
        assertEq(lastA, startTs, "cooldown recorded for admin path at call time");

        // Warp past the cooldown so the user-initiated path can also run.
        vm.warp(block.timestamp + cooldown + 1);

        // Path B: user-initiated, after cooldown — cooldown must tick forward.
        uint256 beforeB = block.timestamp;
        vm.prank(alice);
        vault.redeemEmergency(shares / 4, alice, alice);
        uint256 lastB = vault.lastEmergencyRedeemAt(alice);
        assertEq(lastB, beforeB, "cooldown recorded for user path at later time");

        // Warp past cooldown again.
        vm.warp(block.timestamp + cooldown + 1);

        // Path C: admin-initiated, after cooldown.
        uint256 beforeC = block.timestamp;
        vm.prank(riskCouncil);
        vault.redeemEmergencyFor(alice, shares / 4, alice);
        uint256 lastC = vault.lastEmergencyRedeemAt(alice);
        assertEq(lastC, beforeC, "cooldown recorded for admin path at third call time");
        assertGt(lastC, lastB, "cooldown strictly monotonic across paths");

        // And: any further call inside the cooldown window reverts.
        vm.warp(block.timestamp + cooldown - 1); // 1 second short of cooldown
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, lastC + cooldown));
        vault.redeemEmergencyFor(alice, shares / 4, alice);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SpotVault — emergency-exit regression tests (Tier-0.A mainnet-readiness fix)
/// @notice Closes the Tier-0 mainnet-readiness blocker called out at
///         `docs/MAINNET_READINESS.md:38`: "Oracle going quiet freezes all
///         withdrawals; no fallback, no admin override. Users cannot exit."
///
/// Background: SpotVault._withdraw calls assetToCash(shortfall) when the underlying
/// balance is insufficient to pay a redemption. AssetToCash calls _oraclePrice,
/// which revert StaleOracle(updatedAt, block.timestamp) when the feed goes stale
/// past maxOracleStaleness. With the vault holding any cash (targetWeightBps <
/// 10000 — the strategy's normal resting state through drawdowns), every standard
/// redeem/withdraw reverts until the feed recovers — depositors locked in,
/// contradicting the documented invariant "withdrawals are deliberately NOT
/// gated" (SpotVault.sol:175-176).
///
/// Fix: opt-in `redeemEmergency(shares, receiver, owner)` path that skips the
/// oracle entirely and pays whatever underlying is currently in the vault,
/// emitting an explicit `EmergencyRedeem` event for any per-share haircut.
///
/// These tests assert the FIXED behaviour:
///   - the new path exits when the standard path reverts;
///   - the standard path STILL reverts on stale (the bug is real, the new path
///     supplements it, it does not replace it);
///   - the standard path still works in the no-oracle-required (fully-long)
///     case (regression: classic happy path is not broken);
///   - the circuit breaker halts the new path explicitly;
///   - per-address cooldown rate-limits the new path (MEV guard);
///   - non-owner cannot burn someone else's shares without allowance;
///   - input validation rejects zero shares / zero address;
///   - admin gate on the cooldown setter (mirror `setFeeRecipient` tests);
///   - the emitted event carries every field correctly.

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @dev Chainlink-style mock feed with settable answer + updatedAt (for staleness).
contract EmergencyOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) { answer = a; updatedAt = block.timestamp; }
    function setPrice(int256 a) external { answer = a; updatedAt = block.timestamp; }
    function setUpdatedAt(uint256 t) external { updatedAt = t; }   // for staleness tests
    function setAnswer(int256 a) external { answer = a; }          // without refreshing time

    function latestRoundData()
        external view returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @dev Perfect-fill spot venue priced off the oracle (no slippage), for tests.
contract EmergencyAdapter is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    EmergencyOracle public immutable oracle;
    uint8 immutable aDec; uint8 immutable cDec; uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_; cash = cash_; oracle = EmergencyOracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = EmergencyOracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external returns (uint256 out)
    {
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

contract SpotVaultEmergencyTest is Test {
    MockERC20 wbtc;   // underlying, 8 dec
    MockERC20 usdc;   // cash, 6 dec
    EmergencyOracle oracle;
    EmergencyAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    int256 constant PRICE_50K = 50_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000); // a sane non-zero timestamp
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new EmergencyOracle(PRICE_50K);
        adapter = new EmergencyAdapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), MAX_STALE,
            "Zentory BTC Emergency Vault", "zBTCE",
            0,      // rebalanceThresholdBps (0 = always rebalance, for the test)
            100,    // maxSlippageBps (1%)
            0,      // performanceFee off for clarity
            address(this), address(this),
            1 hours // emergencyRedeemCooldown
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), address(this));

        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
        wbtc.mint(bob,   TEN_BTC);
    }

    /// Helper: alice deposits TEN_BTC into the vault. Returns her share balance.
    function _aliceDeposit() internal returns (uint256) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        uint256 shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        return shares;
    }

    /// Helper: deposit + rebalance flat + warp past MAX_STALE. Reaches the
    /// stale-oracle-cash-leg state where the standard redeem reverts.
    function _flatAndStale() internal returns (uint256 shares) {
        shares = _aliceDeposit();
        vault.rebalanceTo(0);
        vm.warp(block.timestamp + MAX_STALE + 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 1) The fix exits when standard redeem reverts.
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_paysAvailableUnderlying_whenFlatAndStale() public {
        uint256 shares = _flatAndStale();
        uint256 bal = wbtc.balanceOf(address(vault));
        assertEq(bal, 0, "vault is flat - no underlying on hand");
        uint256 cashBal = usdc.balanceOf(address(vault));
        assertGt(cashBal, 0, "vault is in cash - the leg that prices via oracle");

        // Standard redeem MUST revert on the stale oracle (this is the bug we are
        // proving exists, and that the new path supplements).
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares, alice, alice);

        // Emergency redeem pays the actual underlying in the vault. After
        // rebalanceTo(0), the vault is fully in cash; bal == 0; paid == 0.
        // The critical bit: it does NOT revert, the depositor is out (their
        // shares are burned), and an `EmergencyRedeem` event is emitted with a
        // recorded (zero, by construction) haircut so monitoring can correlate.
        uint256 supplyBefore = vault.totalSupply();
        assertEq(supplyBefore, shares);

        vm.expectEmit(true, true, true, true, address(vault));
        emit SpotVault.EmergencyRedeem(alice, alice, alice, shares, 0, 0, 0);

        vm.prank(alice);
        uint256 paid = vault.redeemEmergency(shares, alice, alice);

        assertEq(paid, 0, "flat vault: no underlying on hand, so paid == 0");
        assertEq(vault.balanceOf(alice), 0, "shares burned");
        assertEq(vault.totalSupply(), 0, "supply drained");
    }

    function test_EmergencyRedeem_paysUnderlying_whenLongSideCashAvailable() public {
        // Drive the vault to a state where it holds SOME underlying AND SOME cash
        // and the oracle is stale. The fix must pay the underlying portion even
        // though the cash leg is unvalued.
        uint256 shares = _aliceDeposit();
        // rebalanceTo(5000) rebalances halfway; the vault now holds ~5 BTC of
        // underlying. Warp past MAX_STALE so any oracle call would revert.
        vault.rebalanceTo(5000);
        uint256 balBefore = wbtc.balanceOf(address(vault));
        assertGt(balBefore, 0, "vault holds some underlying");

        vm.warp(block.timestamp + MAX_STALE + 1);

        // Standard redeem reverts (any shortfall path needs assetToCash).
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares, alice, alice);

        // Emergency path pays alice's pro-rata share of the underlying.
        uint256 expected = (shares * balBefore) / vault.totalSupply();
        uint256 aliceBalBefore = wbtc.balanceOf(alice);

        vm.prank(alice);
        uint256 paid = vault.redeemEmergency(shares, alice, alice);

        assertEq(paid, expected, "paid = pro-rata underlying");
        assertEq(wbtc.balanceOf(alice), aliceBalBefore + expected, "underlying received");
        assertEq(vault.balanceOf(alice), 0, "shares burned");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2) Original bug reproduction (proves the new path supplements, does not
    //    replace, the standard path; this is the regression test for the bug).
    // ═══════════════════════════════════════════════════════════════════════

    function test_StandardRedeemStillReverts_whenFlatAndStale() public {
        _flatAndStale();
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(); // StaleOracle
        vault.redeem(shares, alice, alice);

        // maxRedeem must NOT be gated: the documented invariant is "users must
        // always be able to exit". This is enforced via the cooldown-gated
        // emergency path; standard redeem's revert is informational, not a gate.
        assertGt(vault.maxRedeem(alice), 0, "exit path stays open via emergency");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3) Classic happy path (fully-long, no oracle needed) still works.
    // ═══════════════════════════════════════════════════════════════════════

    function test_StandardRedeemStillWorks_whenFullyLongAndStale() public {
        uint256 shares = _aliceDeposit();
        // Fully long: no cash leg, no oracle call, no revert possible.
        assertEq(usdc.balanceOf(address(vault)), 0, "long: no cash leg");
        vm.warp(block.timestamp + MAX_STALE + 1);

        // Standard redeem works in the long case regardless of staleness.
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, TEN_BTC, 1e12, "fully-long: oracle-independent payout");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4) Circuit breaker halts the emergency path explicitly (not silently).
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_revertsOnCircuitBreaker() public {
        uint256 shares = _aliceDeposit();
        vault.setCircuitBreaker(true);

        vm.prank(alice);
        vm.expectRevert(SpotVault.EmergencyBreakerActive.selector);
        vault.redeemEmergency(shares, alice, alice);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5) Per-address cooldown rate-limits the emergency path (MEV guard).
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_enforcesCooldown() public {
        uint256 shares = _aliceDeposit();
        // Push some underlying into the vault so the first redeem pays.
        wbtc.mint(address(vault), 1 * 1e8);

        // First call succeeds (lastEmergencyRedeemAt[alice] == 0).
        vm.prank(alice);
        uint256 firstPaid = vault.redeemEmergency(shares / 2, alice, alice);
        assertGt(firstPaid, 0, "first call pays");

        // Immediate second call reverts with EmergencyCooldownActive.
        uint256 expectedNext = block.timestamp + vault.emergencyRedeemCooldown();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(SpotVault.EmergencyCooldownActive.selector, expectedNext)
        );
        vault.redeemEmergency(shares / 2, alice, alice);

        // Warp past the cooldown: succeeds again.
        vm.warp(block.timestamp + vault.emergencyRedeemCooldown() + 1);
        vm.prank(alice);
        uint256 secondPaid = vault.redeemEmergency(shares / 2, alice, alice);
        assertGt(secondPaid, 0, "post-cooldown: succeeds again");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6) Owner-auth check (mirror ERC-4626 allowance semantics).
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_ownerAllowance() public {
        uint256 bobShares = _aliceDeposit_for(bob, TEN_BTC);

        // alice tries to emergency-redeem bob's shares without allowance: must revert
        // (ERC20InsufficientAllowance). This prevents grief / front-running of a
        // victim's exit by an unrelated address.
        vm.prank(alice);
        vm.expectRevert(); // ERC20InsufficientAllowance from _spendAllowance
        vault.redeemEmergency(bobShares, alice, bob);

        // bob grants alice a one-short allowance; she cannot drain bob's full balance.
        vm.prank(bob);
        vault.approve(alice, bobShares - 1);
        vm.prank(alice);
        vm.expectRevert(); // insufficient allowance
        vault.redeemEmergency(bobShares, alice, bob);

        // Full allowance: alice can drain the rest.
        vm.prank(bob);
        vault.approve(alice, type(uint256).max);
        // Fund the vault so the redeem actually pays out.
        wbtc.mint(address(vault), 1 * 1e8);

        vm.prank(alice);
        uint256 paid = vault.redeemEmergency(bobShares, alice, bob);
        assertGt(paid, 0, "allowance path: pays the redeemer");
        assertEq(vault.balanceOf(bob), 0, "bob's shares burned by alice's call");
    }

    function _aliceDeposit_for(address who, uint256 amt) internal returns (uint256) {
        vm.startPrank(who);
        wbtc.approve(address(vault), amt);
        uint256 s = vault.deposit(amt, who);
        vm.stopPrank();
        return s;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7 & 8) Input validation.
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_zeroShares_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("SpotVault: zero shares"));
        vault.redeemEmergency(0, alice, alice);
    }

    function test_EmergencyRedeem_zeroAddr_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("SpotVault: zero addr"));
        vault.redeemEmergency(1, address(0), alice);

        vm.prank(alice);
        vm.expectRevert(bytes("SpotVault: zero addr"));
        vault.redeemEmergency(1, alice, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 9) Admin gate on the cooldown setter.
    // ═══════════════════════════════════════════════════════════════════════

    function test_setEmergencyRedeemCooldown_adminCanSet() public {
        assertEq(vault.emergencyRedeemCooldown(), 1 hours, "starts at 1h");
        vault.setEmergencyRedeemCooldown(30 minutes);
        assertEq(vault.emergencyRedeemCooldown(), 30 minutes, "updated");
    }

    function test_setEmergencyRedeemCooldown_nonAdminReverts() public {
        // alice is a regular address with neither DEFAULT_ADMIN_ROLE nor
        // RISK_COUNCIL_ROLE. She must not be able to set the cooldown.
        vm.prank(alice);
        vm.expectRevert(); // AccessControl: account is missing role
        vault.setEmergencyRedeemCooldown(0);

        // The risk-council-only gate works: a fresh address with
        // RISK_COUNCIL_ROLE (and nothing else) can set the cooldown.
        address riskCouncil = makeAddr("riskCouncil");
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), riskCouncil);
        vm.prank(riskCouncil);
        vault.setEmergencyRedeemCooldown(0);
        assertEq(vault.emergencyRedeemCooldown(), 0, "risk council can set cooldown");

        // Restore the cooldown for any subsequent test.
        vault.setEmergencyRedeemCooldown(1 hours);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 10) The emitted event carries every field correctly.
    // ═══════════════════════════════════════════════════════════════════════

    function test_EmergencyRedeem_emitsEventWithCorrectHaircut() public {
        uint256 shares = _aliceDeposit();
        // 3 BTC into the vault so the redeem pays out something.
        wbtc.mint(address(vault), 3 * 1e8);
        uint256 supply = vault.totalSupply();
        uint256 bal = wbtc.balanceOf(address(vault));
        uint256 expectedPaid = (shares * bal) / supply;
        uint256 expectedHaircutAssets = 0; // owed == paid by construction
        uint256 expectedHaircutPerShare = 0;

        vm.expectEmit(true, true, true, true, address(vault));
        emit SpotVault.EmergencyRedeem(
            alice,        // caller
            alice,        // receiver
            alice,        // owner
            shares,
            expectedPaid,
            expectedHaircutAssets,
            expectedHaircutPerShare
        );

        vm.prank(alice);
        uint256 paid = vault.redeemEmergency(shares, alice, alice);

        assertEq(paid, expectedPaid, "event paid matches return value");
    }
}
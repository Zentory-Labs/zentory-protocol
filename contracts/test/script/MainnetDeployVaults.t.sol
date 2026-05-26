// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {zSOLVault} from "../../src/vaults/zSOLVault.sol";

/// @notice Mock 9-decimal token, matching how WSOL is wrapped on HyperEVM.
///         The whole bug we're guarding against was a script that minted
///         100 * 10^18 raw units into a 9-decimal token's vault, so this
///         test uses the same shape on purpose.
contract MockWSOL is ERC20 {
    constructor() ERC20("Mock WSOL", "WSOL") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 9; }
}

/// @notice MainnetDeployVaults invariant tests.
///
///         We do NOT spin up the whole forge-script harness — that requires
///         env-var plumbing that's awkward in unit tests. Instead we replicate
///         the script's invariant logic (the parts that matter) as raw calls
///         against a real BaseVault and assert that:
///
///           - The happy path (deposit, correct decimals, correct amount)
///             leaves the invariant intact.
///
///           - The broken path that bit us on testnet (raw transfer with
///             wrong decimals) creates an asset/share gap that the script's
///             invariant check would catch.
///
///         If we ever change the seeding rules, these tests should be the
///         first thing that breaks.
contract MainnetDeployVaultsInvariantTest is Test {
    MockWSOL wsol;
    zSOLVault vault;

    address deployer = makeAddr("deployer");
    address admin = makeAddr("admin");
    address feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant TOLERANCE = 1;

    function setUp() public {
        wsol = new MockWSOL();
        vault = new zSOLVault(address(wsol), feeRecipient, admin);
    }

    // ─── Happy path: 100 WSOL (9 dec) via deposit() ─────────────────────

    function test_seed_happy_path_via_deposit() external {
        // Pre-conditions enforced by the script.
        assertEq(wsol.balanceOf(address(vault)), 0, "pre: balance != 0");
        assertEq(vault.totalSupply(), 0, "pre: shares != 0");
        assertEq(vault.totalAssets(), 0, "pre: totalAssets != 0");
        assertEq(vault.asset(), address(wsol), "pre: asset mismatch");

        // Correct seed: 100 WSOL = 100 * 10^9 raw units.
        uint256 amount = 100 * 10**9;
        wsol.mint(deployer, amount);

        vm.startPrank(deployer);
        wsol.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, deployer);
        vm.stopPrank();

        // Post-conditions.
        assertGt(shares, 0, "shares zero");
        uint256 ts = vault.totalSupply();
        uint256 ta = vault.totalAssets();
        uint256 reconstructed = vault.convertToAssets(ts);
        uint256 gap = reconstructed > ta ? reconstructed - ta : ta - reconstructed;
        assertLe(gap, TOLERANCE, "invariant violated on happy path");
        assertEq(wsol.balanceOf(address(vault)), amount, "vault balance mismatch");
    }

    // ─── The bug: 100 * 10^18 raw units via deposit() ────────────────────

    function test_seed_with_wrong_decimals_still_balances() external {
        // Even if the operator pastes the WRONG amount (100e18 instead of
        // 100e9), going through deposit() still mints shares 1:1 with the
        // assets they deposited. The vault doesn't end up broken — it ends
        // up over-funded but internally consistent.
        //
        // This is the key insight that motivates the script: deposit()
        // cannot create the assets-without-shares state. Raw transfer can.
        uint256 wrongAmount = 100 * 10**18; // 100 billion WSOL by mistake
        wsol.mint(deployer, wrongAmount);

        vm.startPrank(deployer);
        wsol.approve(address(vault), wrongAmount);
        uint256 shares = vault.deposit(wrongAmount, deployer);
        vm.stopPrank();

        assertGt(shares, 0);
        // Invariant still holds — vault is overfunded but consistent.
        uint256 ts = vault.totalSupply();
        uint256 ta = vault.totalAssets();
        uint256 reconstructed = vault.convertToAssets(ts);
        uint256 gap = reconstructed > ta ? reconstructed - ta : ta - reconstructed;
        assertLe(gap, TOLERANCE, "deposit() should never break the invariant");
    }

    // ─── The actual testnet bug: raw transfer breaks invariant ──────────

    function test_seed_via_raw_transfer_breaks_invariant() external {
        // Reproduces the testnet bug: tokens transferred directly to the
        // vault address. totalAssets() goes up, totalSupply() stays zero.
        // convertToAssets(0) is 0; totalAssets() is nonzero. Invariant
        // catches it.
        uint256 wrongAmount = 100 * 10**18;
        wsol.mint(address(this), wrongAmount);
        IERC20(address(wsol)).transfer(address(vault), wrongAmount);

        uint256 ts = vault.totalSupply();
        uint256 ta = vault.totalAssets();
        uint256 reconstructed = vault.convertToAssets(ts);
        uint256 gap = reconstructed > ta ? reconstructed - ta : ta - reconstructed;

        // The gap should be ENORMOUS — that's the bug the script blocks.
        assertEq(ts, 0, "no shares");
        assertGt(ta, 0, "but assets");
        assertGt(gap, TOLERANCE, "invariant should be violated");
    }

    // ─── Pre-condition: vault must be empty before seeding ───────────────

    function test_precondition_zero_balance_required() external {
        // Pre-leak: someone transferred tokens to the vault before the
        // deploy script ran. The script must abort.
        wsol.mint(address(this), 1);
        IERC20(address(wsol)).transfer(address(vault), 1);

        // What the script would do:
        bool ok = wsol.balanceOf(address(vault)) == 0;
        assertFalse(ok, "pre-condition should fail when balance is non-zero");
    }
}

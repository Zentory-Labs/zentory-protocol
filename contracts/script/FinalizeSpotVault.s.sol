// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title FinalizeSpotVault
/// @notice Idempotent bring-up / reserve top-up for a SHADOW-mode SpotVault.
///
///         NOTE: DeploySpotVault already performs first-time finalize (grants
///         VAULT_ROLE, funds both adapter reserve legs, seeds the first deposit),
///         so on a fresh deploy this script is a no-op that just confirms state.
///         Its real ongoing use is RESERVE TOP-UP: every rebalance consumes one
///         adapter leg (long→flat drains WBTC into the vault as cash; flat→long
///         drains the cash leg), so re-run this to mint each leg back up to its
///         floor. Safe to run any number of times — each step is conditional:
///
///           1. grant VAULT_ROLE on the adapter -> vault   (skipped if already held)
///           2. top up each adapter reserve leg to its floor (mints only the
///              shortfall; skipped if already at/above floor)
///           3. seed the first deposit                      (only if vault has no shares)
///
/// TESTNET ONLY. The mocks (ShadowUSDC, WBTC mock) have open mints; mainnet uses
/// real USDC + a real audited spot adapter and this script does not apply.
contract FinalizeSpotVault is Script {
    bytes32 internal constant VAULT_ROLE = keccak256("VAULT_ROLE");

    function run() external {
        require(block.chainid == 998, "FinalizeSpotVault: not HyperEVM testnet (998)");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address vault   = vm.envAddress("SPOT_VAULT");    // deployed SpotVault
        address adapter = vm.envAddress("SWAP_ADAPTER");  // ShadowSpotAdapter
        address cash    = vm.envAddress("CASH");          // sUSDC (6 dec)
        address under   = vm.envAddress("UNDERLYING");    // WBTC mock (8 dec) = vault asset

        // Reserve floors + seed size, env-overridable. Defaults sized for a ~$70k
        // BTC testnet demo: enough cash to buy the vault fully out of WBTC and
        // enough WBTC to sell back, with a tiny first deposit.
        uint256 cashFloor  = vm.envOr("CASH_RESERVE",  uint256(50_000_000) * 1e6); // 50,000,000 sUSDC
        uint256 underFloor = vm.envOr("UNDER_RESERVE", uint256(1_000) * 1e8);      // 1,000 WBTC
        uint256 seed       = vm.envOr("SEED_ASSETS",   uint256(1e6));              // 0.01 WBTC (8 dec)

        // Decide what (if anything) needs doing — read-only.
        bool needRole = !IAccessControl(adapter).hasRole(VAULT_ROLE, vault);
        uint256 cashBal  = IERC20(cash).balanceOf(adapter);
        uint256 underBal = IERC20(under).balanceOf(adapter);
        uint256 cashTopUp  = cashBal  < cashFloor  ? cashFloor  - cashBal  : 0;
        uint256 underTopUp = underBal < underFloor ? underFloor - underBal : 0;
        bool needSeed = IERC20Min(vault).totalSupply() == 0;

        console2.log("== Plan ==");
        console2.log("grant VAULT_ROLE -> vault:", needRole);
        console2.log("sUSDC reserve top-up:", cashTopUp);
        console2.log("WBTC reserve top-up: ", underTopUp);
        console2.log("seed first deposit:  ", needSeed);

        vm.startBroadcast(pk);

        if (needRole) IAccessControl(adapter).grantRole(VAULT_ROLE, vault);
        if (cashTopUp  > 0) IMintable(cash).mint(adapter, cashTopUp);
        if (underTopUp > 0) IMintable(under).mint(adapter, underTopUp);
        if (needSeed) {
            IMintable(under).mint(deployer, seed);
            IERC20(under).approve(vault, seed);
            IERC4626Min(vault).deposit(seed, deployer);
        }

        vm.stopBroadcast();

        console2.log("== Done ==");
        if (!needRole && cashTopUp == 0 && underTopUp == 0 && !needSeed) {
            console2.log("Nothing to do: vault finalized + reserves at/above floor. SpotVault is LIVE.");
        }
    }
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IERC20Min {
    function totalSupply() external view returns (uint256);
}

interface IERC4626Min {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

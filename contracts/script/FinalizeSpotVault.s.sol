// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title FinalizeSpotVault
/// @notice One-shot bring-up for a freshly deployed SHADOW-mode SpotVault. Run
///         once, AFTER DeploySpotVault, with the deployer key (admin on the
///         adapter + open-mint on the testnet mocks). It performs the three
///         steps the vault needs before deposits work end-to-end:
///
///           1. grantRole(VAULT_ROLE) on the adapter -> the vault (so the vault
///              is the only caller allowed to drive swaps; without it every
///              rebalance reverts onlyRole).
///           2. Fund BOTH adapter reserve legs (sUSDC + WBTC) so it can fill
///              long->flat (pay cash) AND flat->long (pay asset).
///           3. Seed the first deposit so the ERC4626 share price is anchored
///              (belt-and-suspenders over the virtual-shares inflation guard).
///
/// Idempotency: the seed step reverts if the vault already has shares, so a
/// double-run can't silently re-seed. Reserves can be topped up later with a
/// plain `cast send <token> "mint(address,uint256)" <adapter> <amt>`.
///
/// TESTNET ONLY. The mocks (ShadowUSDC, WBTC mock) have open mints; mainnet
/// uses real USDC + a real audited spot adapter and this script does not apply.
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

        // Reserve + seed sizing, env-overridable. Defaults sized for a ~$70k BTC
        // testnet demo: enough cash to buy the whole vault out of WBTC and enough
        // WBTC to sell back, with a tiny first deposit.
        uint256 cashReserve  = vm.envOr("CASH_RESERVE",  uint256(50_000_000) * 1e6); // 50,000,000 sUSDC
        uint256 underReserve = vm.envOr("UNDER_RESERVE", uint256(1_000) * 1e8);      // 1,000 WBTC
        uint256 seed         = vm.envOr("SEED_ASSETS",   uint256(1e6));              // 0.01 WBTC (8 dec)

        require(
            IERC20Min(vault).totalSupply() == 0,
            "FinalizeSpotVault: vault already seeded (totalSupply != 0) - aborting to avoid double-seed"
        );

        console2.log("== Inputs ==");
        console2.log("deployer:", deployer);
        console2.log("vault:   ", vault);
        console2.log("adapter: ", adapter);

        vm.startBroadcast(pk);

        // 1) let the vault drive the adapter
        IAccessControl(adapter).grantRole(VAULT_ROLE, vault);

        // 2) fund BOTH legs
        IMintable(cash).mint(adapter, cashReserve);
        IMintable(under).mint(adapter, underReserve);

        // 3) seed the first deposit
        IMintable(under).mint(deployer, seed);
        IERC20(under).approve(vault, seed);
        uint256 shares = IERC4626Min(vault).deposit(seed, deployer);

        vm.stopBroadcast();

        console2.log("== Logs ==");
        console2.log("VAULT_ROLE -> vault granted on adapter");
        console2.log("adapter sUSDC reserve:", cashReserve);
        console2.log("adapter WBTC reserve: ", underReserve);
        console2.log("seed assets (WBTC):   ", seed);
        console2.log("seed shares minted:   ", shares);
        console2.log("SpotVault is LIVE: deposits/redeems + signal-driven rebalance loop enabled.");
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

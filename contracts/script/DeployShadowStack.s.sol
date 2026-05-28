// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ShadowUSDC} from "../src/shadow/ShadowUSDC.sol";
import {ShadowPriceOracle} from "../src/shadow/ShadowPriceOracle.sol";
import {ShadowSpotAdapter} from "../src/shadow/ShadowSpotAdapter.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys the testnet SHADOW stack that lets SpotVault run end-to-end
///         without a real Hyperliquid spot integration:
///           - ShadowUSDC      (testnet cash leg, 6 decimals)
///           - ShadowPriceOracle (Chainlink-compatible, keeper-pushed price)
///           - ShadowSpotAdapter (swaps at oracle price, holds reserves)
///         Grants UPDATER_ROLE on the oracle to KEEPER so the keeper bot can
///         push 4H prices alongside its existing settle loop. Run DeploySpotVault
///         next with CASH=<sUSDC>, ORACLE=<this oracle>, SWAP_ADAPTER=<this adapter>,
///         then grant the adapter's VAULT_ROLE to the deployed SpotVault.
///
/// Required env:
///   PRIVATE_KEY, UNDERLYING
/// Optional:
///   KEEPER_ADDRESS (def deployer), INITIAL_PRICE_USD_8DEC (def 7_000_000_000_000 = $70k),
///   SIMULATED_SLIPPAGE_BPS (def 10 = 0.1%)
///
/// !!! NOT FOR MAINNET. Replace ShadowSpotAdapter with the production
/// !!! CoreWriter spot adapter (audited) before any real capital.
contract DeployShadowStack is Script {
    function run() external {
        requireChainFromEnv();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address underlying = vm.envAddress("UNDERLYING");
        address keeper = vm.envOr("KEEPER_ADDRESS", deployer);
        int256 initPx = int256(vm.envOr("INITIAL_PRICE_USD_8DEC", uint256(70_000 * 1e8)));
        uint16 simSlip = uint16(vm.envOr("SIMULATED_SLIPPAGE_BPS", uint256(10)));

        console2.log("Deployer:", deployer);
        console2.log("Keeper:  ", keeper);
        console2.log("Underlying:", underlying);
        console2.log("Initial price (USD, 8dec):", uint256(initPx));
        console2.log("Simulated slippage (bps):", simSlip);
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(deployerKey);

        ShadowUSDC usdc = new ShadowUSDC();
        ShadowPriceOracle oracle = new ShadowPriceOracle(8, initPx, deployer);
        ShadowSpotAdapter adapter =
            new ShadowSpotAdapter(underlying, address(usdc), address(oracle), simSlip, deployer);

        // Keeper can push 4H prices.
        oracle.grantRole(oracle.UPDATER_ROLE(), keeper);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SHADOW STACK DEPLOYED ===");
        console2.log("CASH (sUSDC):    ", address(usdc));
        console2.log("ORACLE:          ", address(oracle));
        console2.log("SWAP_ADAPTER:    ", address(adapter));
        console2.log("");
        console2.log("NEXT:");
        console2.log(" 1) Fund the adapter: mint sUSDC + UNDERLYING reserves to it.");
        console2.log(" 2) Run DeploySpotVault with CASH/ORACLE/SWAP_ADAPTER above.");
        console2.log(" 3) Grant VAULT_ROLE on the adapter to the deployed SpotVault.");
        console2.log(" 4) Have the keeper push prices: oracle.setPrice(...) every 4H.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {SpotVault} from "../src/vaults/SpotVault.sol";
import {HyperSwapRouterAdapter} from "../src/adapters/HyperSwapRouterAdapter.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Turnkey deploy of the production v1 spot stack — a HyperSwapRouterAdapter
///         (atomic DEX router) + a SpotVault — and wires the full SIGNED rebalance
///         loop in one broadcast:
///
///         depositor → SpotVault  ←(rebalanceTo, KEEPER_ROLE)─  StrategyExecutor.executeRebalance
///                        │                                          ▲ (signed by GP engine)
///                        └─ swap(asset⇄cash) ─→ HyperSwapRouterAdapter ─→ HyperSwap V3 router
///
///         Wiring performed:
///           1) adapter.VAULT_ROLE  → vault          (vault may swap through the adapter)
///           2) vault.swapAdapter   = adapter         (vault routes spot via the adapter)
///           3) vault.KEEPER_ROLE   → StrategyExecutor (signed executeRebalance can rebalance)
///           4) vault.KEEPER_ROLE   → KEEPER_ADDRESS  (optional EOA for manual ops)
///           5) vault.RISK_COUNCIL_ROLE → deployer    (move to risk multisig later)
///
/// Required env:
///   EXPECTED_CHAIN_ID, PRIVATE_KEY, UNDERLYING, CASH, ORACLE, ROUTER, FEE_TIER,
///   STRATEGY_EXECUTOR
/// Optional env (sensible defaults):
///   KEEPER_ADDRESS (none), FEE_RECIPIENT (deployer), VAULT_NAME, VAULT_SYMBOL,
///   MAX_ORACLE_STALENESS (3600 — MATCH THE FEED HEARTBEAT),
///   REBALANCE_THRESHOLD_BPS (200), MAX_SLIPPAGE_BPS (100), PERFORMANCE_FEE_BPS (2000)
///
/// Run:
///   forge script script/DeploySpotStack.s.sol --rpc-url $RPC --broadcast
///
/// @dev ROUTER must be the real HyperSwap V3 SwapRouter on the target chain and
///      FEE_TIER the deepest UNDERLYING/CASH pool's fee (e.g. 500 = 0.05%). The
///      adapter is venue-pluggable: a CoreWriter spot adapter (v2) can replace it
///      later via SpotVault.setSwapAdapter without redeploying the vault.
contract DeploySpotStack is Script {
    function run() external {
        requireChainFromEnv();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address underlying = vm.envAddress("UNDERLYING");
        address cash       = vm.envAddress("CASH");
        address oracle     = vm.envAddress("ORACLE");
        address router     = vm.envAddress("ROUTER");
        uint24  feeTier    = uint24(vm.envUint("FEE_TIER"));
        address executor   = vm.envAddress("STRATEGY_EXECUTOR");
        address keeper     = vm.envOr("KEEPER_ADDRESS", address(0));
        address feeRecip   = vm.envOr("FEE_RECIPIENT", deployer);

        string memory name_   = vm.envOr("VAULT_NAME", string("Zentory BTC Spot Vault"));
        string memory symbol_ = vm.envOr("VAULT_SYMBOL", string("zBTCs"));

        uint256 maxStale = vm.envOr("MAX_ORACLE_STALENESS", uint256(3600));
        uint16 threshBps = uint16(vm.envOr("REBALANCE_THRESHOLD_BPS", uint256(200)));
        uint16 slipBps   = uint16(vm.envOr("MAX_SLIPPAGE_BPS", uint256(100)));
        uint256 feeBps   = vm.envOr("PERFORMANCE_FEE_BPS", uint256(2000));
        uint256 emergencyCooldown = vm.envOr("EMERGENCY_REDEEM_COOLDOWN", uint256(3600));

        console2.log("Deployer:        ", deployer);
        console2.log("Router:          ", router);
        console2.log("FeeTier:         ", uint256(feeTier));
        console2.log("Underlying:      ", underlying);
        console2.log("Cash:            ", cash);
        console2.log("Oracle:          ", oracle);
        console2.log("StrategyExecutor:", executor);
        console2.log("EmergencyCooldown (s):", emergencyCooldown);
        console2.log("Chain:           ", block.chainid);

        vm.startBroadcast(deployerKey);

        HyperSwapRouterAdapter adapter =
            new HyperSwapRouterAdapter(router, underlying, cash, feeTier, deployer);

        SpotVault vault = new SpotVault(
            underlying, cash, oracle, maxStale,
            name_, symbol_, threshBps, slipBps, feeBps, feeRecip, deployer,
            emergencyCooldown
        );

        // ── Wire the production loop ──────────────────────────────────────
        adapter.grantRole(adapter.VAULT_ROLE(), address(vault)); // 1
        vault.setSwapAdapter(address(adapter));                   // 2
        vault.grantRole(vault.KEEPER_ROLE(), executor);           // 3
        if (keeper != address(0)) {
            vault.grantRole(vault.KEEPER_ROLE(), keeper);         // 4
        }
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), deployer);     // 5

        vm.stopBroadcast();

        // ── Post-deploy assertions (abort before broadcast if wiring is wrong) ──
        require(address(vault.swapAdapter()) == address(adapter), "adapter not wired");
        require(adapter.hasRole(adapter.VAULT_ROLE(), address(vault)), "vault lacks adapter VAULT_ROLE");
        require(vault.hasRole(vault.KEEPER_ROLE(), executor), "executor lacks vault KEEPER_ROLE");

        console2.log("");
        console2.log("=== SPOT STACK DEPLOYED (v1: HyperSwap router) ===");
        console2.log("SWAP_ADAPTER=", address(adapter));
        console2.log("SPOT_VAULT=  ", address(vault));
        console2.log("");
        console2.log("NEXT (on the EXISTING StrategyExecutor, then ops):");
        console2.log(" - StrategyExecutor.setAuthorizedSigner(<GP engine signer>)");
        console2.log(" - StrategyExecutor.grantRole(KEEPER_ROLE, <keeper bot EOA>)");
        console2.log(" - seed vault with a first deposit (inflation-attack invariant)");
        console2.log(" - transfer vault admin + RISK_COUNCIL + adapter admin to the Safe");
        console2.log(" - add SPOT_VAULT to zentory-app/lib/contracts.ts (canonical vault)");
    }
}

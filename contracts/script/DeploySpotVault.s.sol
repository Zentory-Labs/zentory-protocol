// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {SpotVault} from "../src/vaults/SpotVault.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys a single SpotVault (BaseVault v2 — NAV reflects strategy PnL)
///         and wires its roles + swap adapter in one shot.
///
/// PREREQUISITES (deploy these first / have their addresses):
///   - SWAP_ADAPTER : a contract implementing ISpotSwapAdapter (the spot venue).
///       Production = Hyperliquid spot via CoreWriter (needs HyperCore docs +
///       audit). For testnet SHADOW mode, a mock adapter is fine (deposit/
///       withdraw/NAV work; rebalances just won't hit a real book).
///   - ORACLE       : a Chainlink-compatible underlying/USD feed (AggregatorV3).
///   - CASH         : the cash asset (USDC) ERC-20.
///   - UNDERLYING   : the vault's underlying ERC-20 (e.g. WBTC).
///
/// Required env:
///   PRIVATE_KEY, UNDERLYING, CASH, ORACLE, SWAP_ADAPTER
/// Optional env (sensible defaults):
///   KEEPER_ADDRESS (def deployer), FEE_RECIPIENT (def deployer),
///   VAULT_NAME, VAULT_SYMBOL,
///   MAX_ORACLE_STALENESS (def 3600 — MATCH THE FEED HEARTBEAT),
///   REBALANCE_THRESHOLD_BPS (def 200), MAX_SLIPPAGE_BPS (def 100),
///   PERFORMANCE_FEE_BPS (def 2000 = 20%)
///
/// Run:
///   forge script script/DeploySpotVault.s.sol --rpc-url $RPC \
///     --private-key $PRIVATE_KEY --broadcast
///
/// @dev Role wiring (learned from the signal-network deploy bug): admin = deployer
///      (transfer to governance post-setup); KEEPER_ROLE -> keeper bot so it can
///      call rebalanceTo/evaluateFees; RISK_COUNCIL_ROLE -> deployer (move to the
///      risk multisig later). setSwapAdapter requires DEFAULT_ADMIN_ROLE, so it is
///      called by the deployer within the same broadcast.
contract DeploySpotVault is Script {
    function run() external {
        requireChainFromEnv();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address underlying = vm.envAddress("UNDERLYING");
        address cash       = vm.envAddress("CASH");
        address oracle     = vm.envAddress("ORACLE");
        address adapter    = vm.envAddress("SWAP_ADAPTER");
        address keeper     = vm.envOr("KEEPER_ADDRESS", deployer);
        address feeRecip   = vm.envOr("FEE_RECIPIENT", deployer);

        string memory name_   = vm.envOr("VAULT_NAME", string("Zentory BTC Spot Vault"));
        string memory symbol_ = vm.envOr("VAULT_SYMBOL", string("zBTCs"));

        uint256 maxStale  = vm.envOr("MAX_ORACLE_STALENESS", uint256(3600));
        uint16 threshBps  = uint16(vm.envOr("REBALANCE_THRESHOLD_BPS", uint256(200)));
        uint16 slipBps    = uint16(vm.envOr("MAX_SLIPPAGE_BPS", uint256(100)));
        uint256 feeBps    = vm.envOr("PERFORMANCE_FEE_BPS", uint256(2000));

        console2.log("Deployer:", deployer);
        console2.log("Keeper:  ", keeper);
        console2.log("Underlying:", underlying);
        console2.log("Cash:", cash);
        console2.log("Oracle:", oracle);
        console2.log("SwapAdapter:", adapter);
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(deployerKey);

        SpotVault vault = new SpotVault(
            underlying, cash, oracle, maxStale,
            name_, symbol_, threshBps, slipBps, feeBps, feeRecip, deployer
        );
        console2.log("SpotVault deployed:", address(vault));

        // Wire: adapter (admin-only) + keeper role + risk council.
        vault.setSwapAdapter(adapter);
        vault.grantRole(vault.KEEPER_ROLE(), keeper);
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SPOT VAULT DEPLOYED ===");
        console2.log("SPOT_VAULT=", address(vault));
        console2.log("Post-deploy: add to zentory-app/lib/contracts.ts; seed via a");
        console2.log("first deposit (inflation-attack invariant); transfer admin +");
        console2.log("RISK_COUNCIL to the multisig; set keeper EPOCH cadence to 4H.");
    }
}

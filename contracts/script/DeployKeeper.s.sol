// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {HyperCoreAdapter} from "../src/keeper/HyperCoreAdapter.sol";
import {StrategyExecutor} from "../src/keeper/StrategyExecutor.sol";

/// @notice Deploys HyperCoreAdapter and StrategyExecutor (the keeper layer).
/// @dev Run standalone:
///      forge script script/DeployKeeper.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// Required env:
///      PRIVATE_KEY
///      GOVERNOR       — DAO governor (receives DEFAULT_ADMIN_ROLE on StrategyExecutor)
///      KEEPER         — GP engine / automated keeper address (receives KEEPER_ROLE)
///      GUARDIAN       — emergency pause address (receives GUARDIAN_ROLE)
///      SIGNAL_SIGNER  — authorized EIP-712 signer for TradeSignals
///      GP_ENGINE      — address authorised to trigger ZENT buyback
///      zETH, zBTC, zXRP, zSOL — vault addresses
///
/// Per-vault risk limits (optional — all default to 0 = no trades until set by governance):
///      MAX_POS_zETH   — max position size for zETH vault (in asset units, e.g. 100 = 100 ETH)
///      MAX_POS_zBTC   — max position size for zBTC vault
///      MAX_POS_zXRP   — max position size for zXRP vault
///      MAX_POS_zSOL   — max position size for zSOL vault
///      MAX_LEV_zETH   — max leverage BPS for zETH vault (default: 30000 = 3×)
///      MAX_LEV_zBTC   — max leverage BPS for zBTC vault (default: 30000 = 3×)
///      MAX_LEV_zXRP   — max leverage BPS for zXRP vault (default: 30000 = 3×)
///      MAX_LEV_zSOL   — max leverage BPS for zSOL vault (default: 30000 = 3×)
contract DeployKeeper is Script {
    uint256 constant DEFAULT_MAX_LEVERAGE_BPS = 30000;

    function run() external {
        uint256 key        = vm.envUint("PRIVATE_KEY");
        address governor  = _must("GOVERNOR");
        address keeper    = _must("KEEPER");
        address guardian  = _must("GUARDIAN");
        address signalSigner = _must("SIGNAL_SIGNER");

        address zeth = _must("zETH");
        address zbtc = _must("zBTC");
        address zxrp = _must("zXRP");
        address zsol = _must("zSOL");

        console2.log("Deployer:", vm.addr(key));
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(key);

        HyperCoreAdapter adapter = new HyperCoreAdapter(governor);
        console2.log("HyperCoreAdapter:", address(adapter));

        StrategyExecutor executor = new StrategyExecutor(address(adapter), governor);
        console2.log("StrategyExecutor:", address(executor));

        // Roles
        executor.grantRole(keccak256("KEEPER_ROLE"), keeper);
        executor.grantRole(keccak256("GUARDIAN_ROLE"), guardian);
        console2.log("Roles granted - Keeper:", keeper, "Guardian:", guardian);

        // Signal auth + vault registry
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(zbtc, 0);
        executor.setVaultRegistry(zeth, 1);
        executor.setVaultRegistry(zsol, 2);
        executor.setVaultRegistry(zxrp, 3);

        // Per-vault risk limits
        _setLimits(executor, zeth, "zETH");
        _setLimits(executor, zbtc, "zBTC");
        _setLimits(executor, zxrp, "zXRP");
        _setLimits(executor, zsol, "zSOL");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== KEEPER DEPLOYED ===");
        console2.log("HyperCoreAdapter:", address(adapter));
        console2.log("StrategyExecutor:", address(executor));

        _write("HYPERCORE_ADAPTER", address(adapter));
        _write("STRATEGY_EXECUTOR", address(executor));
    }

    function _setLimits(StrategyExecutor exec, address vault, string memory label) internal {
        uint256 maxPos = vm.envOr(string.concat("MAX_POS_", label), uint256(0));
        uint256 maxLev = vm.envOr(
            string.concat("MAX_LEV_", label),
            DEFAULT_MAX_LEVERAGE_BPS
        );

        if (maxPos > 0) {
            exec.setMaxPositionSize(vault, maxPos);
            console2.log(string.concat(label, " maxPos:"), maxPos);
        }
        exec.setMaxLeverageBPS(vault, maxLev);
        console2.log(string.concat(label, " maxLev (BPS):"), maxLev);
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0), string.concat("DeployKeeper: missing ", key));
        return a;
    }

    function _write(string memory label, address a) internal pure {
        console2.log(string.concat("ADDRESS_", label), a);
    }
}

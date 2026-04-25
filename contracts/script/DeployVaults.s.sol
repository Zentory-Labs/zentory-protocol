// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {BaseVault} from "../src/vaults/BaseVault.sol";
import {zETHVault} from "../src/vaults/zETHVault.sol";
import {zBTCVault} from "../src/vaults/zBTCVault.sol";
import {zXRPVault} from "../src/vaults/zXRPVault.sol";
import {zSOLVault} from "../src/vaults/zSOLVault.sol";

/// @notice Deploys all four benchmark vaults (zETH, zBTC, zXRP, zSOL).
/// @dev Run standalone:
///      forge script script/DeployVaults.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// Required env:
///      PRIVATE_KEY
///      ZENT          — ZENT token address (from DeployCore)
///      FEE_RECIPIENT — address that receives performance fees
///      VAULT_ADMIN   — privileged admin for all vaults (e.g. multisig or Timelock)
contract DeployVaults is Script {
    function run() external {
        uint256 key      = vm.envUint("PRIVATE_KEY");
        address zent     = _must("ZENT");
        address feeRcpt   = _must("FEE_RECIPIENT");
        address admin    = _must("VAULT_ADMIN");

        console2.log("Deployer:", vm.addr(key));
        console2.log("Chain:", block.chainid);
        console2.log("ZENT:", zent);

        vm.startBroadcast(key);

        zETHVault zeth = new zETHVault(zent, feeRcpt, admin);
        console2.log("zETH deployed:", address(zeth));

        zBTCVault zbtc = new zBTCVault(zent, feeRcpt, admin);
        console2.log("zBTC deployed:", address(zbtc));

        zXRPVault zxrp = new zXRPVault(zent, feeRcpt, admin);
        console2.log("zXRP deployed:", address(zxrp));

        zSOLVault zsol = new zSOLVault(zent, feeRcpt, admin);
        console2.log("zSOL deployed:", address(zsol));

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== VAULTS DEPLOYED ===");
        console2.log("zETH:", address(zeth));
        console2.log("zBTC:", address(zbtc));
        console2.log("zXRP:", address(zxrp));
        console2.log("zSOL:", address(zsol));

        _write("zETH", address(zeth));
        _write("zBTC", address(zbtc));
        _write("zXRP", address(zxrp));
        _write("zSOL", address(zsol));
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0), string.concat("DeployVaults: missing ", key));
        return a;
    }

    function _write(string memory label, address a) internal pure {
        console2.log(string.concat("ADDRESS_", label), a);
    }
}

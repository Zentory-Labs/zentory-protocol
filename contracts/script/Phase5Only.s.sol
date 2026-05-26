// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {HyperCoreAdapter} from "../src/keeper/HyperCoreAdapter.sol";
import {StrategyExecutor} from "../src/keeper/StrategyExecutor.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {ModelBonding} from "../src/staking/ModelBonding.sol";
import {FeeDistributor} from "../src/fees/FeeDistributor.sol";
import {zETHVault} from "../src/vaults/zETHVault.sol";
import {zBTCVault} from "../src/vaults/zBTCVault.sol";
import {zXRPVault} from "../src/vaults/zXRPVault.sol";
import {zSOLVault} from "../src/vaults/zSOLVault.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploy only HyperCoreAdapter + StrategyExecutor (Phase 5 only)
/// Pre-existing addresses (all verified live on-chain):
///   ZentGovernor       0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118
///   zETH              0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e
///   zBTC              0x93669daC07321FF397cf5734Ae8364EA24addF45
///   zXRP              0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0
///   zSOL              0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052
///   ZENTStaking       0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65
///   ModelBonding      0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007
///   zETH_Fees         0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73
///   zBTC_Fees         0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c
///   zXRP_Fees         0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F
///   zSOL_Fees         0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0
///   Timelock          0x1504cA3C050C88CcCa67696d642F634fc381fD03
contract Phase5Only is Script {
    function _addr(string memory hexStr) internal pure returns (address a) {
        bytes memory b = bytes(hexStr);
        require(b.length == 42 && b[0] == "0" && b[1] == "x", "bad addr");
        uint256 v = 0;
        for (uint i = 2; i < 42; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) c = c - 48;
            else if (c >= 65 && c <= 70) c = c - 55;
            else if (c >= 97 && c <= 102) c = c - 87;
            else revert("invalid hex");
            v = v * 16 + c;
        }
        return address(uint160(v));
    }

    function run() external {
        requireChainFromEnv(); // F-05
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address keeper = vm.envAddress("KEEPER");
        address guardian = vm.envAddress("GUARDIAN");
        address signalSigner = vm.envOr("SIGNAL_SIGNER", keeper);

        console2.log("Deployer:", deployer);
        console2.log("Chain:", block.chainid);

        // Pre-existing on-chain addresses
        address zentGovernor = _addr("0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118");
        address zeth = _addr("0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e");
        address zbtc = _addr("0x93669daC07321FF397cf5734Ae8364EA24addF45");
        address zxrp = _addr("0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0");
        address zsol = _addr("0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052");
        address staking = _addr("0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65");
        address bonding = _addr("0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007");
        address zethFees = _addr("0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73");
        address zbtcFees = _addr("0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c");
        address zxrpFees = _addr("0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F");
        address zsolFees = _addr("0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0");

        vm.startBroadcast(key);

        console2.log("Deploying HyperCoreAdapter...");
        HyperCoreAdapter adapter = new HyperCoreAdapter(zentGovernor);
        console2.log("HyperCoreAdapter:", address(adapter));

        console2.log("Deploying StrategyExecutor...");
        StrategyExecutor executor = new StrategyExecutor(address(adapter), zentGovernor);
        console2.log("StrategyExecutor:", address(executor));

        // Grant keeper and guardian roles
        executor.grantRole(keccak256("KEEPER_ROLE"), keeper);
        executor.grantRole(keccak256("GUARDIAN_ROLE"), guardian);
        console2.log("Roles assigned.");

        // Grant vault KEEPER_ROLE to StrategyExecutor
        zETHVault(zeth).grantRole(zETHVault(zeth).KEEPER_ROLE(), address(executor));
        zBTCVault(zbtc).grantRole(zBTCVault(zbtc).KEEPER_ROLE(), address(executor));
        zXRPVault(zxrp).grantRole(zXRPVault(zxrp).KEEPER_ROLE(), address(executor));
        zSOLVault(zsol).grantRole(zSOLVault(zsol).KEEPER_ROLE(), address(executor));

        // Set risk limits
        executor.setMaxLeverageBPS(zeth, 30000);
        executor.setMaxLeverageBPS(zbtc, 30000);
        executor.setMaxLeverageBPS(zxrp, 30000);
        executor.setMaxLeverageBPS(zsol, 30000);

        // Phase 6 wiring
        ZENTStaking(staking).grantRole(
            ZENTStaking(staking).GOVERNOR_ROLE(),
            zentGovernor
        );
        ModelBonding(bonding).grantRole(
            ModelBonding(bonding).GOVERNOR_ROLE(),
            zentGovernor
        );
        FeeDistributor(zethFees).grantRole(
            FeeDistributor(zethFees).GOVERNOR_ROLE(),
            zentGovernor
        );
        FeeDistributor(zbtcFees).grantRole(
            FeeDistributor(zbtcFees).GOVERNOR_ROLE(),
            zentGovernor
        );
        FeeDistributor(zxrpFees).grantRole(
            FeeDistributor(zxrpFees).GOVERNOR_ROLE(),
            zentGovernor
        );
        FeeDistributor(zsolFees).grantRole(
            FeeDistributor(zsolFees).GOVERNOR_ROLE(),
            zentGovernor
        );
        ModelBonding(bonding).grantRole(
            ModelBonding(bonding).RISK_COUNCIL_ROLE(),
            guardian
        );
        zETHVault(zeth).grantRole(
            zETHVault(zeth).DEFAULT_ADMIN_ROLE(),
            zentGovernor
        );
        zBTCVault(zbtc).grantRole(
            zBTCVault(zbtc).DEFAULT_ADMIN_ROLE(),
            zentGovernor
        );
        zXRPVault(zxrp).grantRole(
            zXRPVault(zxrp).DEFAULT_ADMIN_ROLE(),
            zentGovernor
        );
        zSOLVault(zsol).grantRole(
            zSOLVault(zsol).DEFAULT_ADMIN_ROLE(),
            zentGovernor
        );
        zETHVault(zeth).setStaking(staking);
        zBTCVault(zbtc).setStaking(staking);
        zXRPVault(zxrp).setStaking(staking);
        zSOLVault(zsol).setStaking(staking);
        zETHVault(zeth).setFeeRecipient(zethFees);
        zBTCVault(zbtc).setFeeRecipient(zbtcFees);
        zXRPVault(zxrp).setFeeRecipient(zxrpFees);
        zSOLVault(zsol).setFeeRecipient(zsolFees);
        executor.grantRole(executor.GOVERNOR_ROLE(), zentGovernor);
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(zbtc, 0);
        executor.setVaultRegistry(zeth, 1);
        executor.setVaultRegistry(zsol, 2);
        executor.setVaultRegistry(zxrp, 3);
        executor.transferAdmin(zentGovernor);

        vm.stopBroadcast();

        console2.log("");
        console2.log("==========================================");
        console2.log("  PHASE 5+6 COMPLETE");
        console2.log("==========================================");
        console2.log("HyperCoreAdapter:", address(adapter));
        console2.log("StrategyExecutor:", address(executor));
        console2.log("");
        console2.log("POST-DEPLOY STEPS:");
        console2.log("  1. Transfer Timelock admin to multisig");
        console2.log("  2. Fund keeper wallet with native token for gas");
    }
}

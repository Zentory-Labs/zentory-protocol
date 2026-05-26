// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {FeeDistributor} from "../src/fees/FeeDistributor.sol";
import {zETHVault} from "../src/vaults/zETHVault.sol";
import {zBTCVault} from "../src/vaults/zBTCVault.sol";
import {zXRPVault} from "../src/vaults/zXRPVault.sol";
import {zSOLVault} from "../src/vaults/zSOLVault.sol";
import {HyperCoreAdapter} from "../src/keeper/HyperCoreAdapter.sol";
import {StrategyExecutor} from "../src/keeper/StrategyExecutor.sol";
import {Timelock} from "../src/governance/Timelock.sol";
import {Zentroller} from "../src/governance/Zentroller.sol";
import {ZentGovernor} from "../src/governance/ZentGovernor.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {ModelBonding} from "../src/staking/ModelBonding.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Resume script: deploys only contracts missing from prior partial run.
/// Pre-existing on-chain addresses (verified):
///   ZENT            0x271cd48c1297CacCD810c7B1BCD904f459df7117
///   ZENTVesting     0xf7c45f45768d790F388215A44d6E01f6f2568774
///   WETH            0x80F727AF3f7932718fEb25FC28818Ad103040BD2
///   WBTC            0x08890A5B7D6D157Da65C04C19150fF7d124eaE40
///   WXRP            0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371
///   WSOL            0x2b9d5bBD8C5FEfc71E985d993C13db2770469972
///   zETH            0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e
///   zBTC            0x93669daC07321FF397cf5734Ae8364EA24addF45
///   zXRP            0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0
///   zSOL            0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052
///   ZENTStaking     0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65
///   ModelBonding    0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007
contract ResumeDeployment is Script {
    uint256 constant DEF_VOTING_DELAY   = 1 days;
    uint256 constant DEF_VOTING_PERIOD  = 7 days;
    uint256 constant DEF_PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 constant DEF_QUORUM_BPS     = 1500;
    uint256 constant DEF_TIMELOCK_DELAY = 48 hours;
    uint256 constant DEF_MIN_STAKE      = 100e18;
    uint64  constant DEF_UNBOND_COOLDOWN = 14 days;

    // Helper to convert hex strings to addresses without checksum requirement
    function _addr(string memory hexStr) internal pure returns (address a) {
        bytes memory b = bytes(hexStr);
        require(b.length == 42, "bad addr len");
        require(b[0] == "0" && b[1] == "x", "missing 0x");
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
        uint256 key       = vm.envUint("PRIVATE_KEY");
        uint256 governorKey = vm.envOr("GOVERNOR_KEY", key);
        address deployer  = vm.addr(key);
        address governorAddr = vm.addr(governorKey);
        address treasury  = vm.envAddress("TREASURY");
        address proposer  = vm.envAddress("PROPOSER");
        address keeper   = vm.envAddress("KEEPER");
        address guardian = vm.envAddress("GUARDIAN");
        address insurance = vm.envOr("INSURANCE_FUND", treasury);
        address gpEngine = vm.envOr("GP_ENGINE", keeper);
        address signalSigner = vm.envOr("SIGNAL_SIGNER", keeper);

        uint256 votingDelay   = vm.envOr("VOTING_DELAY", DEF_VOTING_DELAY);
        uint256 votingPeriod  = vm.envOr("VOTING_PERIOD", DEF_VOTING_PERIOD);
        uint256 proposalThr  = vm.envOr("PROPOSAL_THRESHOLD", DEF_PROPOSAL_THRESHOLD);
        uint256 quorumBps    = vm.envOr("QUORUM_BPS", DEF_QUORUM_BPS);
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", DEF_TIMELOCK_DELAY);
        uint256 minStake     = vm.envOr("MIN_STAKE", DEF_MIN_STAKE);
        uint64  unbondCool   = uint64(vm.envOr("UNBOND_COOLDOWN", uint256(DEF_UNBOND_COOLDOWN)));

        console2.log("==========================================");
        console2.log("  Zentory Protocol - Resume Deployment");
        console2.log("==========================================");
        console2.log("Deployer:", deployer);
        console2.log("Chain:", block.chainid);

        // Pre-existing addresses (from prior deployment run)
        address zent     = _addr("0x271cd48c1297CacCD810c7B1BCD904f459df7117");
        address weth     = _addr("0x80F727AF3f7932718fEb25FC28818Ad103040BD2");
        address wbtc    = _addr("0x08890A5B7D6D157Da65C04C19150fF7d124eaE40");
        address wxrp    = _addr("0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371");
        address wsol    = _addr("0x2b9d5bBD8C5FEfc71E985d993C13db2770469972");
        address zeth    = _addr("0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e");
        address zbtc    = _addr("0x93669daC07321FF397cf5734Ae8364EA24addF45");
        address zxrp    = _addr("0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0");
        address zsol    = _addr("0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052");
        address staking = _addr("0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65");
        address bonding = _addr("0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007");

        vm.startBroadcast(key);

        // ================================================================
        // PHASE 3b -- FeeDistributors (4 missing)
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 3b: FeeDistributors --------------------------");

        FeeDistributor zethFees = new FeeDistributor(
            weth, zent, deployer, gpEngine, insurance, treasury
        );
        console2.log("zETH_Fees:", address(zethFees));

        FeeDistributor zbtcFees = new FeeDistributor(
            wbtc, zent, deployer, gpEngine, insurance, treasury
        );
        console2.log("zBTC_Fees:", address(zbtcFees));

        FeeDistributor zxrpFees = new FeeDistributor(
            wxrp, zent, deployer, gpEngine, insurance, treasury
        );
        console2.log("zXRP_Fees:", address(zxrpFees));

        FeeDistributor zsolFees = new FeeDistributor(
            wsol, zent, deployer, gpEngine, insurance, treasury
        );
        console2.log("zSOL_Fees:", address(zsolFees));

        // ================================================================
        // PHASE 4 -- GOVERNANCE
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 4: GOVERNANCE ------------------------------");

        Timelock timelock = new Timelock(
            timelockDelay,
            _singleton(proposer),
            _singleton(address(0)),
            deployer
        );
        console2.log("Timelock:", address(timelock));

        Zentroller zentroller = new Zentroller(staking, address(0));
        console2.log("Zentroller:", address(zentroller));

        ZentGovernor govContract = new ZentGovernor(
            zent,
            staking,
            address(timelock),
            address(zentroller),
            votingDelay,
            votingPeriod,
            proposalThr,
            quorumBps
        );
        console2.log("ZentGovernor:", address(govContract));

        // Grant governor PROPOSER_ROLE on Timelock
        Timelock(payable(address(timelock))).grantRole(
            keccak256("PROPOSER_ROLE"),
            address(govContract)
        );

        // ================================================================
        // PHASE 5 -- KEEPER
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 5: KEEPER ---------------------------------");

        HyperCoreAdapter adapter = new HyperCoreAdapter(address(govContract));
        console2.log("HyperCoreAdapter:", address(adapter));

        StrategyExecutor executor = new StrategyExecutor(address(adapter), address(govContract));
        console2.log("StrategyExecutor:", address(executor));

        // Grant keeper and guardian roles
        executor.grantRole(keccak256("KEEPER_ROLE"), keeper);
        executor.grantRole(keccak256("GUARDIAN_ROLE"), guardian);
        console2.log("Keeper and guardian roles assigned.");

        // Grant vault KEEPER_ROLE to StrategyExecutor
        zETHVault(zeth).grantRole(zETHVault(zeth).KEEPER_ROLE(), address(executor));
        zBTCVault(zbtc).grantRole(zBTCVault(zbtc).KEEPER_ROLE(), address(executor));
        zXRPVault(zxrp).grantRole(zXRPVault(zxrp).KEEPER_ROLE(), address(executor));
        zSOLVault(zsol).grantRole(zSOLVault(zsol).KEEPER_ROLE(), address(executor));

        // Set initial risk limits
        executor.setMaxLeverageBPS(zeth, 30000);
        executor.setMaxLeverageBPS(zbtc, 30000);
        executor.setMaxLeverageBPS(zxrp, 30000);
        executor.setMaxLeverageBPS(zsol, 30000);
        console2.log("Risk limits configured.");

        // ================================================================
        // PHASE 6 -- WIRING
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 6: WIRING ---------------------------------");

        // Wire governor into staking/bonding/fee contracts
        ZENTStaking(staking).grantRole(
            ZENTStaking(staking).GOVERNOR_ROLE(),
            address(govContract)
        );
        ModelBonding(bonding).grantRole(
            ModelBonding(bonding).GOVERNOR_ROLE(),
            address(govContract)
        );

        zethFees.grantRole(zethFees.GOVERNOR_ROLE(), address(govContract));
        zbtcFees.grantRole(zbtcFees.GOVERNOR_ROLE(), address(govContract));
        zxrpFees.grantRole(zxrpFees.GOVERNOR_ROLE(), address(govContract));
        zsolFees.grantRole(zsolFees.GOVERNOR_ROLE(), address(govContract));

        // Risk council can slash bonds
        ModelBonding(bonding).grantRole(
            ModelBonding(bonding).RISK_COUNCIL_ROLE(),
            guardian
        );

        // Transfer vault admin to governor
        zETHVault(zeth).grantRole(zETHVault(zeth).DEFAULT_ADMIN_ROLE(), address(govContract));
        zBTCVault(zbtc).grantRole(zBTCVault(zbtc).DEFAULT_ADMIN_ROLE(), address(govContract));
        zXRPVault(zxrp).grantRole(zXRPVault(zxrp).DEFAULT_ADMIN_ROLE(), address(govContract));
        zSOLVault(zsol).grantRole(zSOLVault(zsol).DEFAULT_ADMIN_ROLE(), address(govContract));

        // Wire vault access gating + fee routing
        zETHVault(zeth).setStaking(staking);
        zBTCVault(zbtc).setStaking(staking);
        zXRPVault(zxrp).setStaking(staking);
        zSOLVault(zsol).setStaking(staking);

        zETHVault(zeth).setFeeRecipient(address(zethFees));
        zBTCVault(zbtc).setFeeRecipient(address(zbtcFees));
        zXRPVault(zxrp).setFeeRecipient(address(zxrpFees));
        zSOLVault(zsol).setFeeRecipient(address(zsolFees));

        // Grant GOVERNOR_ROLE on StrategyExecutor to the governor contract
        executor.grantRole(executor.GOVERNOR_ROLE(), address(govContract));

        // Signal auth + vault registry
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(zbtc, 0);
        executor.setVaultRegistry(zeth, 1);
        executor.setVaultRegistry(zsol, 2);
        executor.setVaultRegistry(zxrp, 3);

        // Transfer DEFAULT_ADMIN_ROLE on StrategyExecutor from deployer to governor
        executor.transferAdmin(address(govContract));

        vm.stopBroadcast();

        // Summary
        console2.log("");
        console2.log("==========================================");
        console2.log("  RESUME DEPLOYMENT COMPLETE");
        console2.log("==========================================");
        console2.log("");
        console2.log("NEW CONTRACTS:");
        console2.log("  zETH_Fees      ", address(zethFees));
        console2.log("  zBTC_Fees      ", address(zbtcFees));
        console2.log("  zXRP_Fees      ", address(zxrpFees));
        console2.log("  zSOL_Fees      ", address(zsolFees));
        console2.log("  Timelock       ", address(timelock));
        console2.log("  Zentroller     ", address(zentroller));
        console2.log("  ZentGovernor   ", address(govContract));
        console2.log("  HyperCoreAdapter ", address(adapter));
        console2.log("  StrategyExecutor", address(executor));
        console2.log("");
        console2.log("POST-DEPLOY STEPS:");
        console2.log("  1. Transfer Timelock admin to multisig: Timelock.acceptAdmin()");
        console2.log("  2. Renounce deployer DEFAULT_ADMIN_ROLE on all contracts");
        console2.log("  3. Configure HyperCoreAdapter asset indices for each vault");
        console2.log("  4. Fund keeper wallet with native token for gas");
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}

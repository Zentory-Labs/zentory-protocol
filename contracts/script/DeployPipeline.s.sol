// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTVesting} from "../src/ZENTVesting.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {ModelBonding} from "../src/staking/ModelBonding.sol";
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

/// @notice Full protocol deployment orchestrator.
/// @dev Run with:
///      forge script script/DeployPipeline.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// The script deploys in dependency order:
///   Phase 1  CORE       (ZENT + Vesting)
///   Phase 2  VAULTS     (zETH, zBTC, zXRP, zSOL)
///   Phase 3  STAKING    (ZENTStaking + ModelBonding + FeeDistributors)
///   Phase 4  GOVERNANCE (Timelock + Zentroller + ZentGovernor)
///   Phase 5  KEEPER     (HyperCoreAdapter + StrategyExecutor)
///   Phase 6  WIRING    (role wiring between contracts)
///
/// Required env:
///      PRIVATE_KEY
///      TREASURY
///      TEAM_WALLET_1..5
///      BACKER_WALLET_1..3
///      PROPOSER   - initial governance proposer (multisig/agent)
///      KEEPER     - GP engine / keeper address
///      GUARDIAN   - emergency pause multisig
///
/// Default governance params (override via env):
///      VOTING_DELAY       = 1 day
///      VOTING_PERIOD      = 7 days
///      PROPOSAL_THRESHOLD = 1_000_000e18  (veZENT)
///      QUORUM_BPS         = 1500           (15%)
///      TIMELOCK_DELAY     = 48 hours
///      MIN_STAKE          = 100e18
///      UNBOND_COOLDOWN    = 14 days
///      INSURANCE_FUND     = TREASURY
///      GP_ENGINE          = KEEPER
contract DeployPipeline is Script {
    // Default governance params
    uint256 constant DEF_VOTING_DELAY       = 1 days;
    uint256 constant DEF_VOTING_PERIOD      = 7 days;
    uint256 constant DEF_PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 constant DEF_QUORUM_BPS          = 1500;
    uint256 constant DEF_TIMELOCK_DELAY     = 48 hours;
    uint256 constant DEF_MIN_STAKE          = 100e18;
    uint64  constant DEF_UNBOND_COOLDOWN    = 14 days;

    // Vesting constants
    uint64 constant TEAM_CLIFF     = 365 days;
    uint64 constant TEAM_VEST     = 1095 days;
    uint64 constant BACKERS_CLIFF = 182 days;
    uint64 constant BACKERS_VEST  = 730 days;
    uint256 constant TEAM_TOTAL   = 180_000_000e18;
    uint256 constant BACKER_TOTAL = 150_000_000e18;

    function run() external {
        uint256 key       = vm.envUint("PRIVATE_KEY");
        address deployer  = vm.addr(key);
        address treasury  = _must("TREASURY");
        address proposer  = _must("PROPOSER");
        address keeper   = _must("KEEPER");
        address guardian = _must("GUARDIAN");

        console2.log("==========================================");
        console2.log("  Zentory Protocol - Deployment Pipeline");
        console2.log("==========================================");
        console2.log("Deployer:", deployer);
        console2.log("Chain:", block.chainid);

        // Optional params
        address insurance    = _opt("INSURANCE_FUND", treasury);
        address gpEngine    = _opt("GP_ENGINE", keeper);
        uint256 votingDelay  = vm.envOr("VOTING_DELAY", DEF_VOTING_DELAY);
        uint256 votingPeriod = vm.envOr("VOTING_PERIOD", DEF_VOTING_PERIOD);
        uint256 proposalThr  = vm.envOr("PROPOSAL_THRESHOLD", DEF_PROPOSAL_THRESHOLD);
        uint256 quorumBps    = vm.envOr("QUORUM_BPS", DEF_QUORUM_BPS);
        uint256 timelockDelay= vm.envOr("TIMELOCK_DELAY", DEF_TIMELOCK_DELAY);
        uint256 minStake     = vm.envOr("MIN_STAKE", DEF_MIN_STAKE);
        uint64  unbondCool   = uint64(vm.envOr("UNBOND_COOLDOWN", uint256(DEF_UNBOND_COOLDOWN)));

        vm.startBroadcast(key);

        // ================================================================
        // PHASE 1 -- CORE: ZENT + Vesting
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 1: CORE -----------------------------------------");

        ZENT zent = new ZENT();
        console2.log("ZENT:", address(zent));

        ZENTVesting vesting = new ZENTVesting(address(zent));
        console2.log("Vesting:", address(vesting));

        zent.approve(address(vesting), TEAM_TOTAL + BACKER_TOTAL);
        _fundTeam(vesting);
        _fundBackers(vesting);

        uint256 remainder = zent.balanceOf(deployer);
        if (remainder > 0) {
            require(zent.transfer(treasury, remainder));
            console2.log("Treasury remainder:", remainder);
        }

        // ================================================================
        // PHASE 2 -- VAULTS
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 2: VAULTS ----------------------------------------");

        zETHVault zeth = new zETHVault(address(zent), treasury, address(this));
        console2.log("zETH:", address(zeth));

        zBTCVault zbtc = new zBTCVault(address(zent), treasury, address(this));
        console2.log("zBTC:", address(zbtc));

        zXRPVault zxrp = new zXRPVault(address(zent), treasury, address(this));
        console2.log("zXRP:", address(zxrp));

        zSOLVault zsol = new zSOLVault(address(zent), treasury, address(this));
        console2.log("zSOL:", address(zsol));

        // ================================================================
        // PHASE 3 -- STAKING
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 3: STAKING ---------------------------------------");

        // Use address(this) as temporary governor to avoid circular dependency.
        // Phase 6 wires the real governor after it is deployed.
        ZENTStaking staking = new ZENTStaking(address(zent), address(this), minStake);
        console2.log("ZENTStaking:", address(staking));

        ModelBonding bonding = new ModelBonding(
            address(zent), address(this), address(this), insurance, unbondCool
        );
        console2.log("ModelBonding:", address(bonding));

        FeeDistributor zethFees = new FeeDistributor(
            address(zeth), address(zent), address(this), gpEngine, insurance, treasury
        );
        FeeDistributor zbtcFees = new FeeDistributor(
            address(zbtc), address(zent), address(this), gpEngine, insurance, treasury
        );
        FeeDistributor zxrpFees = new FeeDistributor(
            address(zxrp), address(zent), address(this), gpEngine, insurance, treasury
        );
        FeeDistributor zsolFees = new FeeDistributor(
            address(zsol), address(zent), address(this), gpEngine, insurance, treasury
        );
        console2.log("FeeDistributors:", address(zethFees));
        console2.log("                ", address(zbtcFees));
        console2.log("                ", address(zxrpFees));
        console2.log("                ", address(zsolFees));

        // ================================================================
        // PHASE 4 -- GOVERNANCE
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 4: GOVERNANCE ------------------------------------");

        Timelock timelock = new Timelock(
            timelockDelay,
            _singleton(proposer),
            _singleton(address(0)), // anyone can execute
            address(this)           // admin = deployer; must transfer after
        );
        console2.log("Timelock:", address(timelock));

        Zentroller zentroller = new Zentroller(address(staking), address(0));
        console2.log("Zentroller:", address(zentroller));

        ZentGovernor governor = new ZentGovernor(
            address(zent),
            address(staking),
            address(timelock),
            address(zentroller),
            votingDelay,
            votingPeriod,
            proposalThr,
            quorumBps
        );
        console2.log("ZentGovernor:", address(governor));

        // Grant governor PROPOSER_ROLE on Timelock
        Timelock(payable(address(timelock))).grantRole(
            keccak256("PROPOSER_ROLE"),
            address(governor)
        );

        // ================================================================
        // PHASE 5 -- KEEPER
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 5: KEEPER ----------------------------------------");

        HyperCoreAdapter adapter = new HyperCoreAdapter();
        console2.log("HyperCoreAdapter:", address(adapter));

        StrategyExecutor executor = new StrategyExecutor(address(adapter), address(governor));
        console2.log("StrategyExecutor:", address(executor));

        executor.grantRole(keccak256("KEEPER_ROLE"), keeper);
        executor.grantRole(keccak256("GUARDIAN_ROLE"), guardian);
        console2.log("Keeper roles assigned.");

        // ================================================================
        // PHASE 6 -- WIRING
        // ================================================================
        console2.log("");
        console2.log("-- PHASE 6: WIRING ----------------------------------------");

        // Wire real governor into staking/bonding/fee contracts
        staking.grantRole(staking.GOVERNOR_ROLE(), address(governor));
        bonding.grantRole(bonding.GOVERNOR_ROLE(), address(governor));

        zethFees.grantRole(zethFees.GOVERNOR_ROLE(), address(governor));
        zbtcFees.grantRole(zbtcFees.GOVERNOR_ROLE(), address(governor));
        zxrpFees.grantRole(zxrpFees.GOVERNOR_ROLE(), address(governor));
        zsolFees.grantRole(zsolFees.GOVERNOR_ROLE(), address(governor));

        // Risk council can slash bonds
        bonding.grantRole(bonding.RISK_COUNCIL_ROLE(), guardian);

        // Transfer vault admin to governor (DAO-controlled)
        zeth.grantRole(zeth.DEFAULT_ADMIN_ROLE(), address(governor));
        zbtc.grantRole(zbtc.DEFAULT_ADMIN_ROLE(), address(governor));
        zxrp.grantRole(zxrp.DEFAULT_ADMIN_ROLE(), address(governor));
        zsol.grantRole(zsol.DEFAULT_ADMIN_ROLE(), address(governor));

        // Per-vault risk limits (defaults: no max position, 3x leverage)
        _setRisk(executor, address(zeth), "zETH");
        _setRisk(executor, address(zbtc), "zBTC");
        _setRisk(executor, address(zxrp), "zXRP");
        _setRisk(executor, address(zsol), "zSOL");

        vm.stopBroadcast();

        // Summary
        console2.log("");
        console2.log("==========================================");
        console2.log("  DEPLOYMENT COMPLETE");
        console2.log("==========================================");
        console2.log("");
        console2.log("CORE:");
        console2.log("  ZENT           ", address(zent));
        console2.log("  Vesting        ", address(vesting));
        console2.log("");
        console2.log("VAULTS:");
        console2.log("  zETH           ", address(zeth));
        console2.log("  zBTC           ", address(zbtc));
        console2.log("  zXRP           ", address(zxrp));
        console2.log("  zSOL           ", address(zsol));
        console2.log("");
        console2.log("STAKING:");
        console2.log("  ZENTStaking    ", address(staking));
        console2.log("  ModelBonding   ", address(bonding));
        console2.log("  zETH_Fees      ", address(zethFees));
        console2.log("  zBTC_Fees      ", address(zbtcFees));
        console2.log("  zXRP_Fees      ", address(zxrpFees));
        console2.log("  zSOL_Fees      ", address(zsolFees));
        console2.log("");
        console2.log("GOVERNANCE:");
        console2.log("  Timelock       ", address(timelock));
        console2.log("  Zentroller     ", address(zentroller));
        console2.log("  ZentGovernor   ", address(governor));
        console2.log("");
        console2.log("KEEPER:");
        console2.log("  HyperCoreAdapter ", address(adapter));
        console2.log("  StrategyExecutor", address(executor));
        console2.log("");
        console2.log("POST-DEPLOY STEPS:");
        console2.log("  1. Transfer Timelock admin to multisig: Timelock.acceptAdmin()");
        console2.log("  2. Renounce deployer DEFAULT_ADMIN_ROLE on all contracts");
        console2.log("  3. Configure HyperCoreAdapter asset indices for each vault");
        console2.log("  4. Fund keeper wallet with native token for gas");
        console2.log("  5. Set ZENTStaking.minStake via governance proposal");
    }

    // --------------------------------------------------------------------
    // Vesting helpers
    // --------------------------------------------------------------------
    function _fundTeam(ZENTVesting vesting) internal {
        address[] memory wallets   = new address[](5);
        uint256[] memory amounts   = new uint256[](5);
        uint64[] memory cliffs     = new uint64[](5);
        uint64[] memory durations  = new uint64[](5);
        bool[]    memory revocable = new bool[](5);

        for (uint256 i = 0; i < 5; i++) {
            wallets[i]   = _must(string.concat("TEAM_WALLET_", vm.toString(i + 1)));
            amounts[i]   = 36_000_000e18;
            cliffs[i]    = TEAM_CLIFF;
            durations[i] = TEAM_VEST;
            revocable[i] = true;
        }
        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _fundBackers(ZENTVesting vesting) internal {
        address[] memory wallets   = new address[](3);
        uint256[] memory amounts   = new uint256[](3);
        uint64[] memory cliffs     = new uint64[](3);
        uint64[] memory durations  = new uint64[](3);
        bool[]    memory revocable = new bool[](3);

        wallets[0]  = _must("BACKER_WALLET_1");  amounts[0] = 75_000_000e18;
        wallets[1]  = _must("BACKER_WALLET_2");  amounts[1] = 50_000_000e18;
        wallets[2]  = _must("BACKER_WALLET_3");  amounts[2] = 25_000_000e18;

        for (uint256 i = 0; i < 3; i++) {
            cliffs[i]    = BACKERS_CLIFF;
            durations[i] = BACKERS_VEST;
            revocable[i] = false;
        }
        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    // --------------------------------------------------------------------
    // Misc helpers
    // --------------------------------------------------------------------
    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _setRisk(StrategyExecutor exec, address vault, string memory label) internal {
        uint256 maxPos = vm.envOr(string.concat("MAX_POS_", label), uint256(0));
        uint256 maxLev = vm.envOr(string.concat("MAX_LEV_", label), uint256(30000));
        if (maxPos > 0) exec.setMaxPositionSize(vault, maxPos);
        exec.setMaxLeverageBPS(vault, maxLev);
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0), string.concat("DeployPipeline: missing ", key));
        return a;
    }

    function _opt(string memory key, address fallbackAddr) internal view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a != address(0) ? a : fallbackAddr;
        } catch {
            return fallbackAddr;
        }
    }
}

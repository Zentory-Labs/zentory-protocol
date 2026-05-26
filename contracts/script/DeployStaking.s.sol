// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {ModelBonding} from "../src/staking/ModelBonding.sol";
import {FeeDistributor} from "../src/fees/FeeDistributor.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys ZENTStaking, ModelBonding, and one FeeDistributor per vault.
/// @dev Run standalone:
///      forge script script/DeployStaking.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// Required env:
///      PRIVATE_KEY
///      ZENT             — ZENT token address
///      GOVERNOR         — address that receives GOVERNOR_ROLE on staking/bonding
///      RISK_COUNCIL     — address that receives RISK_COUNCIL_ROLE on ModelBonding
///      FEE_RECIPIENT    — performance fee recipient (e.g. treasury multisig)
///      INSURANCE_FUND   — insurance fund destination for slashed bonds
///      GP_ENGINE        — address authorised to trigger ZENT buyback
///      TREASURY         — address receiving treasury portion of fees
///      zETH, zBTC, zXRP, zSOL — vault addresses
///
/// Optional env (with defaults):
///      MIN_STAKE        — minimum ZENT to stake for vault access (default: 100e18)
///      UNBOND_COOLDOWN  — seconds between request and claim (default: 14 days)
contract DeployStaking is Script {
    uint256 constant DEFAULT_MIN_STAKE       = 100e18;
    uint64  constant DEFAULT_UNBOND_COOLDOWN = 14 days;

    function run() external {
        requireChainFromEnv(); // F-05
        uint256 key        = vm.envUint("PRIVATE_KEY");
        address zent       = _must("ZENT");
        address governor   = _must("GOVERNOR");
        address riskCouncil= _must("RISK_COUNCIL");
        address insurance  = _must("INSURANCE_FUND");
        address gpEngine   = _must("GP_ENGINE");
        address treasury   = _must("TREASURY");

        uint256 minStake        = vm.envOr("MIN_STAKE", DEFAULT_MIN_STAKE);
        uint64  unbondCooldown  = uint64(vm.envOr("UNBOND_COOLDOWN", uint256(DEFAULT_UNBOND_COOLDOWN)));

        // ── One FeeDistributor per vault ──────────────────────────────────────
        address zeth = _must("zETH");
        address zbtc = _must("zBTC");
        address zxrp = _must("zXRP");
        address zsol = _must("zSOL");

        console2.log("Deployer:", vm.addr(key));
        console2.log("Chain:", block.chainid);
        console2.log("Governor:", governor);
        console2.log("RiskCouncil:", riskCouncil);

        vm.startBroadcast(key);

        // 1. ZENTStaking
        ZENTStaking staking = new ZENTStaking(zent, governor, minStake);
        console2.log("ZENTStaking deployed:", address(staking));

        // 2. ModelBonding
        ModelBonding bonding = new ModelBonding(zent, governor, riskCouncil, insurance, unbondCooldown);
        console2.log("ModelBonding deployed:", address(bonding));

        // 3. One FeeDistributor per vault (asset = vault.asset())
        FeeDistributor zethFees = new FeeDistributor(
            IERC4626(zeth).asset(), zent, governor, gpEngine, insurance, treasury
        );
        console2.log("zETH FeeDistributor deployed:", address(zethFees));

        FeeDistributor zbtcFees = new FeeDistributor(
            IERC4626(zbtc).asset(), zent, governor, gpEngine, insurance, treasury
        );
        console2.log("zBTC FeeDistributor deployed:", address(zbtcFees));

        FeeDistributor zxrpFees = new FeeDistributor(
            IERC4626(zxrp).asset(), zent, governor, gpEngine, insurance, treasury
        );
        console2.log("zXRP FeeDistributor deployed:", address(zxrpFees));

        FeeDistributor zsolFees = new FeeDistributor(
            IERC4626(zsol).asset(), zent, governor, gpEngine, insurance, treasury
        );
        console2.log("zSOL FeeDistributor deployed:", address(zsolFees));

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== STAKING DEPLOYED ===");
        console2.log("ZENTStaking:", address(staking));
        console2.log("ModelBonding:", address(bonding));
        console2.log("zETH_Fees:", address(zethFees));
        console2.log("zBTC_Fees:", address(zbtcFees));
        console2.log("zXRP_Fees:", address(zxrpFees));
        console2.log("zSOL_Fees:", address(zsolFees));

        _write("ZENT_STAKING", address(staking));
        _write("MODEL_BONDING", address(bonding));
        _write("zETH_FEES", address(zethFees));
        _write("zBTC_FEES", address(zbtcFees));
        _write("zXRP_FEES", address(zxrpFees));
        _write("zSOL_FEES", address(zsolFees));
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0), string.concat("DeployStaking: missing ", key));
        return a;
    }

    function _write(string memory label, address a) internal pure {
        console2.log(string.concat("ADDRESS_", label), a);
    }
}

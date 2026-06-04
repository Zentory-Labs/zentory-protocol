// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys the dedicated InsuranceFund (M10) and prints the address to
///         wire into the deploy pipeline's INSURANCE_FUND (so FeeDistributor's
///         insurance share + slashed bonds route here, NOT to the treasury).
///
/// Chain-parameterized via EXPECTED_CHAIN_ID (ChainGuard), so it runs on testnet
/// 998 AND mainnet — no hardcoded chain id.
///
/// Required env: PRIVATE_KEY, EXPECTED_CHAIN_ID.
/// Optional:     INSURANCE_GOVERNANCE — owner of the fund. MUST be the Gnosis Safe
///               / Timelock on mainnet. Defaults to the deployer (testnet only).
///
///   forge script script/DeployInsuranceFund.s.sol --rpc-url $RPC --broadcast
contract DeployInsuranceFund is Script {
    function run() external {
        requireChainFromEnv();
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address governance = vm.envOr("INSURANCE_GOVERNANCE", vm.addr(pk));

        vm.startBroadcast(pk);
        InsuranceFund fund = new InsuranceFund(governance);
        vm.stopBroadcast();

        require(fund.owner() == governance, "DeployInsuranceFund: owner mismatch");
        console2.log("InsuranceFund:", address(fund));
        console2.log("owner (governance):", governance);
        if (governance == vm.addr(pk)) {
            console2.log("WARNING: owner is the deployer EOA - acceptable on testnet ONLY.");
            console2.log("For mainnet, set INSURANCE_GOVERNANCE to the Gnosis Safe / Timelock.");
        }
        console2.log("NEXT: set INSURANCE_FUND=this address in the deploy pipeline, then seed it from treasury.");
    }
}

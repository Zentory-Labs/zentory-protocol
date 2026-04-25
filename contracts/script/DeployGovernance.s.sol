// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Timelock} from "../src/governance/Timelock.sol";
import {Zentroller} from "../src/governance/Zentroller.sol";
import {ZentGovernor} from "../src/governance/ZentGovernor.sol";

/// @notice Deploys TimelockController, Zentroller (staking link), and ZentGovernor.
/// @dev Run standalone:
///      forge script script/DeployGovernance.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// Required env:
///      PRIVATE_KEY
///      ZENT           — ZENT token address
///      STAKING        — ZENTStaking address
///      PROPOSER       — initial proposer address (e.g. multisig or DAO agent)
///      EXECUTOR       — initial executor address (use address(0) for anyone)
///      TIMELOCK_DELAY — proposal execution delay in seconds (default: 48 hours)
///
/// Governor params (with defaults):
///      VOTING_DELAY   — blocks between proposal creation and vote start (default: 1 day)
///      VOTING_PERIOD  — blocks for which votes are open (default: 7 days)
///      PROPOSAL_THRESHOLD — minimum veBalance to submit (default: 1_000_000e18)
///      QUORUM_BPS     — quorum as bps of total ZENT supply (default: 1500 = 15%)
contract DeployGovernance is Script {
    uint256 constant DEFAULT_VOTING_DELAY      = 1 days;
    uint256 constant DEFAULT_VOTING_PERIOD      = 7 days;
    uint256 constant DEFAULT_PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 constant DEFAULT_QUORUM_BPS         = 1500; // 15%
    uint256 constant DEFAULT_TIMELOCK_DELAY     = 48 hours;

    function run() external {
        uint256 key       = vm.envUint("PRIVATE_KEY");
        address zent     = _must("ZENT");
        address staking  = _must("STAKING");
        address proposer = _must("PROPOSER");
        address executor = _mustOrZero("EXECUTOR");

        uint256 votingDelay      = vm.envOr("VOTING_DELAY",      DEFAULT_VOTING_DELAY);
        uint256 votingPeriod     = vm.envOr("VOTING_PERIOD",     DEFAULT_VOTING_PERIOD);
        uint256 proposalThreshold= vm.envOr("PROPOSAL_THRESHOLD", DEFAULT_PROPOSAL_THRESHOLD);
        uint256 quorumBps        = vm.envOr("QUORUM_BPS",        DEFAULT_QUORUM_BPS);
        uint256 timelockDelay    = vm.envOr("TIMELOCK_DELAY",    DEFAULT_TIMELOCK_DELAY);

        console2.log("Deployer:", vm.addr(key));
        console2.log("Chain:", block.chainid);
        console2.log("ZENT:", zent);
        console2.log("Staking:", staking);

        vm.startBroadcast(key);

        // 1. Timelock — delay, [proposer], [executor], admin
        // The deployer is set as admin so it can grant PROPOSER_ROLE to the governor.
        // After setup, the admin should be transferred to a multisig or renounced.
        Timelock timelock = new Timelock(
            timelockDelay,
            _singleton(proposer),
            _singleton(executor),
            vm.addr(key)  // admin = deployer EOA; must transfer/renounce afterwards
        );
        console2.log("Timelock deployed:", address(timelock));

        // 2. Zentroller — links governor to staking
        Zentroller zentroller = new Zentroller(staking, address(0));
        console2.log("Zentroller deployed:", address(zentroller));

        // 3. ZentGovernor
        ZentGovernor governor = new ZentGovernor(
            zent,
            staking,
            address(timelock),
            address(zentroller),
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumBps
        );
        console2.log("ZentGovernor deployed:", address(governor));

        // Grant governor PROPOSER_ROLE on the Timelock so it can queue proposals.
        Timelock(payable(address(timelock))).grantRole(
            keccak256("PROPOSER_ROLE"),
            address(governor)
        );

        // Grant EXECUTOR_ROLE to the executor if provided, otherwise open to anyone.
        if (executor != address(0)) {
            Timelock(payable(address(timelock))).grantRole(
                keccak256("EXECUTOR_ROLE"),
                executor
            );
        } else {
            // Open execution: grant EXECUTOR_ROLE to the zero address (anyone can execute).
            Timelock(payable(address(timelock))).grantRole(
                keccak256("EXECUTOR_ROLE"),
                address(0)
            );
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== GOVERNANCE DEPLOYED ===");
        console2.log("Timelock:", address(timelock));
        console2.log("Zentroller:", address(zentroller));
        console2.log("ZentGovernor:", address(governor));
        console2.log("");
        console2.log("IMPORTANT: Transfer Timelock admin to a multisig or renounce.");
        console2.log("  To transfer:  Timelock.acceptAdmin() from the new admin.");
        console2.log("  To renounce: Timelock.grantRole(TIMELOCK_ADMIN_ROLE, address(0))");

        _write("TIMELOCK", address(timelock));
        _write("ZENTROLLER", address(zentroller));
        _write("ZENT_GOVERNOR", address(governor));
    }

    /// Returns a single-element array containing `a`.
    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    /// Returns the env address if set, otherwise address(0).
    function _mustOrZero(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0), string.concat("DeployGovernance: missing ", key));
        return a;
    }

    function _write(string memory label, address a) internal pure {
        console2.log(string.concat("ADDRESS_", label), a);
    }
}

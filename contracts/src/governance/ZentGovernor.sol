// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IZENTStaking} from "../interfaces/IZENTStaking.sol";
import {Zentroller} from "./Zentroller.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ZentGovernor
/// @notice ZENT holder governance over risk parameters, treasury, and upgrades.
///         Voting weight = ZENTStaking.veBalance (vote-escrowed ZENT, not raw ZENT balance).
///         Proposals execute through TimelockController after a 48-hour delay.
/// @dev    Does NOT inherit GovernorVotes — voting weight comes from ZENTStaking.veBalance,
///         not from ZENT ERC20Votes checkpoints.
contract ZentGovernor is Governor, GovernorCountingSimple, GovernorTimelockControl {

    /// @notice ZENT token address (used for quorum totalSupply reference).
    address public immutable zentToken;

    /// @notice Contract that resolves staking balances for voting weight.
    Zentroller public immutable zentroller;

    /// @notice Minimum ZENT veBalance required to submit a proposal (application-layer enforced).
    uint256 public immutable minProposalThreshold;

    /// @notice Quorum fraction expressed in basis points (e.g. 1500 = 15%).
    uint256 public immutable quorumBps;

    // ─── Internal immutable storage (avoid naming conflict with Governor.votingDelay()) ───

    /// @notice Delay between proposal creation and voting start.
    uint256 internal immutable _votingDelay;

    /// @notice Duration of the voting period.
    uint256 internal immutable _votingPeriod;

    constructor(
        address zentToken_,
        address staking_,
        address timelock_,
        address zentroller_,
        uint256 votingDelay_,
        uint256 votingPeriod__,
        uint256 proposalThreshold_,
        uint256 quorumBps_
    )
        Governor("ZentGovernor")
        GovernorTimelockControl(TimelockController(payable(timelock_)))
    {
        require(zentToken_ != address(0), "ZentGovernor: zero zent");
        require(staking_ != address(0), "ZentGovernor: zero staking");
        require(timelock_ != address(0), "ZentGovernor: zero timelock");
        require(zentroller_ != address(0), "ZentGovernor: zero zentroller");
        require(quorumBps_ <= 10000, "ZentGovernor: invalid quorum");

        zentToken = zentToken_;
        minProposalThreshold = proposalThreshold_;
        quorumBps = quorumBps_;
        zentroller = Zentroller(zentroller_);
        _votingDelay = votingDelay_;
        _votingPeriod = votingPeriod__;
    }

    // ─── Voting Weight (from Staking) ────────────────────────────────────

    /// @dev Voting weight is veBalance from ZENTStaking, not ZENT ERC20Votes.
    ///     Snapshot parameter (timepoint) is ignored — veBalance is time-based, not snapshot-based.
    function _getVotes(address account, uint256, bytes memory)
        internal
        view
        override(Governor)
        returns (uint256)
    {
        return IZENTStaking(address(zentroller.staking())).veBalance(account);
    }

    // ─── Proposal Threshold ───────────────────────────────────────────────

    /// @notice Proposals can be submitted by anyone (veBalance gating is application-layer).
    function proposalThreshold() public pure override(Governor) returns (uint256) {
        return 0;
    }

    // ─── Quorum ─────────────────────────────────────────────────────

    /// @dev Returns quorum = ZENT.totalSupply * quorumBps / 10000.
    function quorum(uint256) public view override(Governor) returns (uint256) {
        return (IERC20Metadata(zentToken).totalSupply() * quorumBps) / 10000;
    }

    // ─── Timing ────────────────────────────────────────────────────────

    /// @dev Block-timestamp based clock.
    function clock() public view override(Governor) returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override(Governor) returns (string memory) {
        return "mode=timestamp";
    }

    /// @notice Delay between proposal creation and voting start.
    function votingDelay() public view override(Governor) returns (uint256) {
        return _votingDelay;
    }

    /// @notice Duration of the voting period.
    function votingPeriod() public view override(Governor) returns (uint256) {
        return _votingPeriod;
    }

    // ─── Timelock integration ────────────────────────────────────────────

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
    {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

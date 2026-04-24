// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Zentroller} from "./Zentroller.sol";

/// @title ZentGovernor
/// @notice ZENT holder governance over risk parameters, treasury, and upgrades.
///         Voting weight is derived from ZENTStaking.veBalance (vote-escrowed ZENT).
///         Proposals execute through TimelockController after a configurable delay.
contract ZentGovernor is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    /// @notice Minimum ZENT veBalance required to submit a proposal.
    uint256 public proposalThreshold_;

    /// @notice Contract that resolves staking balances for voting weight.
    Zentroller public immutable zentroller;

    constructor(
        address zentToken_,
        address staking_,
        address timelock_,
        address zentroller_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_
    )
        Governor("ZentGovernor")
        GovernorVotes(IERC20(zentToken_))
        GovernorVotesQuorumFraction(15) // 15% of circulating supply for quorum
    {
        require(zentToken_ != address(0), "ZentGovernor: zero zent");
        require(staking_ != address(0), "ZentGovernor: zero staking");
        require(timelock_ != address(0), "ZentGovernor: zero timelock");
        require(zentroller_ != address(0), "ZentGovernor: zero zentroller");

        proposalThreshold_ = proposalThreshold_;
        zentroller = Zentroller(zentroller_);

        // Grant this governor the proposer and canceller roles on the timelock.
        TimelockController(payable(timelock_)).grantRole(
            TimelockController(payable(timelock_)).PROPOSER_ROLE(),
            address(this)
        );
        TimelockController(payable(timelock_)).grantRole(
            TimelockController(payable(timelock_)).CANCELLER_ROLE(),
            address(this)
        );
    }

    // ─── Overrides ───────────────────────────────────────────────────────

    /// @dev Voting weight comes from ZENTStaking.veBalance via the Zentroller.
    function votingWeight(address account) public view returns (uint256) {
        return zentroller.staking().veBalance(account);
    }

    /// @notice Proposals cannot be created with less veBalance than the threshold.
    function proposalThreshold() public view override returns (uint256) {
        return proposalThreshold_;
    }

    /// @dev Delay between proposal creation and voting start (in blocks or seconds depending on clock).
    function votingDelay() public view override returns (uint256) {
        return 1 days; // configurable in production
    }

    /// @dev Duration of the voting period.
    function votingPeriod() public view override returns (uint256) {
        return 7 days; // configurable in production
    }

    /// @dev Use ZENT as the voting token.
    function clock() public view override returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    /// @dev Required forVotes, againstVotes, and abstainVotes accounting.
    function proposalVotes(address account)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        forVotes = _voteCount[account].forVotes;
        againstVotes = _voteCount[account].againstVotes;
        abstainVotes = _voteCount[account].abstainVotes;
    }
}

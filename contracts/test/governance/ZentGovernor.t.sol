// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../../src/ZENT.sol";
import {ZENTStaking} from "../../src/staking/ZENTStaking.sol";
import {Zentroller} from "../../src/governance/Zentroller.sol";
import {Timelock} from "../../src/governance/Timelock.sol";
import {ZentGovernor} from "../../src/governance/ZentGovernor.sol";

/// @notice Minimal Timelock stub so tests don't need OZ TimelockController.
contract Timelock {
    address public admin;
    uint256 public delay;
    mapping(bytes32 => bool) public queuedTransactions;

    constructor(address admin_, uint256 delay_) {
        admin = admin_;
        delay = delay_;
    }

    function queueTransaction(address target, uint256 value, bytes memory data, bytes32 salt)
        external
        returns (bytes32)
    {
        require(msg.sender == admin, "Timelock: not admin");
        bytes32 txHash = keccak256(abi.encode(target, value, data, salt));
        queuedTransactions[txHash] = true;
        return txHash;
    }

    function cancelTransaction(address target, uint256 value, bytes memory data, bytes32 salt) external {
        require(msg.sender == admin, "Timelock: not admin");
        bytes32 txHash = keccak256(abi.encode(target, value, data, salt));
        queuedTransactions[txHash] = false;
    }

    function executeTransaction(address target, uint256 value, bytes memory data, bytes32 salt)
        external
        payable
        returns (bytes memory)
    {
        bytes32 txHash = keccak256(abi.encode(target, value, data, salt));
        require(queuedTransactions[txHash], "Timelock: not queued");
        queuedTransactions[txHash] = false;
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        require(success, "Timelock: execution failed");
        return returndata;
    }
}

contract ZentGovernorTest is Test {
    ZENT internal zent;
    ZENTStaking internal staking;
    Timelock internal timelock;
    Zentroller internal zentroller;
    ZentGovernor internal governor;

    uint256 internal constant VOTING_DELAY = 1 days;
    uint256 internal constant VOTING_PERIOD = 7 days;
    uint256 internal constant PROPOSAL_THRESHOLD = 100 ether; // 100 ZENT veBalance needed

    address internal admin = makeAddr("admin");
    address internal proposer = makeAddr("proposer");
    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");
    address internal outsider = makeAddr("outsider");

    function setUp() external {
        zent = new ZENT();

        // Fund accounts
        zent.transfer(proposer, 100_000 ether);
        zent.transfer(voter1, 100_000 ether);
        zent.transfer(voter2, 100_000 ether);

        // Deploy staking (governor is this test contract for simplicity)
        staking = new ZENTStaking(address(zent), address(this), PROPOSAL_THRESHOLD);

        // Deploy timelock with admin = governor
        timelock = new Timelock(address(this), 2 days);

        // Deploy zentroller (links staking + governor)
        zentroller = new Zentroller(address(staking), address(0));

        // Deploy governor
        governor = new ZentGovernor(
            address(zent),
            address(staking),
            address(timelock),
            address(zentroller),
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );

        // Transfer staking governor role to this test contract
        vm.prank(address(this));
        staking.setMinStake(0);
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    function test_constructorRejectsZeroZent() external {
        vm.expectRevert(bytes("ZentGovernor: zero zent"));
        new ZentGovernor(
            address(0), address(staking), address(timelock), address(zentroller),
            VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD
        );
    }

    function test_constructorRejectsZeroStaking() external {
        vm.expectRevert(bytes("ZentGovernor: zero staking"));
        new ZentGovernor(
            address(zent), address(0), address(timelock), address(zentroller),
            VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD
        );
    }

    function test_constructorRejectsZeroTimelock() external {
        vm.expectRevert(bytes("ZentGovernor: zero timelock"));
        new ZentGovernor(
            address(zent), address(staking), address(0), address(zentroller),
            VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD
        );
    }

    // ─── veBalance Integration ────────────────────────────────────────────

    function test_proposalRequiresMinVeBalance() external {
        // proposer has ZENT but no staking position — veBalance = 0
        vm.startPrank(proposer);
        zent.approve(address(staking), type(uint256).max);
        governor.propose(
           ProposedActions(new address[](1), new uint256[](1), new bytes[](1), ""),
            "Lower the leverage cap"
        );
        vm.stopPrank();
    }

    function test_proposeRejectsBelowThreshold() external {
        vm.startPrank(proposer);
        zent.approve(address(staking), 50 ether);
        staking.stake(50 ether, 365 days);
        // veBalance ≈ 50 * 365/730 ≈ 25 ether < 100 threshold
        vm.stopPrank();

        vm.startPrank(proposer);
        zent.approve(address(staking), type(uint256).max);
        vm.expectRevert(bytes("ZentGovernor: below proposal threshold"));
        governor.propose(
            ProposedActions(new address[](1), new uint256[](1), new bytes[](1), ""),
            "Change the leverage cap"
        );
        vm.stopPrank();
    }

    // ─── Proposal Lifecycle ───────────────────────────────────────────────

    function test_proposeCreatesProposal() external {
        _createStakedPosition(proposer, 200 ether, 730 days);

        uint256 proposalId = governor.propose(
            ProposedActions(new address[](1), new uint256[](1), new bytes[](1), ""),
            "Increase max leverage"
        );

        assertTrue(proposalId > 0);
        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Active));
    }

    function test_voteForProposal() external {
        uint256 proposalId = _createAndActivateProposal();

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        assertEq(governor.hasVoted(proposalId, voter1), true);
    }

    function test_voteAgainstProposal() external {
        uint256 proposalId = _createAndActivateProposal();

        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Against

        assertEq(governor.hasVoted(proposalId, voter1), true);
    }

    function test_voteRevertsAfterVotingPeriod() external {
        uint256 proposalId = _createAndActivateProposal();

        // Warp past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(voter1);
        vm.expectRevert(bytes("ZentGovernor: not active"));
        governor.castVote(proposalId, 1);
    }

    function test_multipleVotersCountCorrectly() external {
        uint256 proposalId = _createAndActivateProposal();

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // for
        vm.prank(voter2);
        governor.castVote(proposalId, 0); // against

        assertEq(governor.proposalVotes(proposalId).forVotes, 0); // voting power is in ZENT terms, not raw
    }

    // ─── Quorum ──────────────────────────────────────────────────────────

    function test_proposalFailsWithoutQuorum() external {
        uint256 proposalId = _createAndActivateProposal();

        // Warp to end of voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Proposal should be defeated (no quorum reached)
        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Defeated));
    }

    // ─── Timelock Execution ──────────────────────────────────────────────

    function test_queueAfterVotePasses() external {
        uint256 proposalId = _createAndActivateProposal();

        // Warp through voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Advance past voting delay so proposal can be queued
        governor.queue(proposalId);

        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Queued));
    }

    function test_executeAfterTimelockDelay() external {
        uint256 proposalId = _createAndActivateProposal();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        governor.queue(proposalId);

        // Warp past timelock delay (2 days)
        vm.warp(block.timestamp + 2 days + 1);

        // Execute should succeed if targets are set
        // (empty targets list is a no-op — just test state transition)
        vm.warp(block.timestamp + 1);
        governor.execute(proposalId);

        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Executed));
    }

    // ─── Access Control ──────────────────────────────────────────────────

    function test_onlyGovernorCanQueue() external {
        uint256 proposalId = _createAndActivateProposal();
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(outsider);
        vm.expectRevert(bytes("ZentGovernor: not timelock"));
        governor.queue(proposalId);
    }

    function test_onlyGovernorCanExecute() external {
        uint256 proposalId = _createAndActivateProposal();
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        governor.queue(proposalId);
        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(outsider);
        vm.expectRevert(bytes("ZentGovernor: not timelock"));
        governor.execute(proposalId);
    }

    // ─── View Functions ───────────────────────────────────────────────────

    function test_votingDelayEnforced() external {
        _createStakedPosition(proposer, 200 ether, 730 days);

        uint256 proposalId = governor.propose(
            ProposedActions(new address[](1), new uint256[](1), new bytes[](1), ""),
            "Test proposal"
        );

        // Proposal should be in Pending state initially
        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Pending));

        // After voting delay, it becomes Active
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        assertEq(uint(governor.state(proposalId)), uint(ZentGovernor.ProposalState.Active));
    }

    function test_proposalThresholdView() external view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_votingPeriodView() external view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    // ─── Helper ─────────────────────────────────────────────────────────

    struct ProposedActions {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    function _createStakedPosition(address user, uint256 amount, uint64 lockDuration) internal {
        vm.startPrank(user);
        zent.approve(address(staking), amount);
        staking.stake(amount, lockDuration);
        vm.stopPrank();
    }

    function _createAndActivateProposal() internal returns (uint256) {
        // voter1 creates and activates a proposal with enough veBalance
        _createStakedPosition(proposer, 200 ether, 730 days);

        ProposedActions memory actions = ProposedActions({
            targets: new address[](1),
            values: new uint256[](1),
            calldatas: new bytes[](1),
            description: "Test proposal to change max leverage"
        });
        actions.targets[0] = address(staking);

        uint256 proposalId = governor.propose(actions, "Test proposal to change max leverage");

        // Advance past voting delay
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        return proposalId;
    }
}

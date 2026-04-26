// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../../src/ZENT.sol";
import {ZENTStaking} from "../../src/staking/ZENTStaking.sol";
import {Zentroller} from "../../src/governance/Zentroller.sol";
import {Timelock} from "../../src/governance/Timelock.sol";
import {ZentGovernor} from "../../src/governance/ZentGovernor.sol";

/// @notice Deploys governance contracts with a minimal timelock setup.
contract GovernorDeployer {
    ZENT public zent;
    ZENTStaking public staking;
    Timelock public timelock;
    Zentroller public zentroller;
    ZentGovernor public governor;

    constructor() {
        zent = new ZENT();

        staking = new ZENTStaking(address(zent), address(this), 100 ether);

        // Timelock: this = admin/proposer/canceller
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](0);
        timelock = new Timelock(2 days, proposers, executors, address(this));

        zentroller = new Zentroller(address(staking), address(0));

        // votingDelay = 1 day so proposals start Pending and become Active the next day
        governor = new ZentGovernor(
            address(zent),
            address(staking),
            address(timelock),
            address(zentroller),
            1 days,
            7 days,
            1, // minProposalThreshold: 1 wei — trivially satisfied in tests; production uses 100 ether
            1500
        );
    }

    function transferZent(address to, uint256 amount) external {
        zent.transfer(to, amount);
    }
}

contract ZentGovernorTest is Test {
    ZENT internal zent;
    ZENTStaking internal staking;
    Timelock internal timelock;
    Zentroller internal zentroller;
    ZentGovernor internal governor;

    address internal proposer;
    address internal voter1;
    address internal voter2;
    address internal outsider;

    address[] internal _targets;
    uint256[] internal _values;
    bytes[] internal _calldatas;

    function setUp() external {
        GovernorDeployer deployer = new GovernorDeployer();

        zent = deployer.zent();
        staking = deployer.staking();
        timelock = deployer.timelock();
        zentroller = deployer.zentroller();
        governor = deployer.governor();

        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        outsider = makeAddr("outsider");

        deployer.transferZent(proposer, 100_000 ether);
        deployer.transferZent(voter1, 100_000 ether);
        deployer.transferZent(voter2, 100_000 ether);

        // The test contract (ZentGovernorTest) is the proposer. It needs veBalance >= 1 wei.
        // Directly write a Position into ZENTStaking storage so veBalance works without
        // the approve/stake dance (Forge prank resets between setUp and tests).
        // ZENTStaking storage layout:
        //   slot 0: zent (address, 20 bytes, padded)
        //   slot 1: minStake (uint256)
        //   slot 2: totalStaked (uint256)
        //   slot 3: totalVeSupply (uint256)
        //   slot N+1: _positions[addr] = keccak256(abi.encode(addr, uint256(slot_of_positions)))
        //              where slot_of_positions = 4 (5th state variable)
        // Position (amount uint128 + lockEnd uint64) packs into 256 bits = 1 slot.
        bytes32 posSlot = keccak256(abi.encode(address(this), uint256(4)));
        uint256 lockEnd = block.timestamp + 730 days;
        // amount (uint128) in lower bits, lockEnd (uint64) in upper bits
        bytes32 packed = bytes32((uint256(200 ether) & ~uint128(0)) | (uint256(lockEnd) << 128));
        vm.store(address(staking), posSlot, packed);
        // Update totalVeSupply
        uint256 veAmt = (200 ether * (lockEnd - block.timestamp)) / 730 days;
        vm.store(address(staking), bytes32(uint256(3)), bytes32(veAmt));

        _targets = new address[](1);
        _targets[0] = address(staking);
        _values = new uint256[](1);
        _values[0] = 0;
        _calldatas = new bytes[](1);
        _calldatas[0] = "";
    }

    // ─── Constructor Validation ──────────────────────────────────────────

    function test_constructorRejectsZeroZent() external {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        Timelock tl = new Timelock(2 days, proposers, new address[](0), address(this));
        Zentroller zt = new Zentroller(address(staking), address(0));

        vm.expectRevert(bytes("ZentGovernor: zero zent"));
        new ZentGovernor(
            address(0), address(staking), address(tl), address(zt),
            1 days, 7 days, 100 ether, 1500
        );
    }

    function test_constructorRejectsZeroStaking() external {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        Timelock tl = new Timelock(2 days, proposers, new address[](0), address(this));
        Zentroller zt = new Zentroller(address(staking), address(0));

        vm.expectRevert(bytes("ZentGovernor: zero staking"));
        new ZentGovernor(
            address(zent), address(0), address(tl), address(zt),
            1 days, 7 days, 100 ether, 1500
        );
    }

    function test_constructorRejectsZeroTimelock() external {
        Zentroller zt = new Zentroller(address(staking), address(0));

        vm.expectRevert(bytes("ZentGovernor: zero timelock"));
        new ZentGovernor(
            address(zent), address(staking), address(0), address(zt),
            1 days, 7 days, 100 ether, 1500
        );
    }

    function test_constructorRejectsInvalidQuorum() external {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        Timelock tl = new Timelock(2 days, proposers, new address[](0), address(this));
        Zentroller zt = new Zentroller(address(staking), address(0));

        vm.expectRevert(bytes("ZentGovernor: invalid quorum"));
        new ZentGovernor(
            address(zent), address(staking), address(tl), address(zt),
            1 days, 7 days, 100 ether, 10001
        );
    }

    // ─── Proposal Creation ───────────────────────────────────────────────

    function test_proposeCreatesPendingProposal() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Increase max leverage");
        assertTrue(proposalId > 0);
        // State should be Pending (0) since votingDelay = 1 day hasn't elapsed yet
        assertEq(uint8(governor.state(proposalId)), uint8(0)); // Pending
    }

    // ─── Proposal State Transitions ───────────────────────────────────────

    function test_proposalBecomesActiveAfterVotingDelay() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Test");
        // Warp past the 1-day voting delay
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(1)); // Active
    }

    function test_proposalDefeatedAfterVotingPeriodNoVotes() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Test");
        // Warp past voting delay AND voting period
        vm.warp(block.timestamp + 1 days + 7 days + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(3)); // Defeated
    }

    // ─── Voting ────────────────────────────────────────────────────────

    function test_castVoteForProposal() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Test");
        // Warp past voting delay to make proposal Active
        vm.warp(block.timestamp + 1 days + 1);

        // Stake voter1 and warp 1 more second so clock()-1 reflects post-stake
        _createStakedPosition(voter1, 200 ether, 730 days);
        vm.warp(block.timestamp + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        assertTrue(governor.hasVoted(proposalId, voter1));
    }

    function test_castVoteAgainstProposal() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Test");
        vm.warp(block.timestamp + 1 days + 1);

        _createStakedPosition(voter1, 200 ether, 730 days);
        vm.warp(block.timestamp + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Against

        assertTrue(governor.hasVoted(proposalId, voter1));
    }

    function test_cannotVoteAfterVotingPeriod() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "Test");
        vm.warp(block.timestamp + 1 days + 1);

        _createStakedPosition(voter1, 200 ether, 730 days);
        vm.warp(block.timestamp + 1);

        // Warp to voteEnd (proposal transitions from Active -> Defeated)
        vm.warp(block.timestamp + 7 days);

        vm.prank(voter1);
        // Proposal is now Defeated (3), so castVote reverts with GovernorUnexpectedProposalState
        vm.expectRevert();
        governor.castVote(proposalId, 1);
    }

    // ─── View Functions ─────────────────────────────────────────────────

    function test_proposalThresholdIsSetToMinProposalThreshold() external view {
        // proposalThreshold returns the constructor-set minProposalThreshold.
        // In production this is 100 ether; in tests it is 1 wei for convenience.
        assertEq(governor.proposalThreshold(), 1);
    }

    function test_minProposalThresholdStored() external view {
        // minProposalThreshold tracks what was passed to the constructor (1 in tests, 100 ether in production)
        assertEq(governor.minProposalThreshold(), 1);
    }

    function test_quorumBpsStored() external view {
        assertEq(governor.quorumBps(), 1500);
    }

    function test_votingDelayAndPeriod() external view {
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 7 days);
    }

    function test_zentrollerLinksStaking() external view {
        assertEq(address(zentroller.staking()), address(staking));
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _createStakedPosition(address user, uint256 amount, uint64 lockDuration) internal {
        // vm.prank only affects the NEXT call; use vm.startPrank for multiple calls
        vm.startPrank(user);
        zent.approve(address(staking), amount);
        staking.stake(amount, lockDuration);
        vm.stopPrank();
    }
}

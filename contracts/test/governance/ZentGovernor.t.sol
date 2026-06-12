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
        // ZENTStaking storage layout (AccessControl _roles occupies slot 0):
        //   slot 0: _roles (AccessControl mapping)
        //   slot 1: minStake (uint256)
        //   slot 2: totalStaked (uint256)
        //   slot 3: totalVeSupply (uint256)
        //   slot 4: insuranceFund (address) — added in audit H-4 fix
        //   slot 5: _positions mapping base
        //   _positions[addr] = keccak256(abi.encode(addr, uint256(5)))
        // Position (amount uint128 + lockEnd uint64) packs into 256 bits = 1 slot.
        bytes32 posSlot = keccak256(abi.encode(address(this), uint256(5)));
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

    // ─── Supermajority (GOV-001) ─────────────────────────────────────────
    // The published governance model (README, whitepaper §12) commits to a 66%
    // supermajority; GovernorCountingSimple's default is a simple majority.
    // These tests pin the _voteSucceeded override: For must reach >= 66% of
    // (For + Against) or the proposal is Defeated even with a clear majority.

    /// @dev Stake both voters and cast a weighted For/Against split, then warp
    ///      past the voting period and return the final state. Staking happens
    ///      immediately before voting with no warp in between so veBalance ==
    ///      staked amount exactly (no per-second decay rounding) and the
    ///      For/(For+Against) ratio is exact.
    function _runWeightedVote(uint256 forAmount, uint256 againstAmount) internal returns (uint8) {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "GOV-001");
        vm.warp(block.timestamp + 1 days + 1);

        _createStakedPosition(voter1, forAmount, 730 days);
        _createStakedPosition(voter2, againstAmount, 730 days);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For
        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against

        vm.warp(block.timestamp + 7 days + 1);
        return uint8(governor.state(proposalId));
    }

    function test_supermajorityConstantMatchesPublishedDocs() external view {
        assertEq(governor.SUPERMAJORITY_BPS(), 6600);
    }

    function test_simpleMajorityIsNoLongerEnough() external {
        // 60% For / 40% Against passed under GovernorCountingSimple's default —
        // this is the GOV-001 regression case. Quorum is met (For = 60e18 >
        // 15% of total veSupply), so the ONLY reason this is Defeated is the
        // supermajority threshold.
        assertEq(_runWeightedVote(60 ether, 40 ether), 3, "60% For must be Defeated (3)");
    }

    function test_sixtyFivePercentForIsDefeated() external {
        assertEq(_runWeightedVote(65 ether, 35 ether), 3, "65% For must be Defeated (3)");
    }

    function test_exactSupermajorityBoundarySucceeds() external {
        // Exactly 66.00% For: 66 * 10000 == 100 * 6600 — at-threshold passes.
        assertEq(_runWeightedVote(66 ether, 34 ether), 4, "exactly 66% For must Succeed (4)");
    }

    function test_sixtySevenPercentForSucceeds() external {
        assertEq(_runWeightedVote(67 ether, 33 ether), 4, "67% For must Succeed (4)");
    }

    function test_unanimousForSucceeds() external {
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "GOV-001 unanimous");
        vm.warp(block.timestamp + 1 days + 1);

        _createStakedPosition(voter1, 100 ether, 730 days);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + 7 days + 1);
        assertEq(uint8(governor.state(proposalId)), 4, "100% For must Succeed (4)");
    }

    function test_abstainDoesNotDiluteTheThreshold() external {
        // 67% of decisive votes For, plus a large Abstain: Abstain counts
        // toward quorum but must not push the proposal below the threshold.
        uint256 proposalId = governor.propose(_targets, _values, _calldatas, "GOV-001 abstain");
        vm.warp(block.timestamp + 1 days + 1);

        // setUp funds proposer/voter1/voter2 only — give the abstainer ZENT.
        vm.prank(voter1);
        zent.transfer(outsider, 100 ether);

        _createStakedPosition(voter1, 67 ether, 730 days);
        _createStakedPosition(voter2, 33 ether, 730 days);
        _createStakedPosition(outsider, 100 ether, 730 days);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For
        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against
        vm.prank(outsider);
        governor.castVote(proposalId, 2); // Abstain

        vm.warp(block.timestamp + 7 days + 1);
        assertEq(uint8(governor.state(proposalId)), 4, "abstain must not count against the supermajority");
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

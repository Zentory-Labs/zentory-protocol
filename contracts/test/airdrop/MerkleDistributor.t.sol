// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MerkleDistributor} from "../../src/airdrop/MerkleDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal mintable ERC-20 for testing. Tracks only what
///         MerkleDistributor calls: transfer + balanceOf.
contract MockZENT is ERC20 {
    constructor() ERC20("Mock ZENT", "ZENT") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @notice MerkleDistributor exhaustive test. Covers the happy path
///         (anyone can submit a valid proof for a recipient), all four
///         revert paths (already claimed, bad proof, expired, before
///         deadline), the bit-packed claimed map, and the sweep flow.
///
// We construct a 2-leaf tree by hand to avoid pulling OpenZeppelin's
// merkle-tree JS library as a Foundry dep. For larger trees the JS
// tooling at scripts/airdrop/snapshot.ts produces matching root + proofs.
contract MerkleDistributorTest is Test {
    MerkleDistributor dist;
    MockZENT zent;

    // Two airdrop recipients, hard-coded.
    address constant ALICE = address(0xA11CE);
    address constant BOB   = address(0xB0B);
    uint256 constant ALICE_AMOUNT = 1000e18;
    uint256 constant BOB_AMOUNT   = 2500e18;

    // The two leaves and the root, computed manually.
    bytes32 leafAlice;
    bytes32 leafBob;
    bytes32 root;
    bytes32[] proofForAlice;
    bytes32[] proofForBob;

    address admin = address(this);
    address treasury = makeAddr("treasury");
    uint256 deadline;

    function setUp() public {
        zent = new MockZENT();

        // Leaf format must match the contract:
        //   keccak256(abi.encodePacked(index, account, amount))
        leafAlice = keccak256(abi.encodePacked(uint256(0), ALICE, ALICE_AMOUNT));
        leafBob   = keccak256(abi.encodePacked(uint256(1), BOB,   BOB_AMOUNT));

        // For a 2-leaf tree the root is keccak256(sorted_pair). Sort to
        // match OZ MerkleProof's verify path (it sorts at each hash step).
        (bytes32 left, bytes32 right) = leafAlice < leafBob
            ? (leafAlice, leafBob)
            : (leafBob, leafAlice);
        root = keccak256(abi.encodePacked(left, right));

        // Each recipient's proof is just the sibling leaf.
        proofForAlice.push(leafBob);
        proofForBob.push(leafAlice);

        deadline = block.timestamp + 90 days;
        dist = new MerkleDistributor(IERC20(address(zent)), root, deadline, admin);

        // Pre-fund the distributor with the total airdrop allocation.
        zent.mint(address(dist), ALICE_AMOUNT + BOB_AMOUNT);
    }

    // ─── Happy path ─────────────────────────────────────────────────────

    function test_claim_succeeds_for_valid_proof() external {
        assertEq(zent.balanceOf(ALICE), 0);
        assertFalse(dist.isClaimed(0));

        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);

        assertEq(zent.balanceOf(ALICE), ALICE_AMOUNT);
        assertTrue(dist.isClaimed(0));
    }

    function test_claim_anyone_can_submit_on_behalf() external {
        // Recipients don't need to pay gas — anyone with their proof can
        // claim FOR them. This is the standard distributor pattern (1inch,
        // Uniswap, etc.).
        address randomCaller = makeAddr("random-helper");
        vm.prank(randomCaller);
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);

        assertEq(zent.balanceOf(ALICE), ALICE_AMOUNT);
        assertEq(zent.balanceOf(randomCaller), 0);
    }

    function test_claim_both_recipients_independently() external {
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);
        dist.claim(1, BOB, BOB_AMOUNT, proofForBob);

        assertEq(zent.balanceOf(ALICE), ALICE_AMOUNT);
        assertEq(zent.balanceOf(BOB), BOB_AMOUNT);
        assertTrue(dist.isClaimed(0));
        assertTrue(dist.isClaimed(1));
    }

    // ─── Revert paths ───────────────────────────────────────────────────

    function test_claim_reverts_when_already_claimed() external {
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);
        vm.expectRevert(abi.encodeWithSelector(MerkleDistributor.AlreadyClaimed.selector, uint256(0)));
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);
    }

    function test_claim_reverts_for_invalid_proof() external {
        // Empty proof
        bytes32[] memory badProof = new bytes32[](0);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        dist.claim(0, ALICE, ALICE_AMOUNT, badProof);
    }

    function test_claim_reverts_when_amount_tampered() external {
        // Right index + address + proof but wrong amount → leaf hash
        // changes → proof fails.
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        dist.claim(0, ALICE, ALICE_AMOUNT + 1, proofForAlice);
    }

    function test_claim_reverts_when_account_tampered() external {
        // Right index + proof + amount but wrong account → leaf hash
        // changes → proof fails. Prevents griefing via swapped recipients.
        address attacker = makeAddr("attacker");
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        dist.claim(0, attacker, ALICE_AMOUNT, proofForAlice);
    }

    function test_claim_reverts_after_deadline() external {
        vm.warp(deadline + 1);
        vm.expectRevert(MerkleDistributor.ClaimWindowClosed.selector);
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);
    }

    // ─── Bit-packed claimed map ─────────────────────────────────────────

    function test_isClaimed_handles_high_indices() external view {
        // Indices beyond the first word (idx >= 256) must work. We don't
        // claim here — just verify the read path handles wordIdx > 0.
        assertFalse(dist.isClaimed(0));
        assertFalse(dist.isClaimed(255));
        assertFalse(dist.isClaimed(256));
        assertFalse(dist.isClaimed(10_000));
    }

    // ─── Sweep ──────────────────────────────────────────────────────────

    function test_sweep_reverts_before_deadline() external {
        vm.expectRevert(MerkleDistributor.SweepBeforeDeadline.selector);
        dist.sweep(treasury);
    }

    function test_sweep_succeeds_after_deadline() external {
        // Alice claims, Bob doesn't.
        dist.claim(0, ALICE, ALICE_AMOUNT, proofForAlice);

        vm.warp(deadline + 1);
        dist.sweep(treasury);

        // Bob's unclaimed allocation went to treasury.
        assertEq(zent.balanceOf(treasury), BOB_AMOUNT);
        // Distributor is drained.
        assertEq(zent.balanceOf(address(dist)), 0);
    }

    function test_sweep_reverts_for_non_sweeper() external {
        address attacker = makeAddr("attacker");
        vm.warp(deadline + 1);
        vm.prank(attacker);
        vm.expectRevert(); // AccessControl revert
        dist.sweep(attacker);
    }

    // ─── Constructor input validation ───────────────────────────────────

    function test_constructor_reverts_on_zero_token() external {
        vm.expectRevert(MerkleDistributor.InvalidConfig.selector);
        new MerkleDistributor(IERC20(address(0)), root, deadline, admin);
    }

    function test_constructor_reverts_on_zero_root() external {
        vm.expectRevert(MerkleDistributor.InvalidConfig.selector);
        new MerkleDistributor(IERC20(address(zent)), bytes32(0), deadline, admin);
    }

    function test_constructor_reverts_on_past_deadline() external {
        vm.expectRevert(MerkleDistributor.InvalidConfig.selector);
        new MerkleDistributor(IERC20(address(zent)), root, block.timestamp - 1, admin);
    }

    function test_constructor_reverts_on_zero_admin() external {
        vm.expectRevert(MerkleDistributor.InvalidConfig.selector);
        new MerkleDistributor(IERC20(address(zent)), root, deadline, address(0));
    }
}

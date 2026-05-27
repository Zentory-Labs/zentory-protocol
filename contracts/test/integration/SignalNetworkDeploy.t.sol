// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SignalRegistry} from "../../src/signals/SignalRegistry.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {ZENTStaking} from "../../src/staking/ZENTStaking.sol";

contract MockZENT is ERC20 {
    constructor() ERC20("Mock ZENT", "ZENT") {}
}

/// @notice Proves that the signal network, deployed + wired EXACTLY as
///         deploy_signal_network.s.sol does it, lets the keeper settle an
///         empty epoch without reverting and advances BOTH the EpochScoring
///         and SignalRegistry epoch counters.
///
///         This is the regression guard for the live incident: the deployed
///         testnet contracts were version-mismatched (the registry predated
///         getSignalCount/advanceEpoch), so EpochScoring.settleEpoch() reverted
///         on every keeper run and the loop stalled at epoch 1. After a
///         redeploy from current source with the corrected role wiring (the
///         EpochScoring *contract* holds SCORING_ORACLE on the registry), the
///         keeper loop runs. If this test ever fails, a redeploy would not
///         fix the live loop — so it must stay green.
contract SignalNetworkDeployTest is Test {
    SignalRegistry registry;
    EpochScoring scoring;
    ZENTStaking staking;
    MockZENT zent;

    address deployer = address(this);
    address keeper = makeAddr("keeper");

    function setUp() public {
        zent = new MockZENT();
        // ZENTStaking(zent, governor, minStake)
        staking = new ZENTStaking(address(zent), deployer, 100e18);

        // Mirror deploy_signal_network.s.sol exactly:
        // 1. registry (deployer = initial scoring oracle)
        registry = new SignalRegistry(address(staking), deployer);
        // 2. scoring (keeper = scoringOracle + EPOCH_SETTLER)
        scoring = new EpochScoring(
            address(registry),
            address(staking),
            address(zent),
            keeper,
            keeper
        );
        // 4a. EpochScoring CONTRACT holds SCORING_ORACLE on the registry — the
        //     grant the old deploy script was missing; without it advanceEpoch
        //     reverts inside settleEpoch.
        registry.grantRole(registry.SCORING_ORACLE(), address(scoring));
        // 4b/4c. keeper roles
        registry.grantRole(registry.SCORING_ORACLE(), keeper);
        scoring.grantRole(scoring.EPOCH_SETTLER(), keeper);
    }

    function test_emptyEpochSettles_andAdvancesBothCounters() external {
        assertEq(scoring.currentEpochId(), 1, "scoring starts at epoch 1");
        assertEq(registry.currentEpochId(), 0, "registry starts at epoch 0");

        // Move past the epoch window for realism (settleEpoch itself doesn't
        // gate on time, but performUpkeep does).
        vm.warp(block.timestamp + 4 hours + 1);

        // The exact call the keeper makes — this is what reverts on the stale
        // live contracts. With fresh contracts + correct wiring it succeeds.
        vm.prank(keeper);
        uint256 rewards = scoring.settleEpoch();

        assertEq(rewards, 0, "empty epoch distributes nothing");
        assertEq(scoring.currentEpochId(), 2, "EpochScoring epoch advanced");
        // The advanceEpoch() call (gated by SCORING_ORACLE on the registry,
        // caller = EpochScoring contract) must have succeeded.
        assertEq(registry.currentEpochId(), 1, "registry epoch advanced via advanceEpoch");

        (uint256 total, uint256 settled, bool isSettled) = scoring.epochStates(1);
        assertEq(total, 0);
        assertEq(settled, 0);
        assertTrue(isSettled, "epoch 1 marked settled");
    }

    function test_settleReverts_ifEpochScoringLacksScoringOracle() external {
        // Negative control: prove the SCORING_ORACLE grant to the EpochScoring
        // contract is load-bearing. Deploy a second network WITHOUT that grant
        // and confirm settleEpoch reverts inside advanceEpoch — i.e. exactly
        // the failure mode the old deploy script produced.
        SignalRegistry reg2 = new SignalRegistry(address(staking), deployer);
        EpochScoring sc2 = new EpochScoring(
            address(reg2), address(staking), address(zent), keeper, keeper
        );
        // NOTE: deliberately NOT granting reg2.SCORING_ORACLE to address(sc2).
        scoring.grantRole(scoring.EPOCH_SETTLER(), keeper); // unrelated, harmless

        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(keeper);
        vm.expectRevert(); // advanceEpoch -> AccessControl: missing SCORING_ORACLE
        sc2.settleEpoch();
    }
}

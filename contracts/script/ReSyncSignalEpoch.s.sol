// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

/// @title ReSyncSignalEpoch
/// @notice One-time fix for the deployed SignalRegistry / EpochScoring epoch
///         off-by-one. The registry counter started at 0 while EpochScoring
///         started at 1, so they ran permanently 1 apart: `settleEpoch(E)` reads
///         `epochSignalIds[E]` but `submitSignal` filed signals in bucket E-1, so
///         every epoch hit the empty fast-path and NOTHING was ever scored.
///
///         This bumps the registry's `currentEpochId` up to equal EpochScoring's,
///         so new signals land in the bucket settlement actually reads. After this,
///         the lockstep advance in settleEpoch keeps them equal forever.
///
///         `advanceEpoch()` is onlyRole(SCORING_ORACLE) (held by the EpochScoring
///         contract), so we temporarily grant SCORING_ORACLE to the admin EOA,
///         advance, and revoke — net role state is unchanged. Run by the registry
///         DEFAULT_ADMIN_ROLE holder (the signal-deploy key in contracts/.env).
///
///         (Source root-cause fixed for future deploys: SignalRegistry now inits
///         currentEpochId = 1. This script repairs the already-deployed contract.)
contract ReSyncSignalEpoch is Script {
    bytes32 internal constant SCORING_ORACLE = keccak256("SCORING_ORACLE");

    function run() external {
        require(block.chainid == 998, "ReSyncSignalEpoch: not HyperEVM testnet (998)");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        address reg   = vm.envOr("SIGNAL_REGISTRY", address(0x9685F25E75758E18b2b109be64271102497D800e));
        address epoch = vm.envOr("EPOCH_SCORING",   address(0x31b7082f1e1B3cC373dE3d9c3575701b9aa24538));

        uint256 target = IEpochScoringView(epoch).currentEpochId();
        uint256 cur = IRegistry(reg).currentEpochId();
        console2.log("registry currentEpochId:", cur);
        console2.log("scoring  currentEpochId (target):", target);

        require(target >= cur, "registry AHEAD of scoring - unexpected, investigate (do not advance)");
        uint256 steps = target - cur;
        if (steps == 0) {
            console2.log("== already in sync - no-op ==");
            return;
        }
        require(steps <= 5, "gap > 5 - unexpected, investigate before advancing");

        bool adminHadOracle = IRegistry(reg).hasRole(SCORING_ORACLE, me);

        vm.startBroadcast(pk);
        if (!adminHadOracle) IRegistry(reg).grantRole(SCORING_ORACLE, me);
        for (uint256 i = 0; i < steps; i++) {
            IRegistry(reg).advanceEpoch();
        }
        if (!adminHadOracle) IRegistry(reg).revokeRole(SCORING_ORACLE, me); // restore prior role state
        vm.stopBroadcast();

        uint256 nowEpoch = IRegistry(reg).currentEpochId();
        console2.log("registry currentEpochId now:", nowEpoch);
        require(nowEpoch == target, "re-sync failed: registry != scoring");
        require(!IRegistry(reg).hasRole(SCORING_ORACLE, me) || adminHadOracle, "SCORING_ORACLE left granted - revoke manually");
        console2.log("== SYNCED == registry == scoring. settleEpoch will now score new signals; re-seed/await fresh signals.");
    }
}

interface IRegistry {
    function currentEpochId() external view returns (uint256);
    function advanceEpoch() external;
    function grantRole(bytes32, address) external;
    function revokeRole(bytes32, address) external;
    function hasRole(bytes32, address) external view returns (bool);
}

interface IEpochScoringView {
    function currentEpochId() external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ChainGuard
/// @notice Helper for enforcing `block.chainid == EXPECTED_CHAIN_ID` at the top
///         of every deploy script. Audit-finding F-05: prior to this, all
///         Deploy*.s.sol scripts (except MainnetDeployVaults) printed the
///         chain ID via console2.log but never actually checked it, so
///         pointing `--rpc-url` at the wrong chain would broadcast happily.
///
/// Usage in any deploy script:
///   import {ChainGuard} from "./lib/ChainGuard.sol";
///   ...
///   function run() external {
///       ChainGuard.requireChainEnv(vm); // reads EXPECTED_CHAIN_ID
///       ...
///   }
///
/// Set `EXPECTED_CHAIN_ID=998` in the testnet env, `999` in the mainnet env.
/// Missing env var aborts the script — no silent default.
library ChainGuard {
    error WrongChain(uint256 actual, uint256 expected);
    error ExpectedChainIdMissing();

    /// @notice Revert unless `block.chainid` matches `expected`.
    function requireChain(uint256 expected) internal view {
        if (block.chainid != expected) revert WrongChain(block.chainid, expected);
    }
}

// The forge-std Vm interface fragment we need; declared locally so this
// library can be imported into any script without pulling forge-std's full
// Script.sol dependency tree.
interface IVmChainGuard {
    function envUint(string calldata) external view returns (uint256);
}

/// @notice Convenience wrapper that reads `EXPECTED_CHAIN_ID` from env and
///         asserts in one call. Use inside a Script.run() body.
function requireChainFromEnv() view {
    // forge cheatcode address
    IVmChainGuard vm_ = IVmChainGuard(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    uint256 expected = vm_.envUint("EXPECTED_CHAIN_ID");
    if (expected == 0) revert ChainGuard.ExpectedChainIdMissing();
    if (block.chainid != expected) revert ChainGuard.WrongChain(block.chainid, expected);
}

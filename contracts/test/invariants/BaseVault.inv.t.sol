// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BaseVaultInvariantTest
/// @notice Invariant tests for BaseVault.
/// @dev   Only pure/view invariants are reliable in open invariance testing
///         (where the engine sends arbitrary calls to ALL public functions).
///         State-modifying tests are in BaseVault.t.sol.
contract BaseVaultInvariantTest is Test {
    BaseVault vault;
    MockERC20 asset;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() external {
        asset = new MockERC20("Mock WETH", "WETH", 18);

        vault = new BaseVault({
            asset_:        address(asset),
            name_:         "zETH Vault",
            symbol_:       "zETH",
            maxLeverage_:  30000,
            maxPositionSizeBPS_: 10000,
            circuitBreakerDrawdownBPS_: 2000,
            rebalanceThresholdBPS_: 500,
            performanceFeeBPS_: 2000,
            feeRecipient_: makeAddr("feeRecipient"),
            admin_:        address(this)
        });

        asset.mint(alice, 1000e18);
        asset.mint(bob, 1000e18);
        asset.mint(carol, 1000e18);
    }

    // ─── Pure invariants ─────────────────────────────────────────────────────────

    /// @notice Performance fee is always within bounds [0, 100%]
    function invariant_performanceFeeBounded() external view {
        assertLe(vault.performanceFee(), 10000);
    }

    /// @notice maxLeverage is always non-zero
    function invariant_maxLeverageIsSet() external view {
        assertGt(vault.maxLeverage(), 0);
    }

    /// @notice Initial NAV per share is 1 (asset unit)
    function invariant_initialNavIsAssetUnit() external view {
        assertEq(vault.lastNavPerShare(), 10 ** IERC20Metadata(address(asset)).decimals());
    }

    /// @notice Initial HWM equals initial NAV
    function invariant_initialHwmEqualsNav() external view {
        assertEq(vault.highWaterMark(), vault.lastNavPerShare());
    }

    /// @notice Vault never starts with assets or shares
    function invariant_initialSupplyAndAssetsZero() external view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    /// @notice Performance fee cannot exceed 100%
    function invariant_circuitBreakerThresholdInBounds() external view {
        assertLe(vault.circuitBreakerDrawdownBPS(), 10000);
    }

    /// @notice Rebalance threshold cannot exceed 100%
    function invariant_rebalanceThresholdInBounds() external view {
        assertLe(vault.rebalanceThresholdBPS(), 10000);
    }

    /// @notice Circuit breaker is initially inactive
    function invariant_circuitBreakerStartsInactive() external view {
        assertFalse(vault.isCircuitBreakerActive());
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IFeeDistributor
/// @notice Interface for the performance-fee router.
interface IFeeDistributor {
    event FeeAccumulated(address indexed vault, uint256 amount);
    event FeesDistributed(
        uint256 buybackAmount, uint256 gpEngineAmount, uint256 insuranceAmount, uint256 treasuryAmount
    );
    event BuybackTriggered(address indexed token, uint256 amount);
    event GovernorUpdated(address indexed previous, address indexed current);

    /// @notice Accumulate fees from a vault. Callable by anyone (permissionless push model).
    function accumulate(address vault, uint256 amount) external;

    /// @notice Pull accumulated fees from a vault and split/distribute to all destinations.
    function distribute(address vault) external;

    /// @notice Trigger ZENT buyback + burn from accumulated buyback pool.
    ///         Uses the accumulated asset (e.g. WBTC) to purchase ZENT from a DEX and burns it.
    /// @param path Token path for the swap (e.g. [WBTC, USDC, ZENT]).
    function triggerBuyback(address[] calldata path) external;

    /// @notice Withdraw accumulated GP engine allocations.
    function withdrawTo(address recipient, uint256 amount, uint8 poolId) external;

    /// @notice Returns the current accumulated balance for a given vault.
    function pendingFees(address vault) external view returns (uint256);
}

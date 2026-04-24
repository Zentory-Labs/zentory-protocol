// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IVault
/// @notice Interface for Zentory benchmark-denominated ERC-4626 vaults.
interface IVault {
    /// @notice Total assets held in the vault (including accrued yield, before fees)
    function totalAssets() external view returns (uint256);

    /// @notice Current NAV per share (in asset units, 18 decimals)
    function getNavPerShare() external view returns (uint256);

    /// @notice High-water mark — max NAV per share ever reached
    function highWaterMark() external view returns (uint256);

    /// @notice Last NAV per share when fees were evaluated
    function lastNavPerShare() external view returns (uint256);

    /// @notice Performance fee ratio (e.g., 2000 = 20%)
    function performanceFee() external view returns (uint256);

    /// @notice Fee recipient address
    function feeRecipient() external view returns (address);

    /// @notice Returns the vault's maximum leverage as a raw multiplier (e.g., 30000 = 3x)
    function maxLeverage() external view returns (uint256);

    /// @notice Returns true if deposits are paused by circuit breaker
    function isCircuitBreakerActive() external view returns (bool);

    /// @notice Current position direction: 1=long, -1=short, 0=flat
    function currentDirection() external view returns (int8);

    /// @notice Emitted when a trade is executed by the keeper
    event TradeExecuted(int8 indexed direction, uint256 size, uint256 entryPrice, uint256 timestamp);

    /// @notice Emitted when performance fee is accrued
    event PerformanceFeeAccrued(uint256 feeAmount, uint256 navPerShareBefore, uint256 navPerShareAfter);

    /// @notice Emitted when circuit breaker activates
    event CircuitBreakerActivated(string reason);

    /// @notice Record a new trade from the GP engine signal
    function recordTrade(int8 direction, uint256 size, uint256 entryPrice) external;

    /// @notice Access control: only the keeper can call privileged functions
    function isKeeper(address caller) external view returns (bool);
}

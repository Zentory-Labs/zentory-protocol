// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IZENTStaking
/// @notice Interface for ZENT staking: vault-access gating and time-weighted governance weight.
interface IZENTStaking {
    event Staked(address indexed user, uint256 amount, uint64 lockEnd);
    event Increased(address indexed user, uint256 addedAmount, uint256 newAmount);
    event Extended(address indexed user, uint64 oldLockEnd, uint64 newLockEnd);
    event Withdrawn(address indexed user, uint256 amount);
    event MinStakeUpdated(uint256 oldValue, uint256 newValue);

    /// @notice Lock ZENT for `lockDuration` seconds. Reverts if the caller already has a position.
    /// @return lockEnd timestamp at which the lock expires
    function stake(uint256 amount, uint64 lockDuration) external returns (uint64 lockEnd);

    /// @notice Add additional ZENT to an existing unexpired position without changing the lock end.
    function increaseAmount(uint256 amount) external;

    /// @notice Push the lock end forward. New absolute lock end must be further in the future
    ///         than the current one and must not exceed MAX_LOCK from now.
    /// @return newLockEnd the updated lock end
    function extendLock(uint64 newLockDuration) external returns (uint64 newLockEnd);

    /// @notice Withdraw the full position after the lock has expired.
    function withdraw() external;

    /// @notice Time-decayed governance weight. Reaches zero when the lock expires.
    function veBalance(address user) external view returns (uint256);

    /// @notice Returns true iff `user` currently holds at least `minStake` with an unexpired lock.
    function hasAccess(address user) external view returns (bool);

    /// @notice Raw staked balance for `user` (ignores lock state).
    function stakedBalance(address user) external view returns (uint256);

    /// @notice Governor-adjustable vault-access threshold.
    function setMinStake(uint256 newMinStake) external;
}

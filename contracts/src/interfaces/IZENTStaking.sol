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
    event ProviderSlashed(address indexed provider, uint256 amount, address indexed reason);
    event ProviderRewarded(address indexed provider, uint256 amount);

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

    /// @notice Sum of veBalance across all stakers (total voting weight).
    function totalVeSupply() external view returns (uint256);

    /// @notice Governor-adjustable vault-access threshold.
    function setMinStake(uint256 newMinStake) external;

    /// @notice Raw staked amount for a provider (used for stake-weighted signal scoring).
    /// @dev    Differs from stakedBalance in that it returns the raw amount regardless of
    ///         lock expiry — a locked-but-expired position still has slashable stake.
    function getProviderStake(address provider) external view returns (uint256 stake);

    /// @notice Slash a provider's stake. Called by EpochScoring when a signal is penalized.
    /// @param provider Address of the signal provider to slash
    /// @param amount   Absolute amount of ZENT to slash from provider's position
    function slash(address provider, uint256 amount) external;

    /// @notice Reward a provider's stake. Called by EpochScoring when a signal is correct.
    /// @param provider Address of the signal provider to reward
    /// @param amount  Amount of ZENT to add to provider's stake
    function reward(address provider, uint256 amount) external;
}

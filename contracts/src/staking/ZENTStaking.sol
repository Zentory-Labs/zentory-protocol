// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IZENTStaking} from "../interfaces/IZENTStaking.sol";

/// @title ZENTStaking
/// @notice Locks ZENT for a fixed duration to gate vault access and grant time-decayed
///         governance weight (veBalance). One position per address; amount may be increased
///         and lock end may be extended, but early withdrawal is impossible.
/// @dev    veBalance(t) = amount * max(0, lockEnd - t) / MAX_LOCK.
///         A full MAX_LOCK position yields veBalance ≈ amount at lockStart and decays to 0 at lockEnd.
contract ZENTStaking is AccessControl, IZENTStaking {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ─── Roles ─────────────────────────────────────────────────────────────
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // ─── Lock Bounds ───────────────────────────────────────────────────────
    uint64 public constant MIN_LOCK = 7 days;
    uint64 public constant MAX_LOCK = 730 days;

    // ─── State ─────────────────────────────────────────────────────────────
    /// @notice ZENT token
    IERC20 public immutable zent;

    /// @notice Minimum staked balance required for vault access (governor-adjustable).
    uint256 public minStake;

    /// @notice Sum of all active stakes.
    uint256 public totalStaked;

    /// @notice Sum of veBalance across all active positions (total voting weight).
    uint256 public totalVeSupply;

    /// @notice Address that receives slashed ZENT. Defaults to the staking
    ///         contract itself (acts as an internal insurance buffer) if the
    ///         constructor receives address(0). Governor-adjustable via
    ///         `setInsuranceFund`. Must NEVER be address(0) post-deploy.
    address public insuranceFund;

    /// @notice Emitted when the insurance fund recipient changes.
    event InsuranceFundUpdated(address indexed previous, address indexed current);

    struct Position {
        uint128 amount;
        uint64 lockEnd;
    }

    mapping(address => Position) private _positions;

    // ─── Constructor ───────────────────────────────────────────────────────
    constructor(address zent_, address governor_, uint256 minStake_) {
        require(zent_ != address(0), "ZENTStaking: zero token");
        require(governor_ != address(0), "ZENTStaking: zero governor");

        zent = IERC20(zent_);
        minStake = minStake_;
        // Default to this contract as the insurance buffer. Governance MUST
        // call setInsuranceFund() before mainnet so slashed ZENT flows into
        // the real insurance contract (audit-finding H-4). Until then,
        // slashed ZENT accumulates in this contract's own balance — bounded
        // exposure, no leak back to the slasher.
        insuranceFund = address(this);
        emit InsuranceFundUpdated(address(0), address(this));

        _grantRole(DEFAULT_ADMIN_ROLE, governor_);
        _grantRole(GOVERNOR_ROLE, governor_);
    }

    /// @notice Update the insurance fund recipient.
    /// @dev    Governor-only. Rejects address(0) to prevent slashed ZENT
    ///         from being burned to the zero address by accident.
    function setInsuranceFund(address newFund) external onlyRole(GOVERNOR_ROLE) {
        require(newFund != address(0), "ZENTStaking: zero insurance fund");
        address previous = insuranceFund;
        insuranceFund = newFund;
        emit InsuranceFundUpdated(previous, newFund);
    }

    // ─── Stake ─────────────────────────────────────────────────────────────

    /// @inheritdoc IZENTStaking
    function stake(uint256 amount, uint64 lockDuration) external returns (uint64 lockEnd) {
        require(amount > 0, "ZENTStaking: zero amount");
        require(lockDuration >= MIN_LOCK && lockDuration <= MAX_LOCK, "ZENTStaking: lock out of range");
        // Intentional existence check: a zero stored amount means the caller has no position.
        // slither-disable-next-line incorrect-equality
        require(_positions[msg.sender].amount == 0, "ZENTStaking: position exists");

        lockEnd = uint64(block.timestamp) + lockDuration;
        uint128 amount128 = amount.toUint128();
        _positions[msg.sender] = Position({amount: amount128, lockEnd: lockEnd});
        totalStaked += amount;

        uint256 ve = _veAt(amount128, lockEnd, uint64(block.timestamp));
        totalVeSupply += ve;

        emit Staked(msg.sender, amount, lockEnd);
        zent.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IZENTStaking
    function increaseAmount(uint256 amount) external {
        require(amount > 0, "ZENTStaking: zero amount");

        Position storage pos = _positions[msg.sender];
        require(pos.amount > 0, "ZENTStaking: no position");
        require(block.timestamp < pos.lockEnd, "ZENTStaking: lock expired");

        uint128 oldAmount = pos.amount;
        uint256 newAmount = uint256(oldAmount) + amount;
        pos.amount = newAmount.toUint128();
        totalStaked += amount;

        uint256 oldVe = _veAt(oldAmount, pos.lockEnd, uint64(block.timestamp));
        uint256 newVe = _veAt(pos.amount, pos.lockEnd, uint64(block.timestamp));
        totalVeSupply = totalVeSupply - oldVe + newVe;

        emit Increased(msg.sender, amount, newAmount);
        zent.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IZENTStaking
    function extendLock(uint64 newLockDuration) external returns (uint64 newLockEnd) {
        require(newLockDuration <= MAX_LOCK, "ZENTStaking: lock out of range");

        Position storage pos = _positions[msg.sender];
        require(pos.amount > 0, "ZENTStaking: no position");

        newLockEnd = uint64(block.timestamp) + newLockDuration;
        uint64 oldLockEnd = pos.lockEnd;
        require(newLockEnd > oldLockEnd, "ZENTStaking: not extending");

        pos.lockEnd = newLockEnd;
        emit Extended(msg.sender, oldLockEnd, newLockEnd);
    }

    /// @inheritdoc IZENTStaking
    function withdraw() external {
        Position storage pos = _positions[msg.sender];
        uint256 amount = pos.amount;
        require(amount > 0, "ZENTStaking: no position");
        require(block.timestamp >= pos.lockEnd, "ZENTStaking: locked");

        uint256 oldVe = _veAt(uint128(amount), pos.lockEnd, uint64(block.timestamp));
        delete _positions[msg.sender];
        totalStaked -= amount;
        totalVeSupply -= oldVe;

        emit Withdrawn(msg.sender, amount);
        zent.safeTransfer(msg.sender, amount);
    }

    // ─── Views ─────────────────────────────────────────────────────────────

    /// @inheritdoc IZENTStaking
    function veBalance(address user) public view returns (uint256) {
        Position memory pos = _positions[user];
        // Intentional existence check: a zero stored amount means no active position.
        // slither-disable-next-line incorrect-equality
        if (pos.amount == 0 || block.timestamp >= pos.lockEnd) return 0;

        uint256 remaining = uint256(pos.lockEnd) - block.timestamp;
        return (uint256(pos.amount) * remaining) / MAX_LOCK;
    }

    /// @dev Pure helper: computes veBalance at a given (amount, lockEnd, timestamp).
    function _veAt(uint128 amount, uint64 lockEnd, uint64 at) private pure returns (uint256) {
        if (amount == 0 || at >= lockEnd) return 0;
        return (uint256(amount) * (uint256(lockEnd) - at)) / MAX_LOCK;
    }

    /// @inheritdoc IZENTStaking
    function hasAccess(address user) external view returns (bool) {
        Position memory pos = _positions[user];
        return pos.amount >= minStake && block.timestamp < pos.lockEnd;
    }

    /// @inheritdoc IZENTStaking
    function stakedBalance(address user) external view returns (uint256) {
        return _positions[user].amount;
    }

    /// @notice Expose position lock end for off-chain consumers.
    function lockEndOf(address user) external view returns (uint64) {
        return _positions[user].lockEnd;
    }

    // ─── Governor-Only ────────────────────────────────────────────────────

    /// @inheritdoc IZENTStaking
    function setMinStake(uint256 newMinStake) external onlyRole(GOVERNOR_ROLE) {
        uint256 old = minStake;
        minStake = newMinStake;
        emit MinStakeUpdated(old, newMinStake);
    }

    /// @inheritdoc IZENTStaking
    function getProviderStake(address provider) external view returns (uint256 stakeAmount) {
        Position memory pos = _positions[provider];
        return pos.amount;
    }

    /// @inheritdoc IZENTStaking
    function getStakeAtEpoch(address provider, uint256 /* epochId */) external view returns (uint256 stakeAmount) {
        // Stub: returns current stake for any epoch since ZENTStaking does not store per-epoch history.
        // Production systems should emit StakeUpdated events and maintain epoch-indexed state.
        Position memory pos = _positions[provider];
        return pos.amount;
    }

    /// @inheritdoc IZENTStaking
    function slash(address provider, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
        if (amount == 0) return;
        Position storage pos = _positions[provider];
        require(pos.amount >= amount, "ZENTStaking: slash exceeds stake");

        uint128 newAmount = pos.amount - uint128(amount);
        uint256 oldVe = _veAt(pos.amount, pos.lockEnd, uint64(block.timestamp));
        uint256 newVe = _veAt(newAmount, pos.lockEnd, uint64(block.timestamp));

        pos.amount = newAmount;
        totalStaked -= amount;
        totalVeSupply = totalVeSupply - oldVe + newVe;

        emit ProviderSlashed(provider, amount, msg.sender);
        // H-4 fix: route slashed ZENT to the insurance fund, not the slasher.
        // Previously sent to msg.sender, which is always the GOVERNOR_ROLE
        // holder (EpochScoring) — slashed ZENT got stuck in that contract
        // forever, and the insurance fund never accumulated from slashing.
        address fund = insuranceFund;
        if (fund != address(this)) {
            zent.safeTransfer(fund, amount);
        }
        // When fund == address(this), the slashed ZENT just stays in this
        // contract's balance as an internal buffer until governance points
        // `insuranceFund` at a real recipient.
    }

    /// @inheritdoc IZENTStaking
    function reward(address provider, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
        if (amount == 0) return;
        Position storage pos = _positions[provider];
        require(pos.amount > 0, "ZENTStaking: no position to reward");

        uint256 oldVe = _veAt(pos.amount, pos.lockEnd, uint64(block.timestamp));
        uint128 newAmount = pos.amount + uint128(amount);
        uint256 newVe = _veAt(newAmount, pos.lockEnd, uint64(block.timestamp));

        pos.amount = newAmount;
        totalStaked += amount;
        totalVeSupply = totalVeSupply - oldVe + newVe;

        emit ProviderRewarded(provider, amount);
        zent.safeTransferFrom(msg.sender, address(this), amount);
    }
}

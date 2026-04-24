// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title ModelBonding
/// @notice Strategy providers bond ZENT as skin-in-the-game. The RiskCouncil can slash
///         bonded ZENT and route it to the insurance fund when a provider's strategy
///         underperforms beyond protocol-defined thresholds.
/// @dev    Unbonding requires a cooldown to ensure bonded capital remains slashable while
///         an investigation window is open. Pending unbond amounts remain at stake and are
///         slashable; they are automatically capped if a slash reduces the total bond below
///         the pending unbond amount.
contract ModelBonding is AccessControl {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ─── Roles ─────────────────────────────────────────────────────────────
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");

    // ─── State ─────────────────────────────────────────────────────────────
    IERC20 public immutable zent;

    /// @notice Destination for slashed ZENT (governor-adjustable).
    address public insuranceFund;

    /// @notice Delay between `requestUnbond` and `claimUnbond` (governor-adjustable).
    uint64 public unbondCooldown;

    /// @notice Sum of all active bonds (excluding paid-out unbonds).
    uint256 public totalBonded;

    struct Bond {
        uint128 amount;
        uint128 unbondAmount;
        uint64 unbondRequestedAt;
    }

    mapping(address => Bond) private _bonds;

    // ─── Events ────────────────────────────────────────────────────────────
    event Bonded(address indexed provider, uint256 amount, uint256 newBalance);
    event UnbondRequested(address indexed provider, uint256 amount, uint64 readyAt);
    event UnbondClaimed(address indexed provider, uint256 amount);
    event UnbondCancelled(address indexed provider, uint256 amount);
    event Slashed(address indexed provider, uint256 amount, string reason);
    event InsuranceFundUpdated(address indexed previous, address indexed current);
    event UnbondCooldownUpdated(uint64 previous, uint64 current);

    // ─── Constructor ───────────────────────────────────────────────────────
    constructor(
        address zent_,
        address governor_,
        address riskCouncil_,
        address insuranceFund_,
        uint64 unbondCooldown_
    ) {
        require(zent_ != address(0), "ModelBonding: zero token");
        require(governor_ != address(0), "ModelBonding: zero governor");
        require(riskCouncil_ != address(0), "ModelBonding: zero council");
        require(insuranceFund_ != address(0), "ModelBonding: zero insurance");

        zent = IERC20(zent_);
        insuranceFund = insuranceFund_;
        unbondCooldown = unbondCooldown_;

        _grantRole(DEFAULT_ADMIN_ROLE, governor_);
        _grantRole(GOVERNOR_ROLE, governor_);
        _grantRole(RISK_COUNCIL_ROLE, riskCouncil_);
    }

    // ─── Bond ──────────────────────────────────────────────────────────────

    /// @notice Deposit ZENT and credit the caller's bond balance.
    function bond(uint256 amount) external {
        require(amount > 0, "ModelBonding: zero amount");

        Bond storage b = _bonds[msg.sender];
        uint256 newBalance = uint256(b.amount) + amount;
        b.amount = newBalance.toUint128();
        totalBonded += amount;

        emit Bonded(msg.sender, amount, newBalance);
        zent.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Queue an amount to be unbonded. Tokens remain at stake and are slashable
    ///         during the cooldown.
    function requestUnbond(uint256 amount) external {
        require(amount > 0, "ModelBonding: zero amount");

        Bond storage b = _bonds[msg.sender];
        require(amount <= b.amount, "ModelBonding: exceeds bond");
        require(b.unbondRequestedAt == 0, "ModelBonding: request pending");

        b.unbondAmount = amount.toUint128();
        uint64 readyAt = uint64(block.timestamp) + unbondCooldown;
        b.unbondRequestedAt = uint64(block.timestamp);

        emit UnbondRequested(msg.sender, amount, readyAt);
    }

    /// @notice Finalize a pending unbond after the cooldown has elapsed.
    function claimUnbond() external {
        Bond storage b = _bonds[msg.sender];
        uint256 amount = b.unbondAmount;
        require(amount > 0, "ModelBonding: no request");
        require(block.timestamp >= uint256(b.unbondRequestedAt) + unbondCooldown, "ModelBonding: cooldown active");

        b.amount = uint128(uint256(b.amount) - amount);
        b.unbondAmount = 0;
        b.unbondRequestedAt = 0;
        totalBonded -= amount;

        emit UnbondClaimed(msg.sender, amount);
        zent.safeTransfer(msg.sender, amount);
    }

    /// @notice Cancel a pending unbond request without withdrawing.
    function cancelUnbond() external {
        Bond storage b = _bonds[msg.sender];
        uint256 amount = b.unbondAmount;
        require(amount > 0, "ModelBonding: no request");

        b.unbondAmount = 0;
        b.unbondRequestedAt = 0;

        emit UnbondCancelled(msg.sender, amount);
    }

    // ─── Slashing ──────────────────────────────────────────────────────────

    /// @notice Slash a provider's bond and send the slashed ZENT to the insurance fund.
    ///         Reserved for the RiskCouncil. If the remaining bond would drop below the
    ///         pending unbond amount, the pending unbond is capped automatically.
    function slash(address provider, uint256 amount, string calldata reason) external onlyRole(RISK_COUNCIL_ROLE) {
        Bond storage b = _bonds[provider];
        require(amount > 0 && amount <= b.amount, "ModelBonding: invalid amount");

        uint128 newBalance = uint128(uint256(b.amount) - amount);
        b.amount = newBalance;
        if (b.unbondAmount > newBalance) {
            b.unbondAmount = newBalance;
        }
        totalBonded -= amount;

        emit Slashed(provider, amount, reason);
        zent.safeTransfer(insuranceFund, amount);
    }

    // ─── Governor-Only ────────────────────────────────────────────────────

    function setInsuranceFund(address newFund) external onlyRole(GOVERNOR_ROLE) {
        require(newFund != address(0), "ModelBonding: zero insurance");
        address old = insuranceFund;
        insuranceFund = newFund;
        emit InsuranceFundUpdated(old, newFund);
    }

    function setUnbondCooldown(uint64 newCooldown) external onlyRole(GOVERNOR_ROLE) {
        uint64 old = unbondCooldown;
        unbondCooldown = newCooldown;
        emit UnbondCooldownUpdated(old, newCooldown);
    }

    // ─── Views ─────────────────────────────────────────────────────────────

    function bondOf(address provider) external view returns (uint256) {
        return _bonds[provider].amount;
    }

    function pendingUnbond(address provider) external view returns (uint256 amount, uint64 readyAt) {
        Bond memory b = _bonds[provider];
        amount = b.unbondAmount;
        // Intentional zero check: no pending request means no ready-at time.
        // slither-disable-next-line incorrect-equality
        readyAt = amount == 0 ? 0 : b.unbondRequestedAt + unbondCooldown;
    }
}

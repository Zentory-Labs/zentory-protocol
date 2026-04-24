// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title ZENTVesting
/// @notice Simple vesting contract for ZENT team and investor allocations.
///         Implements linear vesting with a cliff period.
///         Tokens are pre-deposited; beneficiaries can claim after the cliff.
contract ZENTVesting {
    using SafeCast for uint256;

    /// @notice Emitted when a beneficiary claims vested tokens
    event Claimed(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when the deployer funds this vesting contract with ZENT
    event Funded(address indexed from, uint256 amount);

    /// @notice Vesting schedule for a single beneficiary
    struct VestingSchedule {
        uint128 totalAmount; // Total tokens allocated
        uint64 startTime; // TGE timestamp (seconds)
        uint64 cliffDuration; // Cliff period in seconds
        uint64 vestDuration; // Total vesting duration after cliff (linear)
        uint128 claimed; // Amount already claimed
        bool revocable; // Whether the deployer can revoke
        bool revoked; // Whether it has been revoked
    }

    /// @notice ZENT token reference
    ERC20 public immutable zent;

    /// @notice Deployer (typically a Multisig or DAO Timelock) — can revoke revocable schedules
    address public immutable deployer;

    /// @notice Mapping from beneficiary address to vesting schedule
    mapping(address => VestingSchedule) public schedules;

    /// @notice List of all beneficiary addresses (for enumeration)
    address[] public beneficiaries;

    modifier onlyDeployer() {
        require(msg.sender == deployer, "ZENTVesting: not deployer");
        _;
    }

    constructor(address zentToken_) {
        require(zentToken_ != address(0), "ZENTVesting: zero zent");
        zent = ERC20(zentToken_);
        deployer = msg.sender;
    }

    /// @notice Fund and set vesting schedule for a batch of beneficiaries.
    /// @dev Must be called after ZENT has been approved for transfer.
    function fund(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts,
        uint64[] calldata _cliffs,
        uint64[] calldata _vestDurations,
        bool[] calldata _revocables,
        uint64 startTime_
    ) external onlyDeployer {
        require(_beneficiaries.length == _amounts.length, "ZENTVesting: length mismatch");
        require(_beneficiaries.length == _cliffs.length, "ZENTVesting: length mismatch");
        require(_beneficiaries.length == _vestDurations.length, "ZENTVesting: length mismatch");
        require(_beneficiaries.length == _revocables.length, "ZENTVesting: length mismatch");

        uint256 totalToFund;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            require(_beneficiaries[i] != address(0), "ZENTVesting: zero beneficiary");
            require(_amounts[i] > 0, "ZENTVesting: zero amount");
            require(_vestDurations[i] > 0, "ZENTVesting: zero duration");

            for (uint256 j = 0; j < i; j++) {
                require(_beneficiaries[i] != _beneficiaries[j], "ZENTVesting: duplicate beneficiary");
            }

            require(schedules[_beneficiaries[i]].totalAmount == 0, "ZENTVesting: schedule exists");
            totalToFund += _amounts[i];
        }

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            beneficiaries.push(_beneficiaries[i]);
            schedules[_beneficiaries[i]] = VestingSchedule({
                totalAmount: _amounts[i].toUint128(),
                startTime: startTime_,
                cliffDuration: _cliffs[i],
                vestDuration: _vestDurations[i],
                claimed: 0,
                revocable: _revocables[i],
                revoked: false
            });
        }

        require(zent.transferFrom(msg.sender, address(this), totalToFund), "ZENTVesting: transfer failed");
        emit Funded(msg.sender, totalToFund);
    }

    /// @notice Number of beneficiaries
    function beneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }

    /// @notice Compute the vested amount for a beneficiary at the current timestamp.
    function vestedAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory s = schedules[beneficiary];
        if (s.totalAmount == 0) return 0;
        uint256 vested = s.revoked ? s.totalAmount : _vestedTotal(s, block.timestamp);
        if (vested <= s.claimed) return 0;
        return vested - s.claimed;
    }

    /// @notice Claim available vested tokens to the beneficiary's own address.
    function claim() external returns (uint256) {
        address beneficiary = msg.sender;
        uint256 claimable = vestedAmount(beneficiary);
        require(claimable > 0, "ZENTVesting: nothing to claim");

        schedules[beneficiary].claimed = (schedules[beneficiary].claimed + claimable).toUint128();
        require(zent.transfer(beneficiary, claimable), "ZENTVesting: transfer failed");
        emit Claimed(beneficiary, claimable);
        return claimable;
    }

    /// @notice Deployer can revoke a revocable schedule and reclaim unvested tokens.
    function revoke(address beneficiary) external onlyDeployer {
        VestingSchedule storage s = schedules[beneficiary];
        require(s.revocable, "ZENTVesting: not revocable");
        require(!s.revoked, "ZENTVesting: already revoked");

        uint256 vested = _vestedTotal(s, block.timestamp);
        uint256 unvested = s.totalAmount - vested;

        s.totalAmount = vested.toUint128();
        s.revoked = true;
        if (unvested > 0) {
            require(zent.transfer(deployer, unvested), "ZENTVesting: transfer failed");
        }
    }

    function _vestedTotal(VestingSchedule memory s, uint256 timestamp) internal pure returns (uint256) {
        uint256 cliffEnd = uint256(s.startTime) + s.cliffDuration;
        if (timestamp < cliffEnd) return 0;

        uint256 elapsed = timestamp - cliffEnd;
        if (elapsed >= s.vestDuration) return s.totalAmount;

        return (uint256(s.totalAmount) * elapsed) / s.vestDuration;
    }
}

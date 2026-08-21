// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title InsuranceFund
/// @notice Dedicated, governance-controlled reserve that backstops the protocol.
///         Receives the FeeDistributor insurance share + slashed ModelBonding /
///         ZENTStaking bonds, and holds them until governance pays out to cover a
///         shortfall (an exploit, oracle failure, or bad-debt event).
///
/// @dev    WHY A DISTINCT CONTRACT (M10): every deploy script previously defaulted
///         `INSURANCE_FUND` to the ProtocolTreasury, so insurance reserves were
///         indistinguishable from — and could be swept into — buyback/ops. This
///         gives the insurance allocation its own on-chain identity and balance
///         that anyone can audit, and a payout path gated solely to governance.
///
///         Funds arrive by plain ERC20 transfer (no deposit function needed).
///         The owner MUST be the Gnosis Safe / Timelock on mainnet, never an EOA.
// Ownable2Step (2026 re-scan, AC-4/ACC-002): governance handover requires the new
// owner to acceptOwnership, so a mistyped transfer can't orphan the payout authority.
contract InsuranceFund is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @param token  asset paid out
    /// @param to     recipient (typically a vault or the treasury, to make depositors whole)
    /// @param amount amount transferred
    /// @param reason short on-chain rationale for transparency (e.g. "zBTC bad debt 2026-Q4")
    event PaidOut(address indexed token, address indexed to, uint256 amount, string reason);

    // Ownable(governance) reverts with OwnableInvalidOwner(0) if governance is
    // the zero address, so no extra zero-check is needed here.
    constructor(address governance) Ownable(governance) {}

    /// @notice Current reserve balance of `token` held by the fund. Public so
    ///         reserves are auditable on-chain at a known address.
    function reserveOf(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Governance pays reserves out to cover a protocol shortfall, or to
    ///         recover tokens misrouted to this contract. Owner-only; the `reason`
    ///         is emitted for an on-chain audit trail.
    function payout(address token, address to, uint256 amount, string calldata reason) external onlyOwner {
        require(to != address(0), "InsuranceFund: zero recipient");
        require(amount > 0, "InsuranceFund: zero amount");
        IERC20(token).safeTransfer(to, amount);
        emit PaidOut(token, to, amount, reason);
    }
}

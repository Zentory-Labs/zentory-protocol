// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MerkleDistributor
/// @notice Pull-based airdrop distributor. Recipients claim their allocation
///         by submitting their (wallet, amount, merkleProof) tuple. Funds
///         are paid from this contract's ZENT balance; admin tops it up
///         once with the total allocation pre-launch.
///
///         Same shape as the Uniswap / 1inch / dYdX distributors — battle-
///         tested pattern. We deliberately do not roll our own crypto.
///
///         Flow:
///           1. Compute snapshot off-chain (scripts/airdrop/snapshot.ts)
///           2. Deploy this contract with the Merkle root + token address
///           3. Transfer the total ZENT allocation to this contract
///           4. Publish merkle proofs to the dApp claim page
///           5. Recipients call claim() with their proof
///           6. Unclaimed tokens after expiry → admin sweeps back to treasury
///
/// @dev Storage layout chosen for gas: each claimed slot is one storage
///      bit indexed by the recipient's index in the sorted Merkle leaves.
///      Costs ~5k gas per claim vs ~20k for a per-address mapping.
contract MerkleDistributor is AccessControl {
    using SafeERC20 for IERC20;

    // ─── Roles ─────────────────────────────────────────────────────────
    /// @notice Can sweep unclaimed tokens after expiry. Should be the
    ///         protocol multisig / Timelock, never the deployer EOA.
    bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER_ROLE");

    // ─── Immutable config ───────────────────────────────────────────────
    /// @notice ZENT token address (immutable for security).
    IERC20 public immutable token;
    /// @notice Merkle root committing to the (recipient, amount) tuple set.
    bytes32 public immutable merkleRoot;
    /// @notice Unix timestamp after which unclaimed tokens can be swept.
    uint256 public immutable claimDeadline;

    // ─── State ──────────────────────────────────────────────────────────
    /// @notice Bit-packed claimed status. claimedBitMap[wordIdx] bit (idx % 256).
    mapping(uint256 => uint256) private claimedBitMap;

    // ─── Events ─────────────────────────────────────────────────────────
    event Claimed(uint256 indexed index, address indexed account, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    // ─── Errors ─────────────────────────────────────────────────────────
    error AlreadyClaimed(uint256 index);
    error InvalidProof();
    error ClaimWindowClosed();
    error SweepBeforeDeadline();
    error InvalidConfig();

    // ─── Constructor ────────────────────────────────────────────────────
    /// @param token_         ZENT token contract
    /// @param merkleRoot_    Pre-computed root over double-hashed leaf =
    ///                       keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))))
    /// @param claimDeadline_ Unix timestamp after which sweep() is allowed.
    ///                       Recommended: 90 days post-deploy.
    /// @param admin_         Holder of DEFAULT_ADMIN_ROLE + SWEEPER_ROLE.
    ///                       MUST be a multisig, not an EOA.
    constructor(
        IERC20 token_,
        bytes32 merkleRoot_,
        uint256 claimDeadline_,
        address admin_
    ) {
        if (address(token_) == address(0) || merkleRoot_ == bytes32(0)) revert InvalidConfig();
        if (claimDeadline_ <= block.timestamp) revert InvalidConfig();
        if (admin_ == address(0)) revert InvalidConfig();

        token = token_;
        merkleRoot = merkleRoot_;
        claimDeadline = claimDeadline_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(SWEEPER_ROLE, admin_);
    }

    // ─── Claim ──────────────────────────────────────────────────────────

    /// @notice Returns whether the leaf at `index` has been claimed.
    function isClaimed(uint256 index) public view returns (bool) {
        uint256 wordIdx = index / 256;
        uint256 bitIdx = index % 256;
        uint256 word = claimedBitMap[wordIdx];
        uint256 mask = (1 << bitIdx);
        return word & mask == mask;
    }

    /// @notice Claim `amount` of ZENT for `account`. Anyone can submit on
    ///         behalf of the recipient (the proof is the gate, not msg.sender).
    /// @dev    Reverts if already claimed, proof invalid, or window closed.
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        if (block.timestamp > claimDeadline) revert ClaimWindowClosed();
        if (isClaimed(index)) revert AlreadyClaimed(index);

        // Verify proof. Audit M-8: use double-hashed leaves (the
        // OpenZeppelin / Uniswap standard) so a crafted internal tree node
        // can never be replayed as a valid leaf. abi.encode (not
        // encodePacked) avoids any ambiguity across the fixed-width fields.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) revert InvalidProof();

        // Mark claimed.
        _setClaimed(index);

        // Transfer.
        token.safeTransfer(account, amount);

        emit Claimed(index, account, amount);
    }

    function _setClaimed(uint256 index) private {
        uint256 wordIdx = index / 256;
        uint256 bitIdx = index % 256;
        claimedBitMap[wordIdx] = claimedBitMap[wordIdx] | (1 << bitIdx);
    }

    // ─── Sweep unclaimed (post-deadline) ────────────────────────────────

    /// @notice Sweep all remaining tokens back to `recipient` after the
    ///         claim deadline. Only callable by SWEEPER_ROLE — should
    ///         be the protocol multisig.
    function sweep(address recipient) external onlyRole(SWEEPER_ROLE) {
        if (block.timestamp <= claimDeadline) revert SweepBeforeDeadline();
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        token.safeTransfer(recipient, balance);
        emit Swept(recipient, balance);
    }
}

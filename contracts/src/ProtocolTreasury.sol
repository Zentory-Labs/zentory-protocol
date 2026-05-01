// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Protocol Treasury
/// @notice Central wallet that receives all protocol fees (vault fees, sub fees, etc.)
///         and routes them: 50% to ZENTBuyback, 50% to operational treasury.
contract ProtocolTreasury is Ownable(msg.sender) {
    using SafeERC20 for IERC20;

    address public immutable buyback;
    address public immutable operations; // multi-sig or founder wallet

    uint256 public constant BUYBACK_SHARE_BPS = 5000; // 50%

    event Sweep(address indexed token, uint256 toBuyback, uint256 toOperations);

    constructor(address _buyback, address _operations) {
        require(_buyback != address(0), "ProtocolTreasury: zero buyback");
        require(_operations != address(0), "ProtocolTreasury: zero operations");
        buyback = _buyback;
        operations = _operations;
    }

    /// @notice Sweep all of a given token to buyback + operations.
    ///         Anyone can call — funds are permissionlessly distributed.
    function sweep(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) return;

        uint256 buybackAmount = (balance * BUYBACK_SHARE_BPS) / 10000;
        uint256 opsAmount = balance - buybackAmount;

        IERC20(token).safeTransfer(buyback, buybackAmount);
        IERC20(token).safeTransfer(operations, opsAmount);

        emit Sweep(token, buybackAmount, opsAmount);
    }
}

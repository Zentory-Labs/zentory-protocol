// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ZENT Buyback & Burn
/// @notice Accumulates USDC from protocol fees and uses it to buy ZENT from the market,
///         then burns the purchased ZENT to 0xdead. Non-discretionary execution model
///         (no governance control) to avoid securities classification.
contract ZENTBuyback is Ownable(msg.sender) {
    using SafeERC20 for IERC20;

    IERC20 public immutable zent;   // ZENT token
    IERC20 public immutable usdc;   // fee payment token (USDC or USDC-like)

    uint256 public minBuybackThreshold; // minimum USDC balance to trigger buyback
    address public constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    event BuybackExecuted(address indexed caller, uint256 usdcSpent, uint256 zentBurned);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    error BelowThreshold(uint256 currentBalance);

    constructor(address _zent, address _usdc, uint256 _minThreshold) {
        require(_zent != address(0), "ZENTBuyback: zero ZENT address");
        require(_usdc != address(0), "ZENTBuyback: zero USDC address");

        zent = IERC20(_zent);
        usdc = IERC20(_usdc);
        minBuybackThreshold = _minThreshold;
    }

    /// @notice Called by keeper or automation when this contract's USDC
    ///         balance >= threshold. Swaps USDC for ZENT on the market and
    ///         burns ZENT to dead address.
    /// @dev Integration-ready: in production route through a DEX aggregator (e.g. 1inch).
    ///      For standalone testing the contract accepts pre-bought ZENT and burns it.
    ///
    ///      Audit M-5 fix: the previous implementation called
    ///      `safeTransferFrom(msg.sender, address(this), callerBalance)` —
    ///      a pull-everything pattern that would drain any address with an
    ///      outstanding USDC approval to this contract. This contract is
    ///      funded *by* the FeeDistributor and ProtocolTreasury, which do
    ///      direct safeTransfer (not approve), so the pull was never the
    ///      intended fueling path. Removing it closes the griefing vector.
    function execute() external {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance < minBuybackThreshold) {
            revert BelowThreshold(usdcBalance);
        }

        // In production: swap USDC -> ZENT via DEX and burn acquired ZENT.
        // For testing: accept ZENT that was pre-purchased and burn it.
        uint256 zentBalance = zent.balanceOf(address(this));
        if (zentBalance > 0) {
            zent.safeTransfer(deadAddress, zentBalance);
        }

        emit BuybackExecuted(msg.sender, usdcBalance, zentBalance);
    }

    /// @notice Update minimum threshold (owner only)
    function setThreshold(uint256 _newThreshold) external onlyOwner {
        emit ThresholdUpdated(minBuybackThreshold, _newThreshold);
        minBuybackThreshold = _newThreshold;
    }

    /// @notice Rescue accidentally sent tokens (owner only)
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(zent) && token != address(usdc), "ZENTBuyback: cannot rescue zent or usdc");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

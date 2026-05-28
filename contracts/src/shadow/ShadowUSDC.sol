// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ShadowUSDC
/// @notice TESTNET-ONLY mock USDC (6 decimals) used as the cash leg of the
///         shadow-mode SpotVault. Open mint for testnet provisioning.
///
/// ============================================================================
/// !!! NOT FOR MAINNET. Anyone can mint. Drop in real USDC for production.
/// ============================================================================
contract ShadowUSDC is ERC20 {
    constructor() ERC20("Zentory Shadow USDC", "sUSDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

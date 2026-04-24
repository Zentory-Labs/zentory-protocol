// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zSOLVault
/// @notice zSOL — benchmark-denominated vault tracking Solana (wSOL on HyperEVM).
contract zSOLVault is BaseVault {
    constructor(address _asset, address _feeRecipient, address _admin)
        BaseVault(
            _asset,
            "zSOL Share",
            "zSOL",
            30000,
            10000,
            2000,
            500,
            2000,
            _feeRecipient,
            _admin
        )
    {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zETHVault
/// @notice zETH — benchmark-denominated vault tracking Ethereum (WETH).
contract zETHVault is BaseVault {
    constructor(address _asset, address _feeRecipient, address _admin)
        BaseVault(
            _asset,
            "zETH Share",
            "zETH",
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

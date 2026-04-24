// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zXRPVault
/// @notice zXRP — benchmark-denominated vault tracking XRP (wXRP on HyperEVM).
contract zXRPVault is BaseVault {
    constructor(address _asset, address _feeRecipient, address _admin)
        BaseVault(
            _asset,
            "zXRP Share",
            "zXRP",
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zXRPVault
/// @notice zXRP — benchmark-denominated vault tracking XRP (wXRP on HyperEVM).
// slither-disable-next-line naming-convention
contract zXRPVault is BaseVault {
    constructor(address asset_, address feeRecipient_, address admin_)
        BaseVault(asset_, "zXRP Share", "zXRP", 30000, 10000, 2000, 500, 2000, feeRecipient_, admin_)
    {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zETHVault
/// @notice zETH — benchmark-denominated vault tracking Ethereum (WETH).
// slither-disable-next-line naming-convention
contract zETHVault is BaseVault {
    constructor(address asset_, address feeRecipient_, address admin_)
        BaseVault(asset_, "zETH Share", "zETH", 30000, 10000, 2000, 500, 2000, feeRecipient_, admin_)
    {}
}

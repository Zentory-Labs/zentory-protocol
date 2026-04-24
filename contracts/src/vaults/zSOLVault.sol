// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zSOLVault
/// @notice zSOL — benchmark-denominated vault tracking Solana (wSOL on HyperEVM).
// slither-disable-next-line naming-convention
contract zSOLVault is BaseVault {
    constructor(address asset_, address feeRecipient_, address admin_)
        BaseVault(asset_, "zSOL Share", "zSOL", 30000, 10000, 2000, 500, 2000, feeRecipient_, admin_)
    {}
}

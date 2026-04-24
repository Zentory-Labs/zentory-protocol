// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zBTCVault
/// @notice zBTC — benchmark-denominated vault tracking Bitcoin (WBTC).
// slither-disable-next-line naming-convention
contract zBTCVault is BaseVault {
    constructor(address asset_, address feeRecipient_, address admin_)
        BaseVault(
            asset_,
            "zBTC Share",
            "zBTC",
            30000, // maxLeverage: 3x
            10000, // maxPositionSizeBPS: 100% of TVL
            2000, // circuitBreakerDrawdownBPS: 20% drawdown
            500, // rebalanceThresholdBPS: 5% NAV drift
            2000, // performanceFeeBPS: 20%
            feeRecipient_,
            admin_
        )
    {}
}

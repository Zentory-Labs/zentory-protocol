// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title zBTCVault
/// @notice zBTC — benchmark-denominated vault tracking Bitcoin (WBTC).
contract zBTCVault is BaseVault {
    constructor(address _asset, address _feeRecipient, address _admin)
        BaseVault(
            _asset,
            "zBTC Share",
            "zBTC",
            30000, // maxLeverage: 3x
            10000, // maxPositionSizeBPS: 100% of TVL
            2000, // circuitBreakerDrawdownBPS: 20% drawdown
            500, // rebalanceThresholdBPS: 5% NAV drift
            2000, // performanceFeeBPS: 20%
            _feeRecipient,
            _admin
        )
    {}
}

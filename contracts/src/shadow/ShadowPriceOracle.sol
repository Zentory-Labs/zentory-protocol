// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "../vaults/SpotVault.sol";

/// @title ShadowPriceOracle
/// @notice TESTNET-ONLY Chainlink-compatible price feed for shadow-mode vault
///         demos. An UPDATER (typically the keeper bot, called every 4H from
///         off-chain Binance/HL data) sets the price; SpotVault consumes it via
///         the standard `latestRoundData` interface with its fail-closed
///         staleness guards. Drop-in replacement once a real Chainlink feed
///         exists on HyperEVM.
///
/// ============================================================================
/// !!! NOT FOR MAINNET. NOT AUDITED FOR PRODUCTION VALUE-FLOW. SHADOW DEMO ONLY.
/// ============================================================================
contract ShadowPriceOracle is AccessControl, AggregatorV3Interface {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint8 private immutable _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _round;

    event PriceUpdated(int256 answer, uint256 updatedAt, uint80 round);

    constructor(uint8 decimals_, int256 initialPrice, address admin) {
        require(decimals_ > 0 && decimals_ <= 18, "bad decimals");
        require(initialPrice > 0, "bad initial price");
        require(admin != address(0), "zero admin");
        _decimals = decimals_;
        _answer = initialPrice;
        _updatedAt = block.timestamp;
        _round = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPDATER_ROLE, admin);
    }

    function decimals() external view override returns (uint8) { return _decimals; }

    function latestRoundData()
        external view override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_round, _answer, _updatedAt, _updatedAt, _round);
    }

    /// @notice Push a new price. Reverts on non-positive values; updates round +
    ///         updatedAt so SpotVault's staleness guard sees a fresh feed.
    function setPrice(int256 newPrice) external onlyRole(UPDATER_ROLE) {
        require(newPrice > 0, "bad price");
        _answer = newPrice;
        _updatedAt = block.timestamp;
        unchecked { _round++; }
        emit PriceUpdated(newPrice, _updatedAt, _round);
    }
}

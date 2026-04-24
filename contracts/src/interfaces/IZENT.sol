// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

/// @title IZENT
/// @notice Interface for the ZENT governance token
interface IZENT is IERC20, IERC20Metadata, IERC5805 {
    error ZENT_ZeroAddress();
    error ZENT_Locked();

    /// @notice Returns the fixed token supply cap.
    // slither-disable-next-line naming-convention
    function CAP() external view returns (uint256);
}

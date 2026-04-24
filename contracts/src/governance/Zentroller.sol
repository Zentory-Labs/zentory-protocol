// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IZENTStaking} from "../interfaces/IZENTStaking.sol";

/// @title Zentroller
/// @notice Linkage contract: provides a single canonical address that the Governor can
///         query to resolve ZENT staking balance for voting weight. Decouples the Governor
///         from direct knowledge of the staking implementation.
contract Zentroller {
    IZENTStaking public immutable staking;

    constructor(address staking_, address /* guardian */) {
        require(staking_ != address(0), "Zentroller: zero staking");
        staking = IZENTStaking(staking_);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTVesting} from "../src/ZENTVesting.sol";
import {requireChainFromEnv} from "./lib/ChainGuard.sol";

/// @notice Deploys ZENT token and the team/backer vesting allocator.
/// @dev Run standalone:
///      forge script script/DeployCore.s.sol --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
///
/// Required env:
///      PRIVATE_KEY
///      TREASURY
///      TEAM_WALLET_1..5
///      BACKER_WALLET_1..3
///
/// Output key: CORE
contract DeployCore is Script {
    // ─── Vesting schedule constants ───────────────────────────────────────────
    uint64 constant TEAM_CLIFF    = 365 days;
    uint64 constant TEAM_VEST     = 1095 days; // ~36 months
    uint64 constant BACKERS_CLIFF = 182 days;  // ~6 months
    uint64 constant BACKERS_VEST  = 730 days;  // ~24 months

    uint256 constant TEAM_TOTAL   = 180_000_000e18;
    uint256 constant BACKER_TOTAL = 150_000_000e18;

    function run() external {
        // F-05: require EXPECTED_CHAIN_ID env var matches block.chainid.
        // Aborts before any broadcast if the RPC points at the wrong chain.
        requireChainFromEnv();

        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address treasury = _must("TREASURY");

        console2.log("Deployer:", deployer);
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(key);

        ZENT zent = new ZENT();
        console2.log("ZENT deployed:", address(zent));

        ZENTVesting vesting = new ZENTVesting(address(zent));
        console2.log("ZENTVesting deployed:", address(vesting));

        // Fund team + backer vesting
        zent.approve(address(vesting), TEAM_TOTAL + BACKER_TOTAL);
        _fundTeam(vesting);
        _fundBackers(vesting);

        // Send any residual tokens to treasury
        uint256 remainder = zent.balanceOf(deployer);
        if (remainder > 0) {
            require(zent.transfer(treasury, remainder), "transfer failed");
            console2.log("Treasury remainder:", remainder);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== CORE DEPLOYED ===");
        console2.log("ZENT:", address(zent));
        console2.log("Vesting:", address(vesting));
        console2.log("Treasury:", treasury);

        _writeAddress("ZENT", address(zent));
        _writeAddress("ZENT_VESTING", address(vesting));
    }

    function _fundTeam(ZENTVesting vesting) internal {
        address[] memory wallets  = new address[](5);
        uint256[] memory amounts  = new uint256[](5);
        uint64[] memory cliffs     = new uint64[](5);
        uint64[] memory durations  = new uint64[](5);
        bool[]    memory revocable = new bool[](5);

        for (uint256 i = 0; i < 5; i++) {
            wallets[i]   = _must(string.concat("TEAM_WALLET_", vm.toString(i + 1)));
            amounts[i]   = 36_000_000e18;
            cliffs[i]    = TEAM_CLIFF;
            durations[i] = TEAM_VEST;
            revocable[i] = true;
        }

        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _fundBackers(ZENTVesting vesting) internal {
        address[] memory wallets  = new address[](3);
        uint256[] memory amounts  = new uint256[](3);
        uint64[] memory cliffs     = new uint64[](3);
        uint64[] memory durations  = new uint64[](3);
        bool[]    memory revocable = new bool[](3);

        wallets[0]  = _must("BACKER_WALLET_1");  amounts[0]  = 75_000_000e18;
        wallets[1]  = _must("BACKER_WALLET_2");  amounts[1]  = 50_000_000e18;
        wallets[2]  = _must("BACKER_WALLET_3");  amounts[2]  = 25_000_000e18;

        for (uint256 i = 0; i < 3; i++) {
            cliffs[i]    = BACKERS_CLIFF;
            durations[i] = BACKERS_VEST;
            revocable[i] = false;
        }

        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _must(string memory key) internal view returns (address) {
        address a = vm.envAddress(key);
        require(a != address(0) && a != address(0xdead), string.concat("DeployCore: missing ", key));
        return a;
    }

    function _writeAddress(string memory label, address a) internal {
        // Written to stdout so CI can capture via forge's broadcast log.
        console2.log(string.concat("ADDRESS_", label), a);
    }
}

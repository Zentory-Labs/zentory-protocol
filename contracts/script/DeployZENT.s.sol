// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTVesting} from "../src/ZENTVesting.sol";

/// @notice Deployment script for ZENT token and vesting contracts.
/// @dev Run with:
///      forge script script/DeployZENT.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
///
/// Required env:
///      PRIVATE_KEY, TREASURY
///      TEAM_WALLET_1..5, BACKER_WALLET_1..3
contract DeployZENT is Script {
    // Vesting durations
    uint64 constant TEAM_CLIFF = 365 days;
    uint64 constant TEAM_VEST_DUR = 1095 days; // ~36 months
    uint64 constant BACKERS_CLIFF = 182 days; // ~6 months
    uint64 constant BACKERS_VEST_DUR = 730 days; // ~24 months

    uint256 constant TEAM_TOTAL = 180_000_000e18;
    uint256 constant BACKER_TOTAL = 150_000_000e18;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address treasury = _requiredAddress("TREASURY");

        console2.log("Deployer address:", deployer);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1. Deploy ZENT token
        ZENT zent = new ZENT();
        console2.log("ZENT deployed at:", address(zent));

        // 2. Deploy vesting contract
        ZENTVesting vesting = new ZENTVesting(address(zent));
        console2.log("ZENTVesting deployed at:", address(vesting));

        zent.approve(address(vesting), TEAM_TOTAL + BACKER_TOTAL);
        _fundTeamVesting(vesting);
        _fundBackerVesting(vesting);

        // 6. Transfer remaining tokens to multisig treasury.
        // ZENT has no admin or mint surface to renounce.
        uint256 remainder = zent.balanceOf(deployer);
        if (remainder > 0) {
            zent.transfer(treasury, remainder);
            console2.log("Transferred remainder to treasury:", remainder);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Summary ===");
        console2.log("ZENT token:   ", address(zent));
        console2.log("ZENTVesting: ", address(vesting));
        console2.log("Treasury:", treasury);
        console2.log("Chain ID:", block.chainid);
    }

    function _fundTeamVesting(ZENTVesting vesting) internal {
        address[] memory wallets = new address[](5);
        uint256[] memory amounts = new uint256[](5);
        uint64[] memory cliffs = new uint64[](5);
        uint64[] memory durations = new uint64[](5);
        bool[] memory revocable = new bool[](5);

        for (uint256 i = 0; i < 5; i++) {
            wallets[i] = _requiredAddress(string.concat("TEAM_WALLET_", vm.toString(i + 1)));
            amounts[i] = 36_000_000e18;
            cliffs[i] = TEAM_CLIFF;
            durations[i] = TEAM_VEST_DUR;
            revocable[i] = true;
        }

        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _fundBackerVesting(ZENTVesting vesting) internal {
        address[] memory wallets = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint64[] memory cliffs = new uint64[](3);
        uint64[] memory durations = new uint64[](3);
        bool[] memory revocable = new bool[](3);

        wallets[0] = _requiredAddress("BACKER_WALLET_1");
        amounts[0] = 75_000_000e18;

        wallets[1] = _requiredAddress("BACKER_WALLET_2");
        amounts[1] = 50_000_000e18;

        wallets[2] = _requiredAddress("BACKER_WALLET_3");
        amounts[2] = 25_000_000e18;

        for (uint256 i = 0; i < 3; i++) {
            cliffs[i] = BACKERS_CLIFF;
            durations[i] = BACKERS_VEST_DUR;
            revocable[i] = false;
        }

        vesting.fund(wallets, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _requiredAddress(string memory key) internal view returns (address value) {
        value = vm.envAddress(key);
        require(value != address(0), "DeployZENT: zero address");
        require(value != address(0x000000000000000000000000000000000000dEaD), "DeployZENT: dead address");
    }
}

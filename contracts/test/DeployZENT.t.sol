// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployZENT} from "../script/DeployZENT.s.sol";

contract DeployZENTTest is Test {
    function test_runSucceedsWithExplicitDeploymentAddresses() external {
        vm.setEnv("PRIVATE_KEY", "1");
        vm.setEnv("TREASURY", vm.toString(makeAddr("treasury")));

        for (uint256 i = 1; i <= 5; i++) {
            vm.setEnv(
                string.concat("TEAM_WALLET_", vm.toString(i)),
                vm.toString(makeAddr(string.concat("team", vm.toString(i))))
            );
        }

        for (uint256 i = 1; i <= 3; i++) {
            vm.setEnv(
                string.concat("BACKER_WALLET_", vm.toString(i)),
                vm.toString(makeAddr(string.concat("backer", vm.toString(i))))
            );
        }

        DeployZENT deployScript = new DeployZENT();
        deployScript.run();
    }
}

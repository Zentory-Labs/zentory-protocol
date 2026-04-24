// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {zBTCVault} from "../../src/vaults/zBTCVault.sol";
import {zETHVault} from "../../src/vaults/zETHVault.sol";
import {zSOLVault} from "../../src/vaults/zSOLVault.sol";
import {zXRPVault} from "../../src/vaults/zXRPVault.sol";

contract VaultWrappersTest is Test {
    ERC20Mock internal asset;
    address internal admin = makeAddr("admin");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        asset = new ERC20Mock();
    }

    function test_wrappersUseExplicitAssetAndFeeRecipient() external {
        zBTCVault btc = new zBTCVault(address(asset), feeRecipient, admin);
        zETHVault eth = new zETHVault(address(asset), feeRecipient, admin);
        zSOLVault sol = new zSOLVault(address(asset), feeRecipient, admin);
        zXRPVault xrp = new zXRPVault(address(asset), feeRecipient, admin);

        assertEq(btc.asset(), address(asset));
        assertEq(eth.feeRecipient(), feeRecipient);
        assertEq(sol.asset(), address(asset));
        assertEq(xrp.feeRecipient(), feeRecipient);
    }
}

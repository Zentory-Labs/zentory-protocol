// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";

/// @dev Minimal SpotVault stand-in: records the last rebalance command. Mirrors
///      SpotVault.rebalanceTo's selector so StrategyExecutor.executeRebalance can
///      drive it without pulling in the full oracle/adapter machinery.
contract MockRebalancer {
    uint16  public lastTarget;
    uint256 public callCount;
    address public lastCaller;

    function rebalanceTo(uint16 targetWeightBps) external {
        lastTarget = targetWeightBps;
        lastCaller = msg.sender;
        callCount++;
    }
}

/// @notice Unit tests for the signed target-weight rebalance path
///         (StrategyExecutor.executeRebalance) that drives SpotVault v2.
contract ExecuteRebalanceTest is Test {
    StrategyExecutor exec;
    MockRebalancer vault;

    uint256 constant SIGNER_PK = 0xA11CE;
    address signer;
    address keeper = makeAddr("keeper");
    address governor = makeAddr("governor");

    function setUp() public {
        signer = vm.addr(SIGNER_PK);
        // hyperCore address is irrelevant to executeRebalance (never called); dummy non-zero.
        exec = new StrategyExecutor(makeAddr("hyperCore"), governor);
        // deployer (this) holds DEFAULT_ADMIN_ROLE in the constructor → wire signer + keeper.
        exec.setAuthorizedSigner(signer);
        exec.grantRole(exec.KEEPER_ROLE(), keeper);
        vault = new MockRebalancer();
    }

    function _sign(address v, uint16 wbps, uint256 nonce, uint256 expiry)
        internal
        view
        returns (bytes memory)
    {
        return _signWith(SIGNER_PK, v, wbps, nonce, expiry);
    }

    function _signWith(uint256 pk, address v, uint16 wbps, uint256 nonce, uint256 expiry)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(exec.REBALANCE_TYPEHASH(), v, wbps, nonce, expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", exec.DOMAIN_SEPARATOR(), structHash));
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, vSig);
    }

    function test_happyPath() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.prank(keeper);
        bool ok = exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
        assertTrue(ok);
        assertEq(vault.lastTarget(), 6000);
        assertEq(vault.callCount(), 1);
        assertEq(vault.lastCaller(), address(exec), "executor must be the caller into the vault");
        assertEq(exec.nonces(address(vault)), 1);
    }

    function test_replayReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.prank(keeper);
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(StrategyExecutor.NonceAlreadyUsed.selector, address(vault), 1));
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
    }

    function test_staleNonceReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        // Precompute sigs: _sign makes external view calls that would otherwise
        // consume the vm.prank before executeRebalance runs.
        bytes memory sig5 = _sign(address(vault), 6000, 5, expiry);
        bytes memory sig3 = _sign(address(vault), 6000, 3, expiry);
        // advance to nonce 5
        vm.prank(keeper);
        exec.executeRebalance(address(vault), 6000, 5, expiry, sig5);
        // nonce 3 (< 5) must be rejected
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(StrategyExecutor.NonceAlreadyUsed.selector, address(vault), 3));
        exec.executeRebalance(address(vault), 6000, 3, expiry, sig3);
    }

    function test_expiredReverts() public {
        uint256 expiry = block.timestamp + 100;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.warp(expiry + 1);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(StrategyExecutor.SignalExpired.selector, expiry, block.timestamp));
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
    }

    function test_badSignerReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _signWith(0xBADBAD, address(vault), 6000, 1, expiry);
        vm.prank(keeper);
        vm.expectRevert(StrategyExecutor.InvalidSignature.selector);
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
    }

    function test_tamperedWeightReverts() public {
        // sign for 6000 but submit 7000 → digest mismatch → InvalidSignature
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.prank(keeper);
        vm.expectRevert(StrategyExecutor.InvalidSignature.selector);
        exec.executeRebalance(address(vault), 7000, 1, expiry, sig);
    }

    function test_weightTooHighReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 10001, 1, expiry);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(StrategyExecutor.InvalidWeight.selector, uint16(10001)));
        exec.executeRebalance(address(vault), 10001, 1, expiry, sig);
        assertEq(vault.callCount(), 0, "vault must not be touched on invalid weight");
    }

    function test_nonKeeperReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.prank(makeAddr("rando"));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
    }

    function test_whenPausedReverts() public {
        exec.grantRole(exec.GUARDIAN_ROLE(), address(this));
        exec.setPaused(true);
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(vault), 6000, 1, expiry);
        vm.prank(keeper);
        vm.expectRevert(StrategyExecutor.PausedError.selector);
        exec.executeRebalance(address(vault), 6000, 1, expiry, sig);
    }

    function test_fullLongThenFlat() public {
        uint256 e = block.timestamp + 1 hours;
        bytes memory sigLong = _sign(address(vault), 10000, 1, e);
        bytes memory sigFlat = _sign(address(vault), 0, 2, e);
        vm.prank(keeper);
        exec.executeRebalance(address(vault), 10000, 1, e, sigLong);
        assertEq(vault.lastTarget(), 10000);
        vm.prank(keeper);
        exec.executeRebalance(address(vault), 0, 2, e, sigFlat);
        assertEq(vault.lastTarget(), 0, "flat accepted");
        assertEq(exec.nonces(address(vault)), 2);
        assertEq(vault.callCount(), 2);
    }

    function test_domainBindsToThisExecutor() public {
        // A signature is bound to a specific executor: a sig built for `exec` must
        // NOT verify on a second executor instance (different DOMAIN_SEPARATOR, since
        // the domain commits to address(this)).
        StrategyExecutor exec2 = new StrategyExecutor(makeAddr("hyperCore2"), governor);
        exec2.setAuthorizedSigner(signer);
        exec2.grantRole(exec2.KEEPER_ROLE(), keeper);

        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sigForExec = _sign(address(vault), 6000, 1, expiry); // uses exec.DOMAIN_SEPARATOR()

        vm.prank(keeper);
        vm.expectRevert(StrategyExecutor.InvalidSignature.selector);
        exec2.executeRebalance(address(vault), 6000, 1, expiry, sigForExec);
    }
}

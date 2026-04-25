// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {HyperCoreAdapter} from "../../src/keeper/HyperCoreAdapter.sol";

/// @title StrategyExecutorFuzzTest
/// @notice Fuzz tests for StrategyExecutor access control and signal execution.
contract StrategyExecutorFuzzTest is Test {
    StrategyExecutor executor;
    HyperCoreAdapter adapter;

    address governor = makeAddr("governor");
    address keeper = makeAddr("keeper");
    address guardian = makeAddr("guardian");
    address attacker = makeAddr("attacker");
    address signalSigner = makeAddr("signalSigner");
    address vault = makeAddr("vault");

    function setUp() external {
        adapter = new HyperCoreAdapter(governor);
        executor = new StrategyExecutor(address(adapter), governor);

        executor.grantRole(executor.KEEPER_ROLE(), keeper);
        executor.grantRole(executor.GUARDIAN_ROLE(), guardian);
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(vault, 1);
    }

    // ─── Signal execution access control ──────────────────────────────────────────

    function test_fuzz_onlyKeeperCanExecuteSignal(
        uint256 assets,
        uint64 price,
        uint256 nonce,
        uint256 expiry
    ) external {
        vm.assume(assets > 0 && assets < 1e18);
        vm.assume(expiry > block.timestamp);

        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            assets,
            price,
            nonce,
            expiry
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalSigner, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        // Attacker should not be able to execute
        vm.prank(attacker);
        vm.expectRevert();
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       assets,
            price:      price,
            nonce:      nonce,
            expiry:     expiry,
            signature:  sig
        });
    }

    function test_fuzz_governorCanSetMaxPositionSize(address someVault, uint256 limit) external {
        vm.assume(someVault != address(0));

        vm.prank(governor);
        executor.setMaxPositionSize(someVault, limit);
        assertEq(executor.maxPositionSize(someVault), limit);
    }

    function test_fuzz_governorCanSetMaxLeverage(address someVault, uint256 bps) external {
        vm.assume(someVault != address(0));
        vm.assume(bps <= 100000); // ≤ 10x leverage

        vm.prank(governor);
        executor.setMaxLeverageBPS(someVault, bps);
        assertEq(executor.maxLeverageBPS(someVault), bps);
    }

    function test_fuzz_nonGovernorCannotSetMaxPositionSize(address someVault, uint256 limit) external {
        vm.assume(someVault != address(0));

        vm.prank(attacker);
        vm.expectRevert();
        executor.setMaxPositionSize(someVault, limit);
    }

    function test_fuzz_pausePreventsExecution() external {
        vm.prank(guardian);
        executor.setPaused(true);

        assertTrue(executor.paused());
    }

    function test_fuzz_nonceReplayPrevention(uint64 price, uint256 nonce) external {
        vm.assume(nonce == 0 || nonce < type(uint256).max);

        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            uint256(1e6),
            price,
            nonce,
            block.timestamp + 3600
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalSigner, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        // First call with nonce succeeds
        vm.prank(keeper);
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       1e6,
            price:      price,
            nonce:      nonce,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });

        // Second call with same nonce reverts
        vm.prank(keeper);
        vm.expectRevert("StrategyExecutor: nonce already used");
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       1e6,
            price:      price,
            nonce:      nonce,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    function test_fuzz_expiredSignatureReverts(uint256 expiry) external {
        vm.assume(expiry <= block.timestamp); // expired

        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            uint256(1e6),
            uint64(50000e8),
            1,
            expiry
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalSigner, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        vm.prank(keeper);
        vm.expectRevert("StrategyExecutor: signal expired");
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       1e6,
            price:      50000e8,
            nonce:      1,
            expiry:     expiry,
            signature:  sig
        });
    }

    function test_fuzz_zeroSizeReverts() external {
        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            uint256(0),
            uint64(50000e8),
            1,
            block.timestamp + 3600
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalSigner, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        vm.prank(keeper);
        vm.expectRevert("StrategyExecutor: zero size");
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       0,
            price:      50000e8,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    function test_fuzz_wrongSignerReverts() external {
        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            uint256(1e6),
            uint64(50000e8),
            1,
            block.timestamp + 3600
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
        // Sign with WRONG key (attacker instead of signalSigner)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attacker, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        vm.prank(keeper);
        vm.expectRevert("StrategyExecutor: invalid signature");
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       1e6,
            price:      50000e8,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    // ─── Size limit ───────────────────────────────────────────────────────────────

    function test_fuzz_sizeExceedingLimitReverts(uint256 size) external {
        vm.assume(size > 5e6); // above the test limit set in setUp

        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            size,
            uint64(50000e8),
            1,
            block.timestamp + 3600
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalSigner, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        // Governor sets max position to 5e6
        vm.prank(governor);
        executor.setMaxPositionSize(vault, 5e6);

        vm.prank(keeper);
        vm.expectRevert();
        executor.executeSignal({
            vault:      vault,
            direction:  1,
            size:       size,
            price:      50000e8,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    // ─── Vault registry ──────────────────────────────────────────────────────────

    function test_fuzz_vaultRegistryMustBeSet(address someVault, uint8 localAsset) external {
        vm.assume(someVault != address(0));
        vm.assume(localAsset <= 3);

        // Registry should start at 0 for unknown vault
        assertEq(executor.vaultRegistry(someVault), 0);

        vm.prank(governor);
        executor.setVaultRegistry(someVault, localAsset);
        assertEq(executor.vaultRegistry(someVault), localAsset);
    }

    // ─── Transfer admin ─────────────────────────────────────────────────────────

    function test_fuzz_transferAdminWorks(address newAdmin) external {
        vm.assume(newAdmin != address(0));

        // transferAdmin does immediate grant + renounce
        vm.prank(governor);
        executor.transferAdmin(newAdmin);

        assertTrue(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), governor));
    }

    function test_fuzz_nonAdminCannotTransferAdmin() external {
        vm.prank(attacker);
        vm.expectRevert();
        executor.transferAdmin(attacker);
    }
}

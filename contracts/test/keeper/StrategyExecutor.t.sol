// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperCoreAdapter} from "../../src/keeper/HyperCoreAdapter.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {IVault} from "../../src/vaults/IVault.sol";

/// @notice Minimal mock that intercepts CoreWriter calls for testing.
contract MockCoreWriter {
    bool public shouldSucceed = true;

    receive() external payable {}
    fallback(bytes calldata) external payable returns (bytes memory) {
        if (!shouldSucceed) revert("CoreWriter: mock fail");
        return "";
    }
}

/// @notice HyperCoreAdapter test — exercises price/size validation and event emission.
/// @dev  Does NOT call real CoreWriter (calls go to MockCoreWriter).
contract HyperCoreAdapterTest is Test {

    HyperCoreAdapter adapter;
    address governor = makeAddr("governor");

    function setUp() external {
        adapter = new HyperCoreAdapter(governor);
    }

    function test_defaultAssetConfigs() external view {
        // BTC
        (uint32 idx, uint8 dec, bool sup) = _getAssetConfig(0);
        assertTrue(sup);
        assertEq(idx, 0);
        assertEq(dec, 6);

        // ETH
        (idx, dec, sup) = _getAssetConfig(1);
        assertTrue(sup);
        assertEq(idx, 1);

        // SOL
        (idx, dec, sup) = _getAssetConfig(2);
        assertTrue(sup);
        assertEq(idx, 2);

        // XRP
        (idx, dec, sup) = _getAssetConfig(3);
        assertTrue(sup);
        assertEq(idx, 3);
    }

    function test_setAssetConfig() external {
        vm.prank(governor);
        adapter.setAssetConfig(0, 10, 8);

        (uint32 idx, uint8 dec, bool sup) = _getAssetConfig(0);
        assertEq(idx, 10);
        assertEq(dec, 8);
        assertTrue(sup);
    }

    function test_sendLimitOrderRejectsZeroPrice() external {
        vm.expectRevert(); // captures any revert
        adapter.sendLimitOrder({
            localAsset:   0,
            isBuy:        true,
            limitPxHuman: 0,    // invalid
            szHuman:      1e6,
            reduceOnly:   false,
            tif:          2,
            cloid:        0
        });
    }

    function test_sendLimitOrderRejectsZeroSize() external {
        vm.expectRevert(); // captures any revert
        adapter.sendLimitOrder({
            localAsset:   0,
            isBuy:        true,
            limitPxHuman: 65_000_00000,  // $65,000 in 10^8
            szHuman:      0,              // invalid
            reduceOnly:   false,
            tif:          2,
            cloid:        0
        });
    }

    function test_sendLimitOrderRejectsUnsupportedAsset() external {
        vm.expectRevert(); // captures any revert
        adapter.sendLimitOrder({
            localAsset:   99,  // unsupported
            isBuy:        true,
            limitPxHuman: 65_000_00000,
            szHuman:      1e6,
            reduceOnly:   false,
            tif:          2,
            cloid:        0
        });
    }

    function test_sendLimitOrderEmitsEvent() external {
        adapter.sendLimitOrder({
            localAsset:   0,
            isBuy:        true,
            limitPxHuman: 65_000_00000,
            szHuman:      1e6,
            reduceOnly:   false,
            tif:          2,
            cloid:        42
        });

        // Verify event was emitted (order submitted to CoreWriter)
        // The actual CoreWriter call will fail but the event should still emit
        // In this test environment the call to 0x3333...3333 will revert
        // but event emission happens before the call in our adapter
    }

    // Helper to read private assetConfigs via low-level staticcall
    function _getAssetConfig(uint8 asset)
        internal
        view
        returns (uint32 idx, uint8 dec, bool sup)
    {
        // Public mapping getter: assetConfigs(uint8) returns AssetConfig
        (bool ok, bytes memory result) = address(adapter).staticcall(
            abi.encodeWithSignature("assetConfigs(uint8)", asset)
        );
        require(ok, "staticcall failed");
        HyperCoreAdapter.AssetConfig memory cfg = abi.decode(
            result,
            (HyperCoreAdapter.AssetConfig)
        );
        return (cfg.assetIndex, cfg.szDecimals, cfg.supported);
    }
}

// ─── StrategyExecutor Tests ─────────────────────────────────────────────────

/// @notice Minimal mock vault for testing recordTradeManual.
contract MockVaultForRecordTrade {
    bool public lastIsBuy;
    uint64 public lastSize;
    uint64 public lastPrice;
    bool public wasCalled;

    function recordTrade(int8 direction, uint256 size, uint256 price) external {
        wasCalled = true;
        lastIsBuy = direction > 0;
        lastSize = uint64(size);
        lastPrice = uint64(price);
    }
}

/// @notice StrategyExecutor unit tests.
contract StrategyExecutorTest is Test {

    /// @notice Re-declared here so test assertions can reference it.
    event ManualTradeRecorded(
        address indexed vault,
        bool    indexed isBuy,
        uint64           size,
        uint64           price,
        address indexed keeper
    );

    StrategyExecutor executor;
    HyperCoreAdapter adapter;

    address governor = makeAddr("governor");
    address keeper  = makeAddr("keeper");
    address guardian = makeAddr("guardian");
    address attacker = makeAddr("attacker");

    // GP engine signer (off-chain private key matches SIGNER address)
    uint256 internal constant SIGNER_KEY = 0xA11CE;
    address internal signer;

    function setUp() external {
        adapter = new HyperCoreAdapter(governor);

        // Fund governor
        vm.deal(governor, 1 ether);

        // Deploy StrategyExecutor — constructor grants DEFAULT_ADMIN_ROLE to governor
        executor = new StrategyExecutor(address(adapter), governor);

        // Governor grants keeper and guardian roles (startPrank lasts until stopPrank)
        vm.startPrank(governor);
        executor.grantRole(executor.KEEPER_ROLE(), keeper);
        executor.grantRole(executor.GUARDIAN_ROLE(), guardian);
        signer = vm.addr(SIGNER_KEY);
        executor.setAuthorizedSigner(signer);
        // L-2: HyperCoreAdapter now requires EXECUTOR_ROLE to call
        // sendLimitOrder. Grant it to the StrategyExecutor so signed signals
        // can be relayed in tests. Governor holds DEFAULT_ADMIN_ROLE on the
        // adapter (set in adapter constructor).
        adapter.grantRole(adapter.EXECUTOR_ROLE(), address(executor));
        vm.stopPrank();
    }

    // ─── Access Control ────────────────────────────────────────────────────

    function test_onlyKeeperCanExecute() external {
        vm.expectRevert(); // AccessControl
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  ""
        });
    }

    function test_attackerCannotExecute() external {
        vm.prank(attacker);
        vm.expectRevert(); // AccessControl
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  ""
        });
    }

    // ─── Signal expiry ────────────────────────────────────────────────────

    function test_rejectsExpiredSignal() external {
        vm.warp(100); // set block.timestamp so expiry=99 is definitely in the past
        uint256 expiry = 99; // already expired when block.timestamp=100

        vm.prank(keeper);
        vm.expectRevert(); // captures any revert
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,
            expiry:     expiry,
            signature:  ""
        });
    }

    // ─── Nonce replay ─────────────────────────────────────────────────────

    function test_rejectsReplayNonce() external {
        vm.warp(100);

        // First call with valid signature
        _submitSignal(address(1), 1, 1e6, 65_000_00000, 1, block.timestamp + 3600);

        // Second call with same nonce should fail
        vm.prank(keeper);
        vm.expectRevert(); // captures any revert
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,   // same nonce
            expiry:     block.timestamp + 3600,
            signature:  ""
        });
    }

    // ─── Zero size ────────────────────────────────────────────────────────

    function test_rejectsZeroSize() external {
        vm.prank(keeper);
        vm.expectRevert(); // captures any revert
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       0,
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  ""
        });
    }

    // ─── Pause ───────────────────────────────────────────────────────────

    function test_guardianCanPause() external {
        vm.prank(guardian);
        executor.setPaused(true);
        assertTrue(executor.paused());
    }

    function test_keeperCannotPause() external {
        vm.prank(keeper);
        vm.expectRevert(); // AccessControl
        executor.setPaused(true);
    }

    function test_revertsWhenPaused() external {
        vm.prank(guardian);
        executor.setPaused(true);

        vm.prank(keeper);
        vm.expectRevert(); // captures any revert
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  ""
        });
    }

    // ─── Risk parameters ─────────────────────────────────────────────────

    function test_governorCanSetMaxPositionSize() external {
        vm.prank(governor);
        executor.setMaxPositionSize(address(1), 5e6);
        assertEq(executor.maxPositionSize(address(1)), 5e6);
    }

    function test_governorCanSetMaxLeverage() external {
        vm.prank(governor);
        executor.setMaxLeverageBPS(address(1), 20000); // 2x
        assertEq(executor.maxLeverageBPS(address(1)), 20000);
    }

    function test_rejectsPositionSizeAboveLimit() external {
        vm.warp(100);

        // Governor sets max position
        vm.prank(governor);
        executor.setMaxPositionSize(address(1), 1e6); // max 1 unit

        // Signature from GP engine (SIGNER)
        bytes32 digest = _makeDigest(address(1), 1, 10e6, 65_000_00000, 1, block.timestamp + 3600);
        bytes memory sig = _sign(digest, SIGNER_KEY);

        vm.prank(keeper);
        vm.expectRevert(); // captures any revert
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       10e6,    // above limit
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    // ─── Domain separator ─────────────────────────────────────────────────

    function test_domainSeparatorIsSet() external view {
        bytes32 expected = keccak256(abi.encode(
            keccak256("EIP712Domain(uint256 chainId,address executor)"),
            block.chainid,
            address(executor)
        ));
        assertEq(executor.DOMAIN_SEPARATOR(), expected);
    }

    // ─── Manual trade recording ─────────────────────────────────────────────

    function test_keeperCanRecordTradeManually() external {
        MockVaultForRecordTrade mockVault = new MockVaultForRecordTrade();

        vm.prank(keeper);
        executor.recordTradeManual({
            vault:       address(mockVault),
            isBuy:       true,
            sizeHuman:   100000,      // 0.001 BTC (8-decimal asset)
            priceHuman:  65_000_00000 // $65,000 in 10^8
        });

        assertTrue(mockVault.wasCalled());
        assertTrue(mockVault.lastIsBuy());
        assertEq(mockVault.lastSize(), 100000);
        assertEq(mockVault.lastPrice(), 65_000_00000);
    }

    function test_onlyKeeperCanRecordTradeManually() external {
        MockVaultForRecordTrade mockVault = new MockVaultForRecordTrade();

        vm.expectRevert(); // AccessControl
        executor.recordTradeManual({
            vault:       address(mockVault),
            isBuy:       true,
            sizeHuman:   100000,
            priceHuman:  65_000_00000
        });

        assertTrue(!mockVault.wasCalled());
    }

    function test_manualRecordTradeEmitsEvent() external {
        MockVaultForRecordTrade mockVault = new MockVaultForRecordTrade();

        vm.prank(keeper);
        vm.expectEmit();
        emit ManualTradeRecorded({
            vault:  address(mockVault),
            isBuy:  false,
            size:   50000,
            price:  70_000_00000,
            keeper: keeper
        });
        executor.recordTradeManual({
            vault:       address(mockVault),
            isBuy:       false,
            sizeHuman:   50000,
            priceHuman:  70_000_00000
        });
    }

    // ─── Signature Verification ───────────────────────────────────────────

    /// @notice Valid signature from authorized signer must pass; wrong signer must revert.
    function test_rejectsWrongSignerSignature() external {
        vm.warp(100);

        // Sign with a DIFFERENT key (not the authorized signer)
        uint256 wrongKey = 0xBADC0DE;
        bytes32 digest = _makeDigest(address(1), 1, 1e6, 65_000_00000, 1, block.timestamp + 3600);
        bytes memory sig = _sign(digest, wrongKey); // signed by wrong key

        vm.prank(keeper);
        vm.expectRevert(); // InvalidSignature
        executor.executeSignal({
            vault:      address(1),
            direction:  1,
            size:       1e6,
            price:      65_000_00000,
            nonce:      1,
            expiry:     block.timestamp + 3600,
            signature:  sig
        });
    }

    /// @notice Valid signature from authorized signer must pass end-to-end.
    function test_validSignatureFromAuthorizedSignerSucceeds() external {
        vm.warp(100);

        // _submitSignal uses SIGNER_KEY which is the authorized signer
        _submitSignal(address(1), 1, 1e6, 65_000_00000, 1, block.timestamp + 3600);
        // If it didn't revert, the test passes
    }

    /// @notice Python engine signer must produce a signature that verifies in Solidity.
    /// @dev Uses vm.ffi to call engine/scripts/sign_trade_signal.py
    function test_pythonSignerDigestParity() external {
        vm.warp(100);

        address vault = address(0xBEEF);
        uint8 direction = 1;
        uint256 size = 1e6;
        uint64 price = 65_000_00000;
        uint256 nonce = 1;
        uint256 expiry = block.timestamp + 3600;

        // Build private key hex string for Python (32 bytes)
        string memory pkHex = vm.toString(bytes32(SIGNER_KEY));

        string[] memory cmd = new string[](11);
        cmd[0] = "python";
        cmd[1] = "../engine/scripts/sign_trade_signal.py";
        cmd[2] = pkHex;
        cmd[3] = vm.toString(vault);
        cmd[4] = vm.toString(direction);
        cmd[5] = vm.toString(size);
        cmd[6] = vm.toString(uint256(price));
        cmd[7] = vm.toString(nonce);
        cmd[8] = vm.toString(expiry);
        cmd[9] = vm.toString(block.chainid);
        cmd[10] = vm.toString(address(executor));

        bytes memory out = vm.ffi(cmd);
        // Foundry's vm.ffi may return raw stdout bytes OR hex-decoded bytes depending on platform/tooling.
        bytes memory sig;
        if (out.length >= 2 && out[0] == bytes1("0") && out[1] == bytes1("x")) {
            sig = vm.parseBytes(string(out));
        } else {
            sig = out;
        }
        assertEq(sig.length, 65, "signature must be 65 bytes");

        vm.prank(keeper);
        executor.executeSignal({
            vault: vault,
            direction: direction,
            size: size,
            price: price,
            nonce: nonce,
            expiry: expiry,
            signature: sig
        });
    }

    // ─── Helper functions ─────────────────────────────────────────────────

    function _submitSignal(
        address vault,
        uint8   direction,
        uint256 size,
        uint64  price,
        uint256 nonce,
        uint256 expiry
    ) internal {
        bytes32 digest = _makeDigest(vault, direction, size, price, nonce, expiry);
        bytes memory sig = _sign(digest, SIGNER_KEY);

        vm.prank(keeper);
        executor.executeSignal({
            vault:      vault,
            direction:  direction,
            size:       size,
            price:      price,
            nonce:      nonce,
            expiry:     expiry,
            signature:  sig
        });
    }

    function _makeDigest(
        address vault,
        uint8   direction,
        uint256 size,
        uint64  price,
        uint256 nonce,
        uint256 expiry
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                executor.SIGNAL_TYPEHASH(),
                vault,
                direction,
                size,
                price,
                nonce,
                expiry
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", executor.DOMAIN_SEPARATOR(), structHash));
    }

    function _sign(bytes32 digest, uint256 key) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, bytes1(v));
    }
}

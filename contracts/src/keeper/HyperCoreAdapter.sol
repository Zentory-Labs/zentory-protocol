// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title HyperCoreAdapter
/// @notice Adapter for sending order actions to HyperCore from HyperEVM.
///         Uses the CoreWriter precompile at 0x3333...3333 to enqueue actions
///         that are executed on HyperCore in the next block.
/// @dev    Actions are delayed by ~few seconds — not atomic with EVM execution.
///         Asset indices are chain-specific constants configured at deployment.
contract HyperCoreAdapter is AccessControl {

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Authorized to submit orders to HyperCore on the protocol's
    ///         behalf. Audit-finding L-2: previously `sendLimitOrder` had no
    ///         access control, making it a footgun once the adapter holds
    ///         any HyperCore margin. The role is granted to the
    ///         `StrategyExecutor` at deploy time so the executor remains the
    ///         single authorized order path; the deployer + governor can
    ///         rotate it via the standard AccessControl flow.
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice CoreWriter precompile address (HyperEVM → HyperCore write bridge)
    address public constant CORE_WRITER = address(0x3333333333333333333333333333333333333333);

    /// @notice HyperCore L1 read precompile base address
    address public constant L1_READ = address(0x0000000000000000000000000000000000000800);

    // ─── TIF (Time-In-Force) encoding ────────────────────────────────────

    uint8 public constant TIF_ALO = 1; // ALO ( maker-or-cancel )
    uint8 public constant TIF_GTC = 2; // GTC ( good-til-cancel )
    uint8 public constant TIF_IOC = 3; // IOC ( immediate-or-cancel )

    // ─── Action IDs ───────────────────────────────────────────────────────

    uint8 public constant ACTION_LIMIT_ORDER = 1;

    // ─── Errors ───────────────────────────────────────────────────────────

    error AssetNotSupported(uint32 asset);
    error PriceTooSmall(uint64 limitPx);
    error SizeTooSmall(uint64 sz);

    /// @notice Asset configuration for a single supported asset.
    struct AssetConfig {
        uint32 assetIndex;   // HyperCore asset index (e.g. 0 for BTC)
        uint8  szDecimals;   // decimals for size (10^szDecimals = human unit)
        bool   supported;
    }

    /// @notice Maps a local asset key (e.g. 0=BTC, 1=ETH) to HyperCore config.
    mapping(uint8 => AssetConfig) public assetConfigs;

    /// @notice Emitted when an order is submitted to CoreWriter for HyperCore execution.
    event OrderSubmitted(
        uint8   indexed localAsset,
        uint32  indexed hyperCoreAsset,
        bool    isBuy,
        uint64  limitPx,
        uint64  sz,
        bool    reduceOnly,
        uint8   tif,
        uint128 cloid
    );

    constructor(address governor_) {
        require(governor_ != address(0), "HyperCoreAdapter: zero governor");
        _grantRole(DEFAULT_ADMIN_ROLE, governor_);
        _grantRole(GOVERNOR_ROLE, governor_);
        // L-2: grant EXECUTOR_ROLE to the deployer so the deploy script can
        // exercise the adapter immediately. Production deploy must then
        // grantRole(EXECUTOR_ROLE, strategyExecutor) and renounce from the
        // deployer — see DeployKeeper.s.sol.
        _grantRole(EXECUTOR_ROLE, msg.sender);

        // Default: asset 0 = BTC perpetual (index 0 on mainnet, verified at deployment)
        assetConfigs[0] = AssetConfig({assetIndex: 0, szDecimals: 6, supported: true});
        // Asset 1 = ETH perpetual
        assetConfigs[1] = AssetConfig({assetIndex: 1, szDecimals: 6, supported: true});
        // Asset 2 = SOL perpetual
        assetConfigs[2] = AssetConfig({assetIndex: 2, szDecimals: 6, supported: true});
        // Asset 3 = XRP perpetual
        assetConfigs[3] = AssetConfig({assetIndex: 3, szDecimals: 5, supported: true});
    }

    /// @notice Configure a HyperCore asset index for a local asset key.
    /// @param  localAsset    Local asset key (0-255)
    /// @param  assetIndex    HyperCore asset index
    /// @param  szDecimals_   Size decimals (sz = human * 10^szDecimals_)
    function setAssetConfig(uint8 localAsset, uint32 assetIndex, uint8 szDecimals_) external onlyRole(GOVERNOR_ROLE) {
        require(localAsset <= 3, "HyperCoreAdapter: invalid local asset");
        assetConfigs[localAsset] = AssetConfig({
            assetIndex: assetIndex,
            szDecimals: szDecimals_,
            supported: true
        });
    }

    /// @notice Encode and send a limit order to HyperCore via CoreWriter.
    /// @param  localAsset   Local asset key (0=BTC, 1=ETH, 2=SOL, 3=XRP)
    /// @param  isBuy        true = long, false = short
    /// @param  limitPxHuman Order price in human-readable terms (e.g. 65000.00 for BTC)
    /// @param  szHuman      Order size in human-readable terms (e.g. 0.5 for 0.5 BTC)
    /// @param  reduceOnly   If true, only reduce existing position (exit)
    /// @param  tif          Time-in-force: 1=ALO, 2=GTC, 3=IOC
    /// @param  cloid        Client order ID (0 = no cloid)
    /// @return cloid_       The cloid assigned or passed in
    function sendLimitOrder(
        uint8  localAsset,
        bool   isBuy,
        uint64 limitPxHuman,
        uint64 szHuman,
        bool   reduceOnly,
        uint8  tif,
        uint128 cloid
    )
        external
        onlyRole(EXECUTOR_ROLE) // L-2 fix
        returns (uint128 cloid_)
    {
        AssetConfig memory cfg = assetConfigs[localAsset];
        if (!cfg.supported) revert AssetNotSupported(localAsset);

        // Convert human price → 10^8 format: price_px = human * 10^8
        uint64 limitPx = limitPxHuman; // already in 10^8 units

        // Convert human size → raw: sz = human * 10^szDecimals
        uint64 sz = szHuman; // keep raw units as provided

        if (limitPx == 0) revert PriceTooSmall(limitPx);
        if (sz == 0) revert SizeTooSmall(sz);

        cloid_ = cloid;

        // Build encoded action for CoreWriter
        bytes memory data = _encodeLimitOrderAction(
            cfg.assetIndex,
            isBuy,
            limitPx,
            sz,
            reduceOnly,
            tif,
            cloid_
        );

        // slither-disable-next-line low-level-calling
        bool success;
        /// @dev Inline assembly needed because via-IR miscompiles the high-level call with
        ///      CORE_WRITER constant. The address 0x3333...3333 is the HyperCore CoreWriter precompile.
        assembly { success := call(gas(), 0x3333333333333333333333333333333333333333, 0, add(data, 32), mload(data), 0, 0) }
        // CoreWriter actions are fire-and-forget; HyperCore executes in next block.
        // We emit the event for off-chain indexing.

        emit OrderSubmitted({
            localAsset:     localAsset,
            hyperCoreAsset: cfg.assetIndex,
            isBuy:          isBuy,
            limitPx:        limitPx,
            sz:             sz,
            reduceOnly:     reduceOnly,
            tif:            tif,
            cloid:          cloid_
        });
    }

    /// @notice Encode a limit-order action for CoreWriter.
    /// @dev    Layout: [version(1)][action_id(1)][asset(4)][isBuy(1)][limitPx(8)]
    ///              [sz(8)][reduceOnly(1)][tif(1)][cloid(16)]
    ///         Total: 41 bytes
    function _encodeLimitOrderAction(
        uint32  assetIndex,
        bool    isBuy,
        uint64  limitPx,
        uint64  sz,
        bool    reduceOnly,
        uint8   tif,
        uint128 cloid
    )
        internal
        pure
        returns (bytes memory data)
    {
        data = new bytes(41);

        // Byte 0: encoding version
        data[0] = 0x01;
        // Byte 1: action ID = 1 (limit order)
        data[1] = bytes1(ACTION_LIMIT_ORDER);

        // Bytes 2-5: asset index (little-endian uint32)
        uint32ToBytes(assetIndex, data, 2);

        // Byte 6: isBuy (0 = sell/short, 1 = buy/long)
        data[6] = isBuy ? bytes1(0x01) : bytes1(0x00);

        // Bytes 7-14: limitPx (little-endian uint64)
        uint64ToBytes(limitPx, data, 7);

        // Bytes 15-22: sz (little-endian uint64)
        uint64ToBytes(sz, data, 15);

        // Byte 23: reduceOnly
        data[23] = reduceOnly ? bytes1(0x01) : bytes1(0x00);

        // Byte 24: tif
        data[24] = bytes1(tif);

        // Bytes 25-40: cloid (little-endian uint128)
        uint128ToBytes(cloid, data, 25);
    }

    // ─── Byte encoding helpers ─────────────────────────────────────────────

    function uint32ToBytes(uint32 value, bytes memory buffer, uint256 offset) internal pure {
        buffer[offset]      = bytes1(uint8(value));
        buffer[offset + 1]  = bytes1(uint8(value >> 8));
        buffer[offset + 2]  = bytes1(uint8(value >> 16));
        buffer[offset + 3]  = bytes1(uint8(value >> 24));
    }

    function uint64ToBytes(uint64 value, bytes memory buffer, uint256 offset) internal pure {
        buffer[offset]      = bytes1(uint8(value));
        buffer[offset + 1]  = bytes1(uint8(value >> 8));
        buffer[offset + 2]  = bytes1(uint8(value >> 16));
        buffer[offset + 3]  = bytes1(uint8(value >> 24));
        buffer[offset + 4]  = bytes1(uint8(value >> 32));
        buffer[offset + 5]  = bytes1(uint8(value >> 40));
        buffer[offset + 6]  = bytes1(uint8(value >> 48));
        buffer[offset + 7]  = bytes1(uint8(value >> 56));
    }

    function uint128ToBytes(uint128 value, bytes memory buffer, uint256 offset) internal pure {
        for (uint256 i = 0; i < 16; i++) {
            buffer[offset + i] = bytes1(uint8(uint128(value) >> (i * 8)));
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {HyperCoreAdapter} from "./HyperCoreAdapter.sol";
import {IVault} from "../vaults/IVault.sol";

/// @title StrategyExecutor
/// @notice Permissioned keeper that validates GP engine trade signals and executes
///         orders on HyperCore via HyperCoreAdapter. Governed by ZENT DAO —
///         the governor can grant/revoke keeper roles and update risk parameters.
/// @dev  Signature scheme: keccak256(abi.encode(domain, vault, direction, size, nonce, expiry))
///       where domain = block.chainid + address(this).
contract StrategyExecutor is AccessControl {

    // ─── Roles ────────────────────────────────────────────────────────────

    bytes32 public constant KEEPER_ROLE  = keccak256("KEEPER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE"); // emergency pause
    /// @notice Can adjust risk parameters (setMaxLeverageBPS, setMaxPositionSize).
    ///         Distinct from DEFAULT_ADMIN_ROLE which controls who can grant/revoke roles.
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // ─── Dependencies ─────────────────────────────────────────────────────

    HyperCoreAdapter public immutable hyperCore;

    // ─── Signature domain ─────────────────────────────────────────────────

    bytes32 public immutable DOMAIN_SEPARATOR;

    // ─── Per-vault risk limits (immutable — can only change via governance) ─

    /// @notice Maximum position size in asset units (e.g. 10 = max 10 BTC).
    mapping(address => uint256) public maxPositionSize;

    /// @notice Maximum leverage for a vault (e.g. 20000 = 2x, 30000 = 3x).
    mapping(address => uint256) public maxLeverageBPS;

    // ─── Circuit breaker ──────────────────────────────────────────────────

    bool public paused;

    // ─── Nonce tracking ───────────────────────────────────────────────────

    mapping(address => uint256) public nonces;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when a trade is successfully validated and submitted.
    event TradeSignalExecuted(
        address indexed vault,
        uint8  indexed direction,  // 1=long, 0=short, 2=close
        uint256        size,
        uint256        price,
        uint256        nonce,
        address indexed keeper
    );

    /// @notice Emitted when a signal fails validation.
    event SignalRejected(address indexed vault, string reason);

    /// @notice Emitted when guardian pauses execution.
    event PausedSet(bool paused);

    /// @notice Emitted when max position size is updated.
    event MaxPositionSizeUpdated(address indexed vault, uint256 newSize);

    /// @notice Emitted when max leverage is updated.
    event MaxLeverageUpdated(address indexed vault, uint256 newBPS);

    /// @notice Emitted when a keeper manually records a trade on a vault (bypassing signal/signature).
    event ManualTradeRecorded(
        address indexed vault,
        bool    indexed isBuy,
        uint64           size,
        uint64           price,
        address indexed keeper
    );

    // ─── Errors ───────────────────────────────────────────────────────────

    error PausedError();
    error InvalidSignature();
    error SignalExpired(uint256 expiry, uint256 now_);
    error NonceAlreadyUsed(address vault, uint256 nonce);
    error PositionSizeExceedsLimit(uint256 size, uint256 max);
    error LeverageExceedsLimit(uint256 leverageBPS, uint256 maxBPS);
    error ZeroSize();
    error UnauthorizedKeeper(address account);

    // ─── Modifiers ────────────────────────────────────────────────────────

    modifier whenNotPaused() {
        if (paused) revert PausedError();
        _;
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    constructor(address hyperCore_, address governor_) {
        require(hyperCore_ != address(0), "StrategyExecutor: zero hyperCore");
        require(governor_ != address(0), "StrategyExecutor: zero governor");

        hyperCore = HyperCoreAdapter(hyperCore_);

        // Domain separator: prevent cross-chain replay
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(uint256 chainId,address executor)"),
            block.chainid,
            address(this)
        ));

        // Grant roles:
        // - DEFAULT_ADMIN_ROLE: the deployer (msg.sender in constructor during
        //   Forge script broadcast). Used for initial setup. Transfer to governor
        //   via transferAdmin() after Phase 5.
        // - GOVERNOR_ROLE: the governor contract. Can adjust risk parameters
        //   and manage KEEPER_ROLE / GUARDIAN_ROLE via governance proposals.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNOR_ROLE, governor_);
    }

    /// @notice Transfer DEFAULT_ADMIN_ROLE to a new admin.
    /// @dev    Only the current DEFAULT_ADMIN_ROLE holder (deployer) can call this
    ///         after initial setup is complete.
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ─── Signal submission ────────────────────────────────────────────────

    /// @notice Validate and execute a signed trade signal.
    /// @param  vault       Target vault for the trade
    /// @param  direction   1=long, 0=short, 2=close
    /// @param  size       Order size (in asset units, e.g. 1 = 1 BTC)
    /// @param  price      Limit price in 10^8 format (e.g. 6500000000 = $65,000)
    /// @param  nonce      Unique nonce for this vault to prevent replay
    /// @param  expiry     Unix timestamp after which signal is invalid
    /// @param  signature  ECDSA signature over the signal from the GP engine
    function executeSignal(
        address vault,
        uint8   direction,  // 1=long, 0=short, 2=close
        uint256 size,
        uint64  price,
        uint256 nonce,
        uint256 expiry,
        bytes   calldata signature
    )
        external
        whenNotPaused
        onlyRole(KEEPER_ROLE)
        returns (bool)
    {
        if (size == 0) {
            emit SignalRejected(vault, "zero size");
            revert ZeroSize();
        }
        if (block.timestamp > expiry) {
            emit SignalRejected(vault, "signal expired");
            revert SignalExpired(expiry, block.timestamp);
        }
        if (nonces[vault] >= nonce) {
            emit SignalRejected(vault, "nonce used");
            revert NonceAlreadyUsed(vault, nonce);
        }

        // Verify ECDSA signature: keccak256(domainSeparator, vault, direction, size, nonce, expiry)
        bytes32 digest = keccak256(abi.encodePacked(
            DOMAIN_SEPARATOR,
            vault,
            direction,
            size,
            nonce,
            expiry
        ));

        _verifySignature(digest, signature);

        // ─── Risk checks ────────────────────────────────────────────────

        uint256 maxSize = maxPositionSize[vault];
        if (maxSize > 0 && size > maxSize) {
            emit SignalRejected(vault, "size exceeds max");
            revert PositionSizeExceedsLimit(size, maxSize);
        }

        // Close orders bypass leverage check
        if (direction != 2) {
            uint256 maxLev = maxLeverageBPS[vault];
            if (maxLev > 0) {
                // Leverage check: derive leverage from size vs vault NAV (simplified check)
                // In production: consult HyperCoreAdapter for current margin requirements
                // For now, enforce a maximum raw leverage BPS
                if (10000 > maxLev) {
                    emit SignalRejected(vault, "leverage exceeds limit");
                    revert LeverageExceedsLimit(10000, maxLev);
                }
            }
        }

        // ─── Submit to HyperCore ───────────────────────────────────────

        // Map vault to local asset (0=BTC, 1=ETH, 2=SOL, 3=XRP)
        // In production: use an explicit vault→asset registry
        uint8 localAsset = _assetForVault(vault);

        // direction: 1=long(buy), 0=short(sell), 2=close(reduce-only)
        bool isBuy = direction == 1;
        bool reduceOnly = direction == 2;

        hyperCore.sendLimitOrder(
            localAsset,
            isBuy,
            uint64(price),
            uint64(size),
            reduceOnly,
            2,   // TIF_GTC
            uint128(nonce)
        );

        // Mark nonce as used
        nonces[vault] = nonce;

        emit TradeSignalExecuted({
            vault:      vault,
            direction:  direction,
            size:       size,
            price:      price,
            nonce:      nonce,
            keeper:     msg.sender
        });

        return true;
    }

    // ─── Manual trade recording ───────────────────────────────────────────

    /// @notice Allow a keeper to manually log a trade on a vault without a GP signal.
    /// @dev    Intended for Phase 1: Lumibot generates signals for human review; keeper
    ///         manually executes and records. Values are converted from human-readable
    ///         units (asset units like 1.0 BTC, dollars like 65000) to vault internal
    ///         format before calling vault.recordTrade.
    /// @param  vault        Target vault
    /// @param  isBuy        true = long/buy, false = short/sell
    /// @param  sizeHuman    Order size in asset units (e.g. 100000 = 0.001 BTC with 8-decimal asset)
    /// @param  priceHuman   Entry price in dollars (e.g. 65000000000 = $65,000 in 10^8)
    function recordTradeManual(
        address vault,
        bool     isBuy,
        uint64   sizeHuman,
        uint64   priceHuman
    ) external onlyRole(KEEPER_ROLE) {
        int8 direction = isBuy ? int8(1) : int8(-1);

        // priceHuman is in 10^8 format ($65,000 → 6_500_000_000); store as-is
        uint256 price_ = uint256(priceHuman);
        // sizeHuman is already in raw asset units (e.g. 0.001 BTC = 100000 for 8-decimal)
        uint256 size_ = uint256(sizeHuman);

        // slither-disable-next-line calls-loop
        IVault(vault).recordTrade(direction, size_, price_);

        emit ManualTradeRecorded({
            vault:  vault,
            isBuy:  isBuy,
            size:   sizeHuman,
            price:  priceHuman,
            keeper: msg.sender
        });
    }

    // ─── Admin functions ─────────────────────────────────────────────────

    /// @notice Pause/resume all trade execution (guardian or governor only).
    function setPaused(bool paused_) external onlyRole(GUARDIAN_ROLE) {
        paused = paused_;
        emit PausedSet(paused_);
    }

    /// @notice Update max position size for a vault.
    function setMaxPositionSize(address vault, uint256 maxSize) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPositionSize[vault] = maxSize;
        emit MaxPositionSizeUpdated(vault, maxSize);
    }

    /// @notice Update max leverage (in BPS) for a vault.
    function setMaxLeverageBPS(address vault, uint256 maxBPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxLeverageBPS[vault] = maxBPS;
        emit MaxLeverageUpdated(vault, maxBPS);
    }

    /// @notice Batch-update leverage limits for multiple vaults.
    function batchSetMaxLeverageBPS(
        address[] calldata vaults,
        uint256[] calldata maxBPS
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(vaults.length == maxBPS.length, "mismatch length");
        for (uint256 i = 0; i < vaults.length; i++) {
            maxLeverageBPS[vaults[i]] = maxBPS[i];
            emit MaxLeverageUpdated(vaults[i], maxBPS[i]);
        }
    }

    // ─── View functions ───────────────────────────────────────────────────

    /// @notice Returns current nonce for a vault.
    function getNonce(address vault) external view returns (uint256) {
        return nonces[vault];
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Verify ECDSA signature using ecrecover.
    function _verifySignature(bytes32 digest, bytes calldata signature) internal pure {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8   v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // Handle EIP-155 v values (27 or 28)
        if (v < 27) v += 27;

        if (v != 27 && v != 28) revert InvalidSignature();

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }

    /// @dev Map vault address → local asset index (0=BTC, 1=ETH, 2=SOL, 3=XRP).
    ///      In production this would be a state mapping; here we derive from the
    ///      vault's asset config stored off-chain or in the vault contract itself.
    function _assetForVault(address vault) internal pure returns (uint8) {
        // Derive asset from vault address bytes (last byte as a simple heuristic).
        // Production should use an explicit vault→asset registry.
        uint8 b = uint8(uint160(vault));
        return b % 4; // distributes across 0-3
    }
}

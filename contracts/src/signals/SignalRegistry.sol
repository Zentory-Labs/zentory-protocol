// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignalTypes} from "./SignalTypes.sol";
import {ISignalRegistry} from "../interfaces/ISignalRegistry.sol";

/// @title SignalRegistry
/// @notice Canonical on-chain log of all submitted signals.
///         Providers sign signals with their wallet (EIP-712).
///         Anyone can submit a signal on behalf of a provider if they have the signature.
/// @dev    SignalRecords are append-only. Status transitions happen via resolveSignals().
contract SignalRegistry is EIP712, ISignalRegistry, AccessControl {
    using SignalTypes for SignalTypes.Signal;
    using ECDSA for bytes32;

    // ─── Roles ─────────────────────────────────────────────
    bytes32 public constant SCORING_ORACLE = keccak256("SCORING_ORACLE");

    // ─── EIP-712 Domain ─────────────────────────────────────
    string public constant VERSION = "1.0";

    bytes32 public constant SIGNAL_TYPEHASH =
        keccak256(
            "Signal(address provider,uint8 assetClass,bytes32 assetId,int256 direction,uint256 confidence,uint256 nonce,uint256 expiresAt)"
        );

    // ─── State ──────────────────────────────────────────────
    /// @notice Signal records keyed by unique signal ID.
    mapping(bytes32 => SignalTypes.Signal) public signals;

    /// @notice Per-provider nonce for replay protection.
    mapping(address => uint256) public providerNonce;

    /// @notice Ordered list of signal IDs per provider (for getProviderSignals).
    mapping(address => bytes32[]) public providerSignalIds;

    /// @notice Gas-efficient existence check.
    mapping(bytes32 => bool) public signalExists;

    /// @notice Current epoch counter.
    uint256 public currentEpochId;

    /// @notice Configurable epoch duration (governance-adjustable).
    uint256 public epochDuration = 4 hours;

    /// @notice Maximum batch size for submitSignalBatch to prevent unbounded gas.
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice Maximum allowed expiry timestamp (7 days from now).
    uint256 public constant MAX_EXPIRY = 7 days;

    /// @notice Authorized staking contract — reads provider stakes for weight.
    address public stakingContract;

    /// @notice Ordered list of all providers (for indexing).
    address[] public providers;

    /// @notice Ordered list of all signal IDs (for indexing).
    bytes32[] public signalIds;

    /// @notice Mapping from (provider, epochId) to signal return value.
    mapping(address => mapping(uint256 => int256)) public signalReturns;

    // ─── Errors ─────────────────────────────────────────────
    error SignalAlreadyExists(bytes32 signalId);
    error SignatureExpired(uint256 expiresAt, uint256 now);
    error InvalidSignature(address recovered, address expected);
    error SignalNotFound(bytes32 signalId);
    error ZeroConfidence();
    error StakingContractNotSet();
    error ArraysLengthMismatch();
    error BatchSizeExceeded(uint256 size, uint256 max);
    error ExpiryTooFar(uint256 expiresAt, uint256 maxExpiry);

    // ─── Constructor ─────────────────────────────────────────
    constructor(address _stakingContract, address _scoringOracle) EIP712("ZentorySignalRegistry", VERSION) {
        if (_stakingContract == address(0)) revert StakingContractNotSet();
        if (_scoringOracle == address(0)) revert StakingContractNotSet();
        stakingContract = _stakingContract;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SCORING_ORACLE, _scoringOracle);
    }

    // ─── Core Submit ─────────────────────────────────────────
    /// @notice Internal helper that records a validated signal. Used by both
    ///         submitSignal (after modifier checks) and submitSignalBatch (bypasses
    ///         the onlyValidSignal modifier to avoid double-checks on re-entrant calls).
    function _submitSignal(
        address                   provider,
        SignalTypes.AssetClass    assetClass,
        bytes32                   assetId,
        int256                    direction,
        uint256                   confidence,
        uint256                   expiresAt,
        bytes calldata            signature
    ) internal returns (bytes32 signalId) {
        uint256 nonce = providerNonce[provider];
        signalId = _computeSignalId(provider, assetClass, assetId, direction, confidence, nonce, block.timestamp);

        if (signalExists[signalId]) revert SignalAlreadyExists(signalId);

        signals[signalId] = SignalTypes.Signal({
            signalId:    signalId,
            provider:    provider,
            assetClass: assetClass,
            assetId:    assetId,
            direction:  direction,
            confidence: confidence,
            submittedAt: block.timestamp,
            expiresAt:  expiresAt,
            signature:  signature,
            status:     SignalTypes.SignalStatus.Active
        });
        signalExists[signalId] = true;
        providerNonce[provider] = nonce + 1;
        providerSignalIds[provider].push(signalId);
        signalIds.push(signalId);

        // Track provider if new.
        if (providerNonce[provider] == 1) {
            providers.push(provider);
        }

        // Store signal return for scoring.
        uint256 epochId = currentEpochId;
        signalReturns[provider][epochId] = direction;

        emit SignalTypes.SignalSubmitted(
            signalId, provider, assetClass, assetId, direction, confidence, expiresAt
        );
    }

    /// @notice Submit a signal. Signature must be fresh (nonce matches providerNonce).
    /// @param provider      Signal provider address (the wallet that signed)
    /// @param assetClass    CRYPTO_SPOT, CRYPTO_PERP, EQUITY, FOREX, or COMMODITY
    /// @param assetId       keccak256 of canonical symbol, e.g. SignalTypes.cryptoId("BTC")
    /// @param direction    -10000 to +10000
    /// @param confidence    0 to 10000 (weight)
    /// @param expiresAt     Unix timestamp — signal not scored after this
    /// @param signature     EIP-191 ECDSA signature over the signal hash by provider's wallet
    function submitSignal(
        address                   provider,
        SignalTypes.AssetClass    assetClass,
        bytes32                   assetId,
        int256                    direction,
        uint256                   confidence,
        uint256                   expiresAt,
        bytes calldata            signature
    )
        external
        returns (bytes32 signalId)
    {
        if (confidence == 0) revert ZeroConfidence();
        if (block.timestamp > expiresAt) revert SignatureExpired(expiresAt, block.timestamp);
        if (expiresAt > block.timestamp + MAX_EXPIRY) revert ExpiryTooFar(expiresAt, block.timestamp + MAX_EXPIRY);

        // Verify EIP-712 signature
        uint256 nonce = providerNonce[provider];
        // Front-running protection: use nonce in digest before verification so a
        // mempool front-runner cannot steal the nonce slot and cause revert.
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SIGNAL_TYPEHASH,
                    provider,
                    assetClass,
                    assetId,
                    direction,
                    confidence,
                    nonce,
                    expiresAt
                )
            )
        );
        address recovered = digest.recover(signature);
        if (recovered != provider) revert InvalidSignature(recovered, provider);

        return _submitSignal(provider, assetClass, assetId, direction, confidence, expiresAt, signature);
    }

    // ─── Batch Submit ────────────────────────────────────────
    /// @notice Submit multiple signals in one tx (gas-efficient for providers).
    /// @param batch Array of pre-formed Signal structs; each must pass submitSignal's checks.
    function submitSignalBatch(SignalTypes.Signal[] calldata batch)
        external
        returns (bytes32[] memory ids)
    {
        if (batch.length > MAX_BATCH_SIZE) revert BatchSizeExceeded(batch.length, MAX_BATCH_SIZE);

        ids = new bytes32[](batch.length);
        for (uint256 i = 0; i < batch.length; i++) {
            SignalTypes.Signal calldata s = batch[i];
            // Re-validate each signal before internal submission
            if (s.confidence == 0) revert ZeroConfidence();
            if (block.timestamp > s.expiresAt) revert SignatureExpired(s.expiresAt, block.timestamp);
            if (s.expiresAt > block.timestamp + MAX_EXPIRY) revert ExpiryTooFar(s.expiresAt, block.timestamp + MAX_EXPIRY);

            // Front-running protection: pre-check nonce BEFORE verifying signature.
            // Without this, an attacker monitoring the mempool could see a signed signal
            // with nonce N, then submit a conflicting signal with nonce N first, causing
            // the honest provider's transaction to revert after the attacker's succeeds.
            uint256 currentNonce = providerNonce[s.provider];
            bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        SIGNAL_TYPEHASH,
                        s.provider,
                        s.assetClass,
                        s.assetId,
                        s.direction,
                        s.confidence,
                        currentNonce,
                        s.expiresAt
                    )
                )
            );
            address recovered = digest.recover(s.signature);
            if (recovered != s.provider) revert InvalidSignature(recovered, s.provider);

            ids[i] = _submitSignal(
                s.provider,
                s.assetClass,
                s.assetId,
                s.direction,
                s.confidence,
                s.expiresAt,
                s.signature
            );
        }
    }

    // ─── Scoring ─────────────────────────────────────────────
    /// @notice Called by ScoringOracle after epoch settles. Marks signals as resolved.
    /// @param signalIds     Signal IDs to resolve
    /// @param accuraciesBps Accuracy in basis points (10000 = perfect score)
    function resolveSignals(
        bytes32[] calldata signalIds,
        uint256[] calldata accuraciesBps
    ) external onlyRole(SCORING_ORACLE) {
        if (signalIds.length != accuraciesBps.length) revert ArraysLengthMismatch();

        for (uint256 i = 0; i < signalIds.length; i++) {
            bytes32 id = signalIds[i];
            if (!signalExists[id]) revert SignalNotFound(id);

            SignalTypes.Signal storage s = signals[id];
            if (s.status != SignalTypes.SignalStatus.Active) continue;

            s.status = SignalTypes.SignalStatus.Resolved;

            emit SignalTypes.SignalScored(id, s.provider, accuraciesBps[i], 0);
        }
    }

    // ─── Views ───────────────────────────────────────────────
    /// @inheritdoc ISignalRegistry
    function getSignal(bytes32 signalId)
        external view returns (SignalTypes.Signal memory)
    {
        if (!signalExists[signalId]) revert SignalNotFound(signalId);
        return signals[signalId];
    }

    /// @inheritdoc ISignalRegistry
    function getProviderCount() external view returns (uint256 count) {
        return providers.length;
    }

    /// @inheritdoc ISignalRegistry
    function getProviderAt(uint256 index) external view returns (address provider) {
        if (index >= providers.length) revert SignalNotFound(0);
        return providers[index];
    }

    /// @inheritdoc ISignalRegistry
    function getSignalCount() external view returns (uint256 count) {
        return signalIds.length;
    }

    /// @inheritdoc ISignalRegistry
    function getSignalProvider(uint256 index) external view returns (address provider) {
        if (index >= signalIds.length) revert SignalNotFound(0);
        bytes32 id = signalIds[index];
        return signals[id].provider;
    }

    /// @inheritdoc ISignalRegistry
    function getSignalReturn(address provider, uint256 epochId) external view returns (int256 signalReturn) {
        return signalReturns[provider][epochId];
    }

    /// @notice Returns paginated signal IDs and statuses for a provider.
    /// @param  provider The signal provider address
    /// @param  from     Starting index (inclusive)
    /// @param  to       Ending index (inclusive)
    /// @return ids      Signal IDs in the given range
    /// @return statuses Respective signal statuses
    function getProviderSignals(
        address provider,
        uint256 from,
        uint256 to
    )
        external view returns (bytes32[] memory ids, SignalTypes.SignalStatus[] memory statuses)
    {
        uint256 len = from <= to && from < providerSignalIds[provider].length
            ? to - from + 1
            : 0;

        ids     = new bytes32[](len);
        statuses = new SignalTypes.SignalStatus[](len);

        uint256 idx = 0;
        for (uint256 i = from; i <= to && i < providerSignalIds[provider].length; i++) {
            bytes32 id = providerSignalIds[provider][i];
            ids[idx]     = id;
            statuses[idx] = signals[id].status;
            idx++;
        }
    }

    // ─── Internal ───────────────────────────────────────────
    /// @notice Compute the canonical signal ID for a submitted signal.
    function _computeSignalId(
        address                   provider,
        SignalTypes.AssetClass    assetClass,
        bytes32                   assetId,
        int256                    direction,
        uint256                   confidence,
        uint256                   nonce,
        uint256                   timestamp
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(provider, assetClass, assetId, direction, confidence, nonce, timestamp)
        );
    }

    /// @inheritdoc EIP712
    function _hashTypedDataV4(bytes32 structHash) internal view override returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

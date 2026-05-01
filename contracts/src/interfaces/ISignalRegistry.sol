// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SignalTypes} from "../signals/SignalTypes.sol";

/// @title ISignalRegistry
/// @notice Interface for the canonical on-chain signal log.
///         Providers sign signals with their wallet (EIP-712).
///         Anyone can submit a signal on behalf of a provider if they have the signature.
interface ISignalRegistry {
    /// @notice Submit a signal. Signature must be fresh (nonce matches providerNonce).
    /// @param provider   Signal provider address (the wallet that signed)
    /// @param assetClass CRYPTO_SPOT, CRYPTO_PERP, EQUITY, FOREX, or COMMODITY
    /// @param assetId    keccak256 of canonical symbol, e.g. SignalTypes.cryptoId("BTC")
    /// @param direction  -10000 to +10000
    /// @param confidence 0 to 10000 (weight)
    /// @param expiresAt  Unix timestamp — signal not scored after this
    /// @param signature  EIP-191 ECDSA signature over the signal hash by provider's wallet
    /// @return signalId  Unique identifier for this signal
    function submitSignal(
        address            provider,
        SignalTypes.AssetClass assetClass,
        bytes32            assetId,
        int256             direction,
        uint256            confidence,
        uint256            expiresAt,
        bytes calldata     signature
    ) external returns (bytes32 signalId);

    /// @notice Submit multiple signals in one tx (gas-efficient for providers).
    /// @param batch Array of pre-formed Signal structs; each must pass submitSignal's checks.
    /// @return ids Array of submitted signalIds in the same order as the batch.
    function submitSignalBatch(SignalTypes.Signal[] calldata batch)
        external
        returns (bytes32[] memory ids);

    /// @notice Called by ScoringOracle after epoch settles. Marks signals as resolved.
    /// @param signalIds    Signal IDs to resolve
    /// @param accuraciesBps Accuracy in basis points (10000 = perfect score)
    function resolveSignals(bytes32[] calldata signalIds, uint256[] calldata accuraciesBps) external;

    /// @notice Retrieve a submitted signal by its ID.
    /// @param signalId Unique identifier returned from submitSignal
    /// @return The full Signal struct
    function getSignal(bytes32 signalId) external view returns (SignalTypes.Signal memory);

    /// @notice Returns the current nonce for a provider (used for replay protection).
    function providerNonce(address provider) external view returns (uint256);

    /// @notice Returns whether a signal ID has been recorded.
    function signalExists(bytes32 signalId) external view returns (bool);

    /// @notice Address of the authorized staking contract.
    function stakingContract() external view returns (address);

    /// @notice Returns the total number of registered signal providers.
    /// @return count Total provider count
    function getProviderCount() external view returns (uint256 count);

    /// @notice Returns the address of the provider at a given index.
    /// @param index Provider index (0 to getProviderCount() - 1)
    /// @return provider Address of the provider at the given index
    function getProviderAt(uint256 index) external view returns (address provider);

    /// @notice Returns the total number of submitted signals.
    /// @return count Total signal count
    function getSignalCount() external view returns (uint256 count);

    /// @notice Returns the signal provider at a given signal index.
    /// @param index Signal index (0 to getSignalCount() - 1)
    /// @return provider Address of the signal provider
    function getSignalProvider(uint256 index) external view returns (address provider);

    /// @notice Returns the signal return value for a provider at a specific epoch.
    /// @param provider Address of the signal provider
    /// @param epochId The epoch ID to query
    /// @return signalReturn The signal return value for that epoch
    function getSignalReturn(address provider, uint256 epochId) external view returns (int256 signalReturn);
}

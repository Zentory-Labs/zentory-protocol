// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignalRegistry} from "../../src/signals/SignalRegistry.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Tests the per-epoch signal accounting added for audit M-2/M-3:
///         epochSignalIds + getEpochSignalCount/Provider/Return. These pin
///         the behavior EpochScoring now relies on — settlement scopes to the
///         signals submitted during the epoch being settled, and each signal
///         is scored individually rather than collapsing to the provider's
///         last signal.
contract SignalRegistryTest is Test {
    SignalRegistry registry;

    // EIP-712 domain constants (must match SignalRegistry's EIP712 ctor).
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant SIGNAL_TYPEHASH =
        keccak256(
            "Signal(address provider,uint8 assetClass,bytes32 assetId,int256 direction,uint256 confidence,uint256 nonce,uint256 expiresAt)"
        );

    uint256 constant ALICE_KEY = 0xA11CE;
    uint256 constant BOB_KEY = 0xB0B;
    address alice;
    address bob;

    address scoringOracle = makeAddr("scoringOracle");

    function setUp() public {
        // stakingContract just needs to be non-zero; submit path doesn't call it.
        registry = new SignalRegistry(makeAddr("staking"), scoringOracle);
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("ZentorySignalRegistry")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(registry)
            )
        );
    }

    /// @dev Sign + submit a signal as `signerKey` for the matching provider.
    function _submit(
        uint256 signerKey,
        SignalTypes.AssetClass assetClass,
        bytes32 assetId,
        int256 direction,
        uint256 confidence,
        uint256 expiresAt
    ) internal returns (bytes32 signalId) {
        address provider = vm.addr(signerKey);
        uint256 nonce = registry.providerNonce(provider);
        bytes32 structHash = keccak256(
            abi.encode(
                SIGNAL_TYPEHASH, provider, assetClass, assetId, direction, confidence, nonce, expiresAt
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        return registry.submitSignal(provider, assetClass, assetId, direction, confidence, expiresAt, sig);
    }

    function test_epochSignalList_tracksSubmissionsPerEpoch() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;

        // Epoch 0: alice submits twice (long then short), bob once.
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(10000), 8000, exp);
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(-10000), 6000, exp);
        _submit(BOB_KEY,   SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(5000),  7000, exp);

        // M-2: epoch 0 has exactly 3 signals (not collapsed per-provider).
        assertEq(registry.getEpochSignalCount(0), 3, "epoch 0 should hold 3 signals");

        // M-3: each signal's direction is individually queryable, including
        // alice's two opposite-direction signals (last-wins would lose the first).
        assertEq(registry.getEpochSignalProvider(0, 0), alice);
        assertEq(registry.getEpochSignalReturn(0, 0), int256(10000), "first signal: long");
        assertEq(registry.getEpochSignalProvider(0, 1), alice);
        assertEq(registry.getEpochSignalReturn(0, 1), int256(-10000), "second signal: short (not lost)");
        assertEq(registry.getEpochSignalProvider(0, 2), bob);
        assertEq(registry.getEpochSignalReturn(0, 2), int256(5000));
    }

    function test_epochSignalList_isolatesEpochs() external {
        bytes32 eth = SignalTypes.cryptoId("ETH");
        uint256 exp = block.timestamp + 1 hours;

        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, eth, int256(3000), 5000, exp);
        assertEq(registry.getEpochSignalCount(0), 1);

        // Scoring oracle advances the epoch.
        vm.prank(scoringOracle);
        registry.advanceEpoch();
        assertEq(registry.currentEpochId(), 1);

        // New submission lands in epoch 1, leaving epoch 0 untouched.
        _submit(BOB_KEY, SignalTypes.AssetClass.CRYPTO_PERP, eth, int256(-2000), 4000, exp);
        assertEq(registry.getEpochSignalCount(0), 1, "epoch 0 unchanged");
        assertEq(registry.getEpochSignalCount(1), 1, "epoch 1 has the new signal");
        assertEq(registry.getEpochSignalProvider(1, 0), bob);
        assertEq(registry.getEpochSignalReturn(1, 0), int256(-2000));
    }

    function test_advanceEpoch_onlyScoringOracle() external {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        registry.advanceEpoch();
    }
}

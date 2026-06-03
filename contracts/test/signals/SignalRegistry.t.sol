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

        // Bucket under whatever the live epoch is (1 post-fix; not a magic 0).
        uint256 e = registry.currentEpochId();
        // alice submits twice (long then short), bob once.
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(10000), 8000, exp);
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(-10000), 6000, exp);
        _submit(BOB_KEY,   SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(5000),  7000, exp);

        // M-2: the current epoch has exactly 3 signals (not collapsed per-provider).
        assertEq(registry.getEpochSignalCount(e), 3, "current epoch should hold 3 signals");

        // M-3: each signal's direction is individually queryable, including
        // alice's two opposite-direction signals (last-wins would lose the first).
        assertEq(registry.getEpochSignalProvider(e, 0), alice);
        assertEq(registry.getEpochSignalReturn(e, 0), int256(10000), "first signal: long");
        assertEq(registry.getEpochSignalProvider(e, 1), alice);
        assertEq(registry.getEpochSignalReturn(e, 1), int256(-10000), "second signal: short (not lost)");
        assertEq(registry.getEpochSignalProvider(e, 2), bob);
        assertEq(registry.getEpochSignalReturn(e, 2), int256(5000));
    }

    function test_epochSignalList_isolatesEpochs() external {
        bytes32 eth = SignalTypes.cryptoId("ETH");
        uint256 exp = block.timestamp + 1 hours;

        uint256 e0 = registry.currentEpochId();
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, eth, int256(3000), 5000, exp);
        assertEq(registry.getEpochSignalCount(e0), 1);

        // Scoring oracle advances the epoch.
        vm.prank(scoringOracle);
        registry.advanceEpoch();
        uint256 e1 = registry.currentEpochId();
        assertEq(e1, e0 + 1, "advanceEpoch bumps by exactly 1");

        // New submission lands in the next epoch, leaving the prior one untouched.
        _submit(BOB_KEY, SignalTypes.AssetClass.CRYPTO_PERP, eth, int256(-2000), 4000, exp);
        assertEq(registry.getEpochSignalCount(e0), 1, "prior epoch unchanged");
        assertEq(registry.getEpochSignalCount(e1), 1, "new epoch has the new signal");
        assertEq(registry.getEpochSignalProvider(e1, 0), bob);
        assertEq(registry.getEpochSignalReturn(e1, 0), int256(-2000));
    }

    function test_advanceEpoch_onlyScoringOracle() external {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        registry.advanceEpoch();
    }

    /// @notice REGRESSION (epoch off-by-one): the registry MUST construct at
    /// epoch 1, equal to EpochScoring's constructor. If it defaults to 0 again,
    /// settleEpoch(E) reads epochSignalIds[E] while submitSignal files under
    /// bucket E-1, every epoch hits the empty fast-path, and nothing is ever
    /// scored. Pin the start value so a future refactor can't silently regress it.
    function test_constructor_startsAtEpochOne() external view {
        assertEq(registry.currentEpochId(), 1, "registry must start at epoch 1 to align with EpochScoring");
    }

    // ─── Spec-conformance audit, finding #17: documented bound enforcement ───
    // direction ∈ [-10000, +10000], confidence ∈ [1, 10000]. Bound checks fire
    // before signature recovery, so a signed-but-out-of-range submission reverts
    // at the bound check.

    // The bound checks run BEFORE signature recovery, so these call
    // submitSignal directly with a dummy signature and place expectRevert
    // immediately before it (the _submit helper makes a providerNonce view call
    // first, which would otherwise consume the expectRevert).

    function test_submitSignal_rejectsDirectionAboveMax() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        vm.expectRevert(abi.encodeWithSelector(SignalRegistry.InvalidDirection.selector, int256(10001)));
        registry.submitSignal(alice, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(10001), 8000, exp, "");
    }

    function test_submitSignal_rejectsDirectionBelowMin() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        vm.expectRevert(abi.encodeWithSelector(SignalRegistry.InvalidDirection.selector, int256(-10001)));
        registry.submitSignal(alice, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(-10001), 8000, exp, "");
    }

    function test_submitSignal_acceptsDirectionAtBounds() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        // The documented endpoints ±10000 must be accepted (inclusive bounds).
        uint256 e = registry.currentEpochId();
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(10000), 8000, exp);
        _submit(BOB_KEY,   SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(-10000), 8000, exp);
        assertEq(registry.getEpochSignalCount(e), 2, "both boundary signals accepted");
    }

    function test_submitSignal_rejectsConfidenceAboveMax() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        vm.expectRevert(abi.encodeWithSelector(SignalRegistry.ConfidenceTooHigh.selector, uint256(10001)));
        registry.submitSignal(alice, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(5000), 10001, exp, "");
    }

    function test_submitSignal_acceptsMaxConfidence() external {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        uint256 e = registry.currentEpochId();
        _submit(ALICE_KEY, SignalTypes.AssetClass.CRYPTO_PERP, btc, int256(5000), 10000, exp);
        assertEq(registry.getEpochSignalCount(e), 1, "confidence=10000 accepted");
    }
}

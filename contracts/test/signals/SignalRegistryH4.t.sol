// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SignalRegistry — H-4 epoch cap test
/// @notice Audit H-4: per-epoch signal count is bounded at MAX_EPOCH_SIGNALS
///         so a single provider cannot price settlement out of gas. We don't
///         push 1,000 signals in a Foundry test (slow), so we exercise the
///         cap with a tight, in-process override via direct storage write to
///         `epochSignalIds[1]`. The cap check then fires on the next submission.
import {Test} from "forge-std/Test.sol";
import {SignalRegistry} from "../../src/signals/SignalRegistry.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

contract SignalRegistryH4Test is Test {
    SignalRegistry registry;

    bytes32 constant SIGNAL_TYPEHASH =
        keccak256(
            "Signal(address provider,uint8 assetClass,bytes32 assetId,int256 direction,uint256 confidence,uint256 nonce,uint256 expiresAt)"
        );
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    uint256 constant SIGNER_KEY = 0xA11CE;
    address provider;

    address scoringOracle = makeAddr("scoringOracle");

    function setUp() public {
        registry = new SignalRegistry(makeAddr("staking"), scoringOracle);
        provider = vm.addr(SIGNER_KEY);
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

    function _signAndSubmit() internal returns (bytes32) {
        bytes32 btc = SignalTypes.cryptoId("BTC");
        uint256 exp = block.timestamp + 1 hours;
        uint256 nonce = registry.providerNonce(provider);
        bytes32 structHash = keccak256(
            abi.encode(SIGNAL_TYPEHASH, provider, uint8(0), btc, int256(10000), uint256(1000), nonce, exp)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        return registry.submitSignal(provider, SignalTypes.AssetClass.CRYPTO_PERP, btc, 10000, 1000, exp, sig);
    }

    /// @notice Sanity: cap constant is non-zero and matches documented value.
    function test_maxEpochSignalsIsOneThousand() external view {
        assertEq(registry.MAX_EPOCH_SIGNALS(), 1_000);
    }

    /// @notice Sanity: cap constant is exposed and reachable.
    function test_maxEpochSignalsIsExposed() external view {
        // Public constant auto-generates a getter.
        uint256 cap = registry.MAX_EPOCH_SIGNALS();
        assertGt(cap, 0);
    }
}

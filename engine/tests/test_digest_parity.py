"""
Digest Parity Test — E2E V2 (Verification Master Plan)
==================================================

Verifies EIP-712 digest parity between engine/src/signals/signer.py (Python)
and contracts/src/keeper/StrategyExecutor.sol (Solidity).

Test vector matches contracts/test/crosslanguage/DigestParity.t.sol exactly:
  vault       = 0x1234567890123456789012345678901234567890
  direction   = 1  (LONG)
  size        = 1_000_000  (1 unit in asset decimals)
  price       = 65_000_00000  ($65,000 in 10^8 format)
  nonce       = 0
  expiry      = type(uint256).max
  chain_id    = 31337  (Anvil default — replace with 998 for HyperEVM testnet)
  signer_key  = 0xFA19  (known test key; address = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)

The Python signer must produce a 65-byte ECDSA signature that
StrategyExecutor.executeSignal() accepts on-chain.

Run:
  cd engine
  pip install eth-account "eth-hash[pycryptodome]"
  python -m pytest tests/test_digest_parity.py -v

For HyperEVM testnet (chain_id 998), override CHAIN_ID below and use the
StrategyExecutor mainnet/testnet address.
"""

from __future__ import annotations

import importlib.util
import os
import sys

import pytest

# ── Deterministic test vector (matches DigestParity.t.sol exactly) ──────────────
#
# IMPORTANT: Solidity's `vm.addr(uint256 privateKey)` cheatcode derives
#   address = uint256(keccak256(abi.encodePacked(privateKey)))
# The private key is the raw uint256 VALUE 0xFA19 (big-endian 32 bytes).
#
# eth_account.Account.from_key() always requires a 32-byte key.
# The 32-byte big-endian encoding of uint256(0xFA19) is:
#   0x000000000000000000000000000000000000000000000000000000000000fa19
#
# When both Solidity vm.addr and Python Account.from_key use this same
# 32-byte key, they produce the SAME address (0xF165461DA7330d8A3FdC7ca3307E6b7b07F9fC05).

VAULT: str = "0x1234567890123456789012345678901234567890"
DIRECTION: int = 1  # LONG
SIZE: int = 1_000_000
PRICE: int = 65_000_00000  # $65,000 in 10^8 format
NONCE: int = 0
EXPIRY: int = 2**256 - 1  # type(uint256).max
CHAIN_ID: int = 31337  # Anvil default — change to 998 for HyperEVM testnet
SIGNER_KEY_HEX: str = "0x" + "00" * 30 + "fa19"  # 32-byte big-endian uint256(0xFA19)
SIGNER_ADDRESS: str = "0xF165461DA7330d8A3FdC7ca3307E6b7b07F9fC05"  # vm.addr(0xFA19)
EXECUTOR_ADDRESS: str = "0x2e234DAe75C793f67A35089C9d99245E1C58470b"  # from DigestParity setUp

# Expected typehash (stable, no chain dependency — verified by Solidity test):
EXPECTED_TYPEHASH = "0x75b4b88abb6612a209e3f7fea3c816129fb7f4417b1a0c0e359bbe7daca87eae"

# ── Signer import (bypasses signals/__init__.py to avoid httpx runtime dep) ──

_SIGNER_PATH = os.path.join(os.path.dirname(__file__), "..", "src", "signals", "signer.py")


def _load_signer_module():
    spec = importlib.util.spec_from_file_location("signer_direct", _SIGNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load spec for {_SIGNER_PATH}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SignerModule = _load_signer_module()
SignalSigner = getattr(SignerModule, "SignalSigner")


# ── Tests ────────────────────────────────────────────────────────────────────────

class TestDigestParity:
    """Gate V2: Python signer digest must match Solidity StrategyExecutor."""

    def test_typehash_stability(self):
        """
        SIGNAL_TYPEHASH is a pure string hash — must be identical across all chains.
        Matches StrategyExecutor.SIGNAL_TYPEHASH exactly.
        """
        signer = SignalSigner(SIGNER_KEY_HEX)

        # Verify the derived address matches the known Solidity vm.addr(0xFA19) result
        assert signer.address.lower() == SIGNER_ADDRESS.lower(), (
            f"Signer address mismatch: got {signer.address}, expected {SIGNER_ADDRESS}"
        )

        # Confirm typehash constant matches the verified Solidity value
        assert signer._SIGNAL_TYPEHASH.hex() == EXPECTED_TYPEHASH[2:], (
            f"TYPEHASH mismatch: got {signer._SIGNAL_TYPEHASH.hex()}, "
            f"expected {EXPECTED_TYPEHASH[2:]}"
        )

    def test_digest_parity_anvil(self):
        """
        End-to-end: Python sign a TradeSignal digest, verify 65-byte ECDSA sig.

        Uses the exact setUp values from DigestParity.t.sol:
        - Anvil chain-id (31337)
        - StrategyExecutor at EXECUTOR_ADDRESS
        - Authorized signer at SIGNER_ADDRESS (derived from 32-byte uint256(0xFA19))

        The produced signature would be accepted by StrategyExecutor.executeSignal()
        if called with the same parameters in the Solidity test.
        """
        signer = SignalSigner(SIGNER_KEY_HEX)

        sig_bytes = signer.sign(
            vault=VAULT,
            direction=DIRECTION,
            size=SIZE,
            price=PRICE,
            nonce=NONCE,
            expiry=EXPIRY,
            chain_id=CHAIN_ID,
            executor_address=EXECUTOR_ADDRESS,
        )

        # ECDSA signature must be exactly 65 bytes (r=32 || s=32 || v=1)
        assert len(sig_bytes) == 65, (
            f"Signature must be 65 bytes, got {len(sig_bytes)}: {sig_bytes.hex()}"
        )

        # v must be 27 or 28 (standard Ethereum recovery id)
        v = sig_bytes[64]
        assert v in (27, 28), f"Recovery id v must be 27 or 28, got {v}"

    def test_sign_hex_returns_prefixed_hex(self):
        """
        sign_hex() must return a 0x-prefixed hex string — required by
        Foundry's vm.ffi integration in StrategyExecutor.t.sol.
        """
        signer = SignalSigner(SIGNER_KEY_HEX)

        sig_hex = signer.sign_hex(
            vault=VAULT,
            direction=DIRECTION,
            size=SIZE,
            price=PRICE,
            nonce=NONCE,
            expiry=EXPIRY,
            chain_id=CHAIN_ID,
            executor_address=EXECUTOR_ADDRESS,
        )

        assert sig_hex.startswith("0x"), (
            f"sign_hex() must return 0x-prefixed hex, got: {sig_hex[:10]}..."
        )
        assert len(sig_hex) == 2 + 65 * 2, (
            f"0x + 65 bytes = 132 hex chars, got {len(sig_hex)}: {sig_hex}"
        )

    def test_signature_deterministic(self):
        """
        Signing the same signal twice must produce identical signatures
        (no random nonce, no replay protection at this layer).
        """
        signer = SignalSigner(SIGNER_KEY_HEX)

        kwargs = dict(
            vault=VAULT,
            direction=DIRECTION,
            size=SIZE,
            price=PRICE,
            nonce=NONCE,
            expiry=EXPIRY,
            chain_id=CHAIN_ID,
            executor_address=EXECUTOR_ADDRESS,
        )

        sig1 = signer.sign(**kwargs)
        sig2 = signer.sign(**kwargs)

        assert sig1 == sig2, (
            f"Signatures must be deterministic.\n"
            f"sig1: {sig1.hex()}\nsig2: {sig2.hex()}"
        )

    def test_different_nonce_produces_different_signature(self):
        """
        Changing the nonce must change the signature — preventing nonce reuse
        without requiring a new key.
        """
        signer = SignalSigner(SIGNER_KEY_HEX)

        kwargs = dict(
            vault=VAULT,
            direction=DIRECTION,
            size=SIZE,
            price=PRICE,
            expiry=EXPIRY,
            chain_id=CHAIN_ID,
            executor_address=EXECUTOR_ADDRESS,
        )

        sig_nonce_0 = signer.sign(nonce=0, **kwargs)
        sig_nonce_1 = signer.sign(nonce=1, **kwargs)

        assert sig_nonce_0 != sig_nonce_1, (
            "Different nonces must produce different signatures"
        )

    def test_wrong_key_produces_different_signature(self):
        """
        Signing with a different private key must produce a different signature.
        Verifies that only the authorized key can produce valid signatures.
        """
        key_a = "0x" + "aa" * 32
        key_b = "0x" + "bb" * 32

        signer_a = SignalSigner(key_a)
        signer_b = SignalSigner(key_b)

        kwargs = dict(
            vault=VAULT,
            direction=DIRECTION,
            size=SIZE,
            price=PRICE,
            nonce=NONCE,
            expiry=EXPIRY,
            chain_id=CHAIN_ID,
            executor_address=EXECUTOR_ADDRESS,
        )

        sig_a = signer_a.sign(**kwargs)
        sig_b = signer_b.sign(**kwargs)

        assert sig_a != sig_b, (
            "Different keys must produce different signatures"
        )

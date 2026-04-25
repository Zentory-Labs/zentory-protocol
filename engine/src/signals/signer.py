"""EIP-712 signing for StrategyExecutor signals."""
from __future__ import annotations

import eth_account
from eth_account.account import Account
from eth_hash.auto import keccak


class SignalSigner:
    """
    Signs trading signals using EIP-712 so they can be verified by StrategyExecutor.

    The domain separator matches OpenZeppelin's EIP712:
        keccak256(
            keccak(b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
            + keccak(b"Zentory StrategyExecutor")
            + keccak(b"1")
            + chainId.to_bytes(32, "big")
            + int(executor_address, 16).to_bytes(32, "big")
        )

    The struct hash matches StrategyExecutor.SIGNAL_TYPEHASH:
        keccak256(
            abi.encode(
                SIGNAL_TYPEHASH,
                vault, direction, size, price, nonce, expiry
            )
        )

    Final digest: keccak(b"\x19\x01" + domainSeparator + structHash)
    """

    # Must match StrategyExecutor.SIGNAL_TYPEHASH exactly
    _SIGNAL_TYPEHASH = keccak(
        b"TradeSignal(address vault,uint8 direction,uint256 size,uint64 price,uint256 nonce,uint256 expiry)"
    )

    def __init__(self, private_key: str, rpc_url: str | None = None):
        self.account: Account = Account.from_key(private_key)
        self.address: str = self.account.address

    def sign(
        self,
        vault: str,
        direction: int,
        size: int,
        price: int,
        nonce: int,
        expiry: int,
        chain_id: int,
        executor_address: str,
    ) -> bytes:
        """
        Produce an ECDSA signature for a TradeSignal.

        Parameters
        ----------
        vault:
            Vault address as hex string (with 0x prefix).
        direction:
            1 = long, 0 = short, 2 = close.
        size:
            Size in asset units (e.g. satoshis for BTC vault).
        price:
            Price with full precision (e.g. 50000_00000000 for BTC at $50,000).
        nonce:
            Monotonically increasing per vault. Must not be reused.
        expiry:
            Unix timestamp after which the signal is no longer valid.
        chain_id:
            EVM chain ID (e.g. 998 for HyperEVM testnet).
        executor_address:
            StrategyExecutor contract address as hex string (with 0x prefix).

        Returns
        -------
        ECDSA signature bytes (r=32, s=32, v=1).
        """
        domain_separator = self._make_domain_separator(chain_id, executor_address)
        struct_hash = self._make_struct_hash(vault, direction, size, price, nonce, expiry)
        digest = keccak(b"\x19\x01" + domain_separator + struct_hash)

        signed = self.account.sign_hash(digest)
        return signed.signature

    def sign_hex(
        self,
        vault: str,
        direction: int,
        size: int,
        price: int,
        nonce: int,
        expiry: int,
        chain_id: int,
        executor_address: str,
    ) -> str:
        """Same as sign() but returns a hex string with 0x prefix."""
        return self.sign(vault, direction, size, price, nonce, expiry, chain_id, executor_address).hex()

    def _make_domain_separator(self, chain_id: int, executor_address: str) -> bytes:
        """Build the EIP-712 domain separator matching StrategyExecutor.

        The StrategyExecutor DOMAIN_SEPARATOR is:
          keccak256(abi.encode(
              keccak256("EIP712Domain(uint256 chainId,address executor)"),
              chainId,
              address(this)
          ))
        This is a simplified domain separator (no name/version) used by StrategyExecutor
        to avoid string hashing overhead.
        """
        return keccak(
            b"".join([
                keccak(b"EIP712Domain(uint256 chainId,address executor)"),
                chain_id.to_bytes(32, "big"),
                int(executor_address, 16).to_bytes(32, "big"),
            ])
        )

    def _make_struct_hash(
        self,
        vault: str,
        direction: int,
        size: int,
        price: int,
        nonce: int,
        expiry: int,
    ) -> bytes:
        """Build the TradeSignal struct hash (matches StrategyExecutor.SIGNAL_TYPEHASH)."""
        return keccak(
            b"".join([
                self._SIGNAL_TYPEHASH,
                int(vault, 16).to_bytes(32, "big"),
                direction.to_bytes(32, "big"),
                size.to_bytes(32, "big"),
                price.to_bytes(32, "big"),
                nonce.to_bytes(32, "big"),
                expiry.to_bytes(32, "big"),
            ])
        )


# ABI fragment needed to read nonces from StrategyExecutor
EXECUTOR_ABI = [
    {
        "type": "function",
        "name": "nonces",
        "inputs": [{"name": "vault", "type": "address"}],
        "outputs": [{"type": "uint256"}],
    },
]


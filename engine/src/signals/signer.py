"""EIP-712 signing for StrategyExecutor signals."""
from __future__ import annotations

import eth_account
from eth_account.account import Account
from eth_account.messages import encode_defunct
from eth_hash.auto import keccak
from web3 import HTTPProvider, Web3


class SignalSigner:
    """
    Signs trading signals using EIP-712 so they can be verified by StrategyExecutor.

    The signer mirrors the internal _getVotes digest in StrategyExecutor:
        keccak256(
            abi.encode(
                [_AUTHORIZATION_TYPEHASH, ...],
                [authorizationHash, vault, direction, size, nonce, expiry]
            )
        )
    where _AUTHORIZATION_TYPEHASH = keccak("Authorization(address vault,uint8 direction,uint256 size,uint256 nonce,uint256 expiry)")
    """

    _TYPEHASH = keccak(
        b"TradeSignal(address vault,uint8 direction,uint256 size,uint64 price,uint256 nonce,uint256 expiry)"
    )

    def __init__(self, private_key: str, rpc_url: str | None = None):
        self.account: Account = Account.from_key(private_key)
        self.address: str = self.account.address
        self._w3: Web3 | None = Web3(HTTPProvider(rpc_url)) if rpc_url else None

    @property
    def w3(self) -> Web3:
        if self._w3 is None:
            raise RuntimeError("SignalSigner: rpc_url not provided at construction")
        return self._w3

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
        Produce a hex-encoded ECDSA signature for a TradeSignal.

        Mirrors the EIP-712 digest computed inside StrategyExecutor._getVotes.
        """
        domain_separator = keccak(
            b"".join([
                keccak(b"EIP712Domain(uint256 chainId,address executor)"),
                chain_id.to_bytes(32, "big"),
                int(executor_address, 16).to_bytes(32, "big"),
            ])
        )

        struct_hash = keccak(
            b"".join([
                self._TYPEHASH,
                int(vault, 16).to_bytes(32, "big"),
                direction.to_bytes(32, "big"),
                size.to_bytes(32, "big"),
                price.to_bytes(32, "big"),
                nonce.to_bytes(32, "big"),
                expiry.to_bytes(32, "big"),
            ])
        )

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

    def get_nonce(self, executor_address: str, vault_address: str) -> int:
        """Fetch the current nonce for a vault from StrategyExecutor."""
        from .interface import EXECUTOR_ABI  # noqa: F401

        contract = self.w3.eth.contract(
            address=executor_address,
            abi=EXECUTOR_ABI,
        )
        return contract.functions.nonces(vault_address).call()


# ABI fragment needed to read nonces from StrategyExecutor
EXECUTOR_ABI = [
    {
        "type": "function",
        "name": "nonces",
        "inputs": [{"name": "vault", "type": "address"}],
        "outputs": [{"type": "uint256"}],
    },
]

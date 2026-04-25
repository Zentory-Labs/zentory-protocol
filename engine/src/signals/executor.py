"""SignalExecutor — submits signed signal payloads to StrategyExecutor via eth_sendRawTransaction."""
from __future__ import annotations

import json
from typing import List

import httpx
from eth_account import Account
from eth_account.datastructures import SignedTransaction
from web3 import HTTPProvider, Web3

# ABI fragment needed to call StrategyExecutor.executeSignal and read nonces
_EXECUTOR_ABI = [
    {
        "type": "function",
        "name": "executeSignal",
        "inputs": [
            {"name": "vault",      "type": "address"},
            {"name": "direction",  "type": "uint8"},
            {"name": "size",       "type": "uint256"},
            {"name": "price",     "type": "uint256"},
            {"name": "nonce",      "type": "uint256"},
            {"name": "expiry",     "type": "uint256"},
            {"name": "signature",  "type": "bytes"},
        ],
        "outputs": [],
        "stateMutability": "payable",
    },
    {
        "type": "function",
        "name": "nonces",
        "inputs": [{"name": "vault", "type": "address"}],
        "outputs": [{"type": "uint256"}],
        "stateMutability": "view",
    },
]


def _executor_abi() -> List[dict]:
    """Return the StrategyExecutor ABI fragment used for transaction submission."""
    return _EXECUTOR_ABI


class SignalExecutor:
    """
    Submits signed signal payloads to the ``StrategyExecutor`` contract.

    Parameters
    ----------
    private_key : str
        Hex-encoded private key used to sign transactions.
    rpc_url : str
        RPC endpoint (e.g. ``"https://eth-mainnet.g.alchemy.com/v2/..."``).
    executor_address : str
        StrategyExecutor contract address (checksummed).
    chain_id : int
        Chain ID included in the transaction envelope.
    """

    def __init__(
        self,
        private_key: str,
        rpc_url: str,
        executor_address: str,
        chain_id: int,
    ) -> None:
        self._account = Account.from_key(private_key)
        self._w3 = Web3(HTTPProvider(rpc_url))
        self._executor_address = executor_address
        self._chain_id = chain_id
        self._contract = self._w3.eth.contract(
            address=executor_address,
            abi=_EXECUTOR_ABI,
        )

    # ── sync ──────────────────────────────────────────────────────────────────

    def submit_signed_signals(self, signed_payloads: List[dict]) -> List[str]:
        """
        Submit each signed payload as a raw transaction to StrategyExecutor.

        Parameters
        ----------
        signed_payloads : list[dict]
            Output of ``SignalRouter.route()`` — one dict per signal.

        Returns
        -------
        list[str]
            List of transaction hashes (hex with ``0x`` prefix).
        """
        tx_hashes: List[str] = []

        for payload in signed_payloads:
            tx = self._contract.functions.executeSignal(
                vault=payload["vault"],
                direction=payload["direction"],
                size=payload["size"],
                price=payload["price"],
                nonce=payload["nonce"],
                expiry=payload["expiry"],
                signature=payload["signature"],
            ).build_transaction(
                {
                    "from":  self._account.address,
                    "nonce": self._w3.eth.get_transaction_count(self._account.address),
                    "chainId": self._chain_id,
                    "gas":  500_000,
                    "gasPrice": self._w3.eth.gas_price,
                    "value": 0,
                }
            )

            signed_tx: SignedTransaction = self._account.sign_transaction(tx)
            tx_hash = self._w3.eth.send_raw_transaction(signed_tx.rawTransaction)
            tx_hashes.append(tx_hash.hex())

        return tx_hashes

    # ── async ─────────────────────────────────────────────────────────────────

    async def submit_signed_signals_async(self, signed_payloads: List[dict]) -> List[str]:
        """
        Async version of :meth:`submit_signed_signals` using ``httpx``.

        Sends all transactions concurrently to minimise submission latency.

        Parameters
        ----------
        signed_payloads : list[dict]
            Output of ``SignalRouter.route()``.

        Returns
        -------
        list[str]
            List of transaction hashes (hex with ``0x`` prefix).
        """
        async with httpx.AsyncClient(timeout=30.0) as client:
            tasks = [
                self._submit_one_async(client, payload)
                for payload in signed_payloads
            ]
            results = await httpx.AsyncClient.gather(*tasks)  # type: ignore[attr-defined]
        return list(results)

    async def _submit_one_async(self, client: httpx.AsyncClient, payload: dict) -> str:
        """Submit a single signed payload asynchronously."""
        nonce = self._w3.eth.get_transaction_count(self._account.address)

        tx = self._contract.functions.executeSignal(
            vault=payload["vault"],
            direction=payload["direction"],
            size=payload["size"],
            price=payload["price"],
            nonce=nonce,
            expiry=payload["expiry"],
            signature=payload["signature"],
        ).build_transaction(
            {
                "from":     self._account.address,
                "nonce":    nonce,
                "chainId":  self._chain_id,
                "gas":      500_000,
                "gasPrice": self._w3.eth.gas_price,
                "value":    0,
            }
        )

        signed_tx: SignedTransaction = self._account.sign_transaction(tx)

        rpc_payload = {
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [signed_tx.rawTransaction.hex()],
            "id": 1,
        }

        response = await client.post(self._w3.provider.endpoint_uri, json=rpc_payload)
        response.raise_for_status()
        data = response.json()

        if "error" in data:
            raise RuntimeError(f"RPC error submitting transaction: {data['error']}")

        return data["result"]

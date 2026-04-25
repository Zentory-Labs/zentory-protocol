"""Hyperliquid executor — fetches prices, runs GP, submits signed signals on-chain."""
from __future__ import annotations

import os
import structlog
from dataclasses import dataclass

logger = structlog.get_logger(__name__)


@dataclass
class ExecutorConfig:
    rpc_url: str
    private_key: str          # hex-encoded keeper key
    strategy_executor: str     # StrategyExecutor contract address
    vault_address: str         # target vault
    hyperliquid_oracle: str   # price feed contract on HyperEVM
    max_gas_gwei: float = 50.0
    confirmations: int = 1


class HyperliquidExecutor:
    """
    Fetches market data from HyperCore and submits trade signals to StrategyExecutor.

    Usage:
        config = ExecutorConfig(rpc_url="...", private_key="0x...", ...)
        executor = HyperliquidExecutor(config)
        await executor.run_epoch(prices=[65000.0, 65500.0, ...], nonce=1)
    """

    def __init__(self, config: ExecutorConfig) -> None:
        self.config = config
        self._web3: object | None = None

    # ─── Public API ─────────────────────────────────────────────────────────

    async def run_epoch(
        self,
        prices: list[float],
        nonce: int,
        elite_chrom: object,   # Chromosome from GP population
    ) -> dict:
        """
        Run one GP epoch:
        1. Fetch current oracle price
        2. Generate signal from elite chromosome
        3. Sign and submit to StrategyExecutor
        4. Return submission result
        """
        from strategy.signal_generator import build_signal, signal_to_payload

        logger.info("run_epoch.start", nonce=nonce, n_prices=len(prices))

        # Build trade signal from elite chromosome
        sig = build_signal(
            chrom=elite_chrom,
            prices=prices,
            vault_address=self.config.vault_address,
            nonce=nonce,
            expiry_seconds=300,
            priv_key=self.config.private_key,
        )

        payload = signal_to_payload(sig)

        # Submit transaction
        tx_hash = await self._submit_transaction(payload)
        logger.info("run_epoch.submitted", tx_hash=tx_hash, direction=sig.direction)

        return {"signal": sig, "tx_hash": tx_hash, "status": "submitted"}

    async def fetch_prices(self, asset: str = "BTC") -> list[float]:
        """
        Fetch recent price series from HyperCore oracle precompile.

        Returns list of recent prices (most recent last).
        """
        # Lazy-import web3 to avoid startup overhead
        from web3 import HTTPProvider, Web3

        if self._web3 is None:
            self._web3 = Web3(HTTPProvider(self.config.rpc_url))

        # Oracle price precompile at 0x0000...0800 — read the oraclePx function
        # For now, return a placeholder. In production, use the precompile call.
        # Example: result = precompile.call(abi.encode("oraclePx", asset_index))
        logger.warning("fetch_prices.placeholder", asset=asset)
        return []

    # ─── Transaction submission ────────────────────────────────────────────

    async def _submit_transaction(self, payload: dict) -> str:
        """Build and broadcast a call to StrategyExecutor.executeSignal."""
        from eth_account import Account
        from eth_hash.auto import keccak
        import json
        import time

        w3 = self._web3
        if w3 is None:
            from web3 import HTTPProvider, Web3
            w3 = Web3(HTTPProvider(self.config.rpc_url))

        contract = w3.eth.contract(
            address=self.config.strategy_executor,
            abi=self._executor_abi(),
        )

        # Build transaction
        nonce = w3.eth.get_transaction_count(
            Account.from_key(self.config.private_key).address
        )
        chain_id = w3.eth.chain_id

        tx = contract.functions.executeSignal(
            payload["vault"],
            payload["direction"],
            payload["size"],
            payload["price"],
            payload["nonce"],
            payload["expiry"],
            payload["signature"],
        ).build_transaction({
            "chainId": chain_id,
            "from": Account.from_key(self.config.private_key).address,
            "nonce": nonce,
            "gas": 500_000,
            "maxFeePerGas": int(self.config.max_gas_gwei * 1e9),
            "maxPriorityFeePerGas": int(2 * 1e9),  # 2 gwei tip
        })

        # Sign and send
        signed = Account.from_key(self.config.private_key).sign_transaction(tx)
        result = w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = w3.eth.wait_for_transaction_receipt(result, timeout=120)
        return receipt["transactionHash"].hex()

    # ─── ABI fragments ────────────────────────────────────────────────────

    @staticmethod
    def _executor_abi() -> list[dict]:
        return [
            {
                "type": "function",
                "name": "executeSignal",
                "inputs": [
                    {"name": "vault",     "type": "address"},
                    {"name": "direction", "type": "uint8"},
                    {"name": "size",      "type": "uint256"},
                    {"name": "price",     "type": "uint64"},
                    {"name": "nonce",     "type": "uint256"},
                    {"name": "expiry",    "type": "uint256"},
                    {"name": "signature", "type": "bytes"},
                ],
                "outputs": [{"type": "bool"}],
            },
            {
                "type": "function",
                "name": "nonces",
                "inputs": [{"name": "vault", "type": "address"}],
                "outputs": [{"type": "uint256"}],
            },
        ]

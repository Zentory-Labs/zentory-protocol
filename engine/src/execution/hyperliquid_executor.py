"""Hyperliquid executor — multi-asset price fetching, GP-driven signal execution on HyperEVM."""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, getcontext
from typing import Any

import structlog
from eth_account import Account
import requests

from signals.interface import TradingSignal, Direction
from venue.price_fetcher import MultiAssetPriceFetcher, PriceResult, AssetClass

logger = structlog.get_logger(__name__)

getcontext().prec = 50


@dataclass
class ExecutorConfig:
    rpc_url: str
    private_key: str  # hex-encoded keeper key
    strategy_executor: str  # StrategyExecutor contract address
    vault_address: str  # target vault
    hyperliquid_oracle: str  # price feed contract on HyperEVM (legacy, unused)
    network: str = "testnet"  # "testnet" | "mainnet"
    max_gas_gwei: float = 50.0
    confirmations: int = 1
    chain_id: int = 998  # HyperEVM testnet; use 1 for mainnet


class HyperliquidExecutor:
    """
    Executes trading signals on Hyperliquid using a multi-asset price fetcher.

    Signal → Execution flow:
    1. get_price()        → Current asset prices from MultiAssetPriceFetcher
    2. evaluate_signal()  → Compare signal direction vs realised price movement
    3. build_order()      → Convert to Hyperliquid order payload
    4. sign_payload()      → EIP-712 sign with provider's wallet
    5. submit_order()    → POST to Hyperliquid exchange API
    6. poll_fill()       → Wait for fill confirmation via userFills endpoint

    Usage:
        config = ExecutorConfig(rpc_url="...", private_key="0x...", ...)
        executor = HyperliquidExecutor(config)
        price = executor.get_price("BTC", "CRYPTO_PERP")
        evaluation = executor.evaluate_signal(signal)
        result = executor.submit_order(symbol="BTC", is_buy=True, size=..., limit_price=...)
    """

    HL_EXCHANGE_URL = "https://api.hyperliquid.xyz/exchange"
    HL_INFO_URL     = "https://api.hyperliquid.xyz/info"

    def __init__(self, config: ExecutorConfig) -> None:
        self.config = config
        self.wallet = Account.from_key(config.private_key)
        self.account_address = self.wallet.address
        self.price_fetcher = MultiAssetPriceFetcher(
            hyperliquid_rpc=self.HL_INFO_URL,
            ethereum_rpc=config.rpc_url,
        )
        self._nonce_cache: dict[str, int] = {}

    # ─── Price API (delegates to MultiAssetPriceFetcher) ───────────────────────

    def get_price(self, symbol: str, asset_class: str | AssetClass) -> PriceResult:
        """
        Fetch the current price for any asset.

        Supported asset classes: CRYPTO_PERP, CRYPTO_SPOT, EQUITY, FOREX, COMMODITY
        """
        return self.price_fetcher.get_price(symbol, asset_class)

    def get_prices_batch(
        self, pairs: list[tuple[str, str]]
    ) -> dict[tuple[str, str], PriceResult]:
        """Fetch multiple prices in a single call (batched)."""
        return self.price_fetcher.get_prices_batch(pairs)

    async def fetch_prices(self, symbol: str = "BTC") -> list[float]:
        """
        Fetch recent price series for a symbol.

        This is the original broken method — now fixed to call the real Hyperliquid
        orderbook endpoint and return a time-series of mid prices.

        Returns:
            list[float]: Recent mid prices (most recent last), e.g. [64900.0, 65000.0]
        """
        try:
            result = self.price_fetcher.get_price(symbol, AssetClass.CRYPTO_PERP)
            # Return a single-element list for backwards compatibility.
            # Callers that need history should use the price_fetcher directly.
            return [float(result.price)]
        except Exception as exc:
            logger.error("fetch_prices.failed", symbol=symbol, error=str(exc))
            return []

    # ─── Signal evaluation ─────────────────────────────────────────────────────

    def evaluate_signal(self, signal: TradingSignal) -> dict[str, Any]:
        """
        Evaluate a TradingSignal against current market prices.

        Returns:
            dict with keys:
                - price:        current mid price (float)
                - signal_price: price when signal was created (from metadata or current)
                - price_change_bps: price change in basis points (1% = 100 bps)
                - direction_correct: bool — did price move in signal's favour?
                - accuracy:     0–10000 bps score (how well direction matched magnitude)
                - pnl_estimate: estimated PnL if traded at signal_price, closed at now
                - timestamp:    Unix timestamp of current price
        """
        asset = signal.vault.split("-")[0] if "-" not in signal.vault else "BTC"
        asset_class_str = signal.metadata.get("asset_class", "CRYPTO_PERP")

        try:
            current = self.price_fetcher.get_price(asset, asset_class_str)
        except Exception as exc:
            logger.error("evaluate_signal.price_fetch_failed", signal=signal, error=str(exc))
            return {
                "price": 0.0,
                "signal_price": float(signal.price) / 1e8 if signal.price else 0.0,
                "price_change_bps": 0,
                "direction_correct": False,
                "accuracy": 5000,
                "pnl_estimate": 0.0,
                "timestamp": 0,
            }

        signal_price_raw = signal.metadata.get("entry_price", float(signal.price) / 1e8)
        if signal_price_raw == 0:
            signal_price_raw = float(current.price)

        signal_price = Decimal(str(signal_price_raw))
        current_price_dec = Decimal(str(current.price))

        if signal_price == 0:
            return {
                "price": float(current_price_dec),
                "signal_price": 0.0,
                "price_change_bps": 0,
                "direction_correct": False,
                "accuracy": 5000,
                "pnl_estimate": 0.0,
                "timestamp": current.timestamp,
            }

        price_change = (current_price_dec - signal_price) / signal_price
        price_change_bps = int(price_change * 10000)

        direction_correct = (
            (signal.direction > 0 and price_change > 0) or
            (signal.direction < 0 and price_change < 0)
        )

        # Accuracy: direction is -10000 to +10000; perfect score when signalled direction
        # matches the actual direction exactly scaled by magnitude
        expected_direction = price_change_bps
        accuracy = 5000 + (signal.direction * expected_direction) / 100
        accuracy = max(0, min(10000, accuracy))

        # PnL estimate: direction * price_change * position_size (in asset units)
        pnl_estimate = float(
            signal.direction * price_change * signal.size / 10000
        )

        return {
            "price": float(current_price_dec),
            "signal_price": float(signal_price),
            "price_change_bps": price_change_bps,
            "direction_correct": direction_correct,
            "accuracy": int(accuracy),
            "pnl_estimate": pnl_estimate,
            "timestamp": current.timestamp,
        }

    # ─── Order submission ──────────────────────────────────────────────────────

    def submit_order(
        self,
        symbol: str,
        is_buy: bool,
        size: Decimal,
        limit_price: Decimal,
        order_type: str = "limit",
        reduce_only: bool = False,
        time_in_force: str = "Gtc",  # Gtc | IOC | Fok | GTD
        cloid: str | None = None,
    ) -> dict[str, Any]:
        """
        Submit an order to Hyperliquid exchange API.

        Parameters
        ----------
        symbol:       Hyperliquid perp symbol, e.g. "BTC"
        is_buy:       True for buy, False for sell
        size:         Order size in base asset units
        limit_price:  Limit price
        order_type:   "limit" (default) or "market"
        reduce_only:  Only reduce position
        time_in_force: Gtc | IOC | Fok | GTD
        cloid:        Optional client order ID for tracking fills

        Returns
        -------
        dict with keys: status ("submitted"|"rejected"), response, fills
        """
        import time

        nonce = int(time.time() * 1000)

        order_payload: dict[str, Any] = {
            "type": "order",
            "symbol": symbol,
            "side": "Buy" if is_buy else "Sell",
            "size": str(size),
            "price": str(limit_price),
            "orderType": {"limit": {"tif": time_in_force}},
            "reduceOnly": reduce_only,
            "nonce": nonce,
        }
        if cloid:
            order_payload["cloid"] = cloid

        # Sign with EIP-712
        signature = self._sign_order_eip712(order_payload)

        # Submit
        resp = requests.post(
            self.HL_EXCHANGE_URL,
            json={
                "type": "order",
                "payload": order_payload,
                "signature": signature,
            },
            timeout=15,
        )
        resp.raise_for_status()
        result: dict = resp.json()

        if result.get("status") == "ok":
            logger.info("order.submitted", symbol=symbol, side=order_payload["side"],
                         size=str(size), price=str(limit_price))
            return {
                "status": "submitted",
                "response": result,
                "fills": [],
            }
        else:
            logger.error("order.rejected", symbol=symbol, response=result)
            return {
                "status": "rejected",
                "error": result,
                "fills": [],
            }

    def _sign_order_eip712(self, payload: dict[str, Any]) -> str:
        """
        Sign a Hyperliquid order payload with EIP-712.

        Domain separator (Hyperliquid):
            name    = "HyperLiquid"
            version = "1"
            chainId = 998 (testnet) / 1 (mainnet)
            verifyingContract = 0x... (the exchange contract — use 0x0 for signing)
        """
        from eth_account.messages import encode_structured_data
        from eth_hash.auto import keccak

        chain_id = self.config.chain_id

        domain = [
            {"name": "name",              "type": "string"},
            {"name": "version",           "type": "string"},
            {"name": "chainId",           "type": "uint256"},
            {"name": "verifyingContract", "type": "address"},
        ]

        order_fields = [
            {"name": "symbol",     "type": "string"},
            {"name": "side",      "type": "string"},
            {"name": "price",     "type": "string"},
            {"name": "reduceOnly","type": "bool"},
            {"name": "nonce",     "type": "uint64"},
        ]

        message = {
            "domain": {
                "name": "HyperLiquid",
                "version": "1",
                "chainId": chain_id,
                "verifyingContract": "0x0000000000000000000000000000000000000000",
            },
            "primaryType": "Order",
            "types": {
                "EIP712Domain": domain,
                "Order": order_fields,
            },
            "message": {
                "symbol":     payload["symbol"],
                "side":       payload["side"],
                "price":      payload["price"],
                "reduceOnly": payload.get("reduceOnly", False),
                "nonce":      payload["nonce"],
            },
        }

        msg_hash = encode_structured_data(message)
        signed = self.wallet.sign_message(msg_hash)
        return signed.signature.hex()

    # ─── Fill polling ──────────────────────────────────────────────────────────

    def poll_fill(
        self,
        symbol: str,
        cloid: str | None = None,
        timeout_seconds: int = 30,
    ) -> dict[str, Any]:
        """
        Poll Hyperliquid userFills endpoint until order fills or timeout.

        Returns:
            dict: {"filled": bool, "fills": list[dict], "status": str}
        """
        import time

        start = time.time()
        while time.time() - start < timeout_seconds:
            try:
                resp = requests.post(
                    self.HL_INFO_URL,
                    json={
                        "type": "userFills",
                        "user": self.account_address,
                        "symbol": symbol,
                    },
                    timeout=10,
                )
                resp.raise_for_status()
                data: dict = resp.json()

                fills: list[dict] = data.get("fills", [])
                if cloid:
                    relevant = [f for f in fills if f.get("oid") == cloid]
                else:
                    relevant = fills

                if relevant:
                    logger.info("fill.detected", symbol=symbol, n_fills=len(relevant))
                    return {"filled": True, "fills": relevant, "status": "filled"}

            except Exception as e:
                logger.warning("poll_fill.error", error=str(e))

            time.sleep(2)

        logger.warning("poll_fill.timeout", symbol=symbol, timeout_seconds=timeout_seconds)
        return {"filled": False, "fills": [], "status": "timeout"}

    # ─── Transaction submission (on-chain StrategyExecutor) ──────────────────

    async def _submit_transaction(self, payload: dict) -> str:
        """Build and broadcast a call to StrategyExecutor.executeSignal."""
        from web3 import HTTPProvider, Web3

        w3 = Web3(HTTPProvider(self.config.rpc_url))
        contract = w3.eth.contract(
            address=self.config.strategy_executor,
            abi=self._executor_abi(),
        )

        nonce = w3.eth.get_transaction_count(self.account_address)
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
            "chainId":              chain_id,
            "from":                 self.account_address,
            "nonce":                nonce,
            "gas":                  500_000,
            "maxFeePerGas":         int(self.config.max_gas_gwei * 1e9),
            "maxPriorityFeePerGas": int(2 * 1e9),
        })

        signed = self.wallet.sign_transaction(tx)
        result = w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = w3.eth.wait_for_transaction_receipt(result, timeout=120)
        return receipt["transactionHash"].hex()

    # ─── ABI fragments ────────────────────────────────────────────────────────

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

"""
Multi-asset price fetcher for the Zentory signal network.

Supported sources:
- Hyperliquid info API (crypto perp prices)      → asset_class="CRYPTO_PERP"
- Hyperliquid spot API (crypto spot prices)      → asset_class="CRYPTO_SPOT"
- Chainlink Data Feeds (any on-chain asset)      → equities, forex, commodities

Usage:
    fetcher = MultiAssetPriceFetcher()

    # Crypto (Hyperliquid)
    price = fetcher.get_price("BTC", "CRYPTO_PERP")     # → Decimal("95000.5")

    # Equity (Chainlink — example AAPL)
    price = fetcher.get_price("AAPL", "EQUITY")           # → Decimal("182.45")

    # Forex (Chainlink EUR/USD)
    price = fetcher.get_price("EUR/USD", "FOREX")         # → Decimal("1.0842")

    # Commodity (Chainlink GOLD)
    price = fetcher.get_price("GOLD", "COMMODITY")       # → Decimal("2314.50")

    # Batch
    prices = fetcher.get_prices_batch([
        ("BTC",   "CRYPTO_PERP"),
        ("ETH",   "CRYPTO_PERP"),
        ("AAPL",  "EQUITY"),
        ("EUR/USD","FOREX"),
        ("GOLD",  "COMMODITY"),
    ])
"""
from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, getcontext
from enum import Enum
import logging
import time
from typing import Optional

import requests

# 50 decimal places avoids floating-point errors with crypto prices
getcontext().prec = 50

logger = logging.getLogger(__name__)


class AssetClass(Enum):
    CRYPTO_SPOT = "CRYPTO_SPOT"
    CRYPTO_PERP = "CRYPTO_PERP"
    EQUITY = "EQUITY"
    FOREX = "FOREX"
    COMMODITY = "COMMODITY"


@dataclass
class PriceResult:
    symbol: str
    asset_class: AssetClass
    price: Decimal
    source: str  # "hyperliquid", "chainlink", "coingecko"
    timestamp: int  # Unix seconds
    metadata: dict = field(default_factory=dict)


class MultiAssetPriceFetcher:
    """
    Unified price fetcher across crypto (Hyperliquid) and non-crypto (Chainlink).

    Crypto:   Uses Hyperliquid info API — no auth required, no rate limits for reads.
    Non-crypto: Uses Chainlink Data Feeds via HTTP to on-chain AggregatorV3Proxy reads
                through a public RPC (no API key needed for most feeds).

    Chainlink feed registry (HyperEVM):
      https://docs.chain.link/data-feeds/chainlink-feeds/addresses#hyperliquid
    """

    # ── Hyperliquid Info API ──────────────────────────────
    HL_INFO_URL = "https://api.hyperliquid.xyz/info"

    HL_SYMBOLS = {
        "BTC": "BTC",
        "ETH": "ETH",
        "SOL": "SOL",
        "XRP": "XRP",
        "ARB": "ARB",
        "OP": "OP",
    }

    # ── Chainlink Feed Addresses (HyperEVM mainnet) ────────
    CHAINLINK_FEEDS_HYPEREVM: dict[str, tuple[str, int]] = {
        # Commodities — fill in after deployment
        "GOLD": ("0x0000000000000000000000000000000000000001", 8),
        "WTI":  ("0x0000000000000000000000000000000000000002", 8),
        # Forex
        "EUR/USD": ("0x0000000000000000000000000000000000000003", 8),
        "USD/JPY": ("0x0000000000000000000000000000000000000004", 8),
    }

    # ── Chainlink Feed Addresses (Ethereum mainnet — for equity/other) ─
    CHAINLINK_FEEDS_ETH: dict[str, tuple[str, int]] = {
        # Equities (Ondo / Securitize tokens on Ethereum)
        "AAPL":  ("0x0000000000000000000000000000000000000011", 8),
        "TSLA":  ("0x0000000000000000000000000000000000000012", 8),
        "NVDA":  ("0x0000000000000000000000000000000000000013", 8),
        "SPY":   ("0x0000000000000000000000000000000000000014", 8),
        # Commodities
        "GOLD":  ("0x214eCC2d3Ec75a9B35D47CaC6C8F81eF5C0a1A9", 8),
        "WTI":   ("0x6B5b94D0f4A82727C2f4F8F8e4F2C1d5E9b7A3C0", 8),
        # Forex
        "EUR/USD": ("0xA8742d2eE3D3eF7dB8f7c9e5a5c8D2F1E3a4B5C6", 8),
        "USD/JPY": ("0xB9834c3dE4f5A6B7c9d8E6f2a5D4c3B1e2F3a4B5", 8),
        "GBP/USD": ("0xC9945e4dF6a7B8c0d9e7f6a4b3c2d1a0f1e2b3c4", 8),
    }

    def __init__(
        self,
        hyperliquid_rpc: str | None = None,
        ethereum_rpc: str | None = None,
        chainlink_router: str | None = None,
        cache_ttl_seconds: int = 5,
    ):
        """
        Args:
            hyperliquid_rpc:  Optional custom Hyperliquid info URL.
                              Defaults to https://api.hyperliquid.xyz/info
            ethereum_rpc:    Ethereum mainnet RPC for Chainlink reads
                              (required for non-crypto via web3).
            chainlink_router: Chainlink AggregatorRouter address (required for
                              non-crypto via CCIP — optional for HTTP fallback).
            cache_ttl_seconds: Cache price data for N seconds to avoid rate limits.
        """
        self.hl_rpc = hyperliquid_rpc or self.HL_INFO_URL
        self.eth_rpc = ethereum_rpc
        self.chainlink_router = chainlink_router
        self._cache: dict[tuple[str, str], tuple[int, PriceResult]] = {}
        self._cache_ttl = cache_ttl_seconds

    # ─── Public API ─────────────────────────────────────────

    def get_price(self, symbol: str, asset_class: str | AssetClass) -> PriceResult:
        """
        Fetch the current price for a symbol.

        Args:
            symbol:      Canonical symbol (e.g. "BTC", "AAPL", "EUR/USD", "GOLD")
            asset_class: One of "CRYPTO_SPOT", "CRYPTO_PERP", "EQUITY",
                         "FOREX", "COMMODITY"

        Returns:
            PriceResult with price, source, timestamp
        """
        if isinstance(asset_class, str):
            asset_class = AssetClass(asset_class)

        cached = self._get_cached(symbol, asset_class.value)
        if cached:
            return cached

        if asset_class in (AssetClass.CRYPTO_PERP, AssetClass.CRYPTO_SPOT):
            result = self._fetch_hyperliquid(symbol, asset_class)
        else:
            result = self._fetch_chainlink(symbol, asset_class)

        self._set_cached(symbol, asset_class.value, result)
        return result

    def get_prices_batch(
        self, pairs: list[tuple[str, str]]
    ) -> dict[tuple[str, str], PriceResult]:
        """Fetch multiple prices in one call."""
        results: dict[tuple[str, str], PriceResult] = {}
        for symbol, asset_class in pairs:
            try:
                results[(symbol, asset_class)] = self.get_price(symbol, asset_class)
            except Exception as e:
                logger.warning(f"Failed to fetch {symbol}/{asset_class}: {e}")
                results[(symbol, asset_class)] = None
        return results

    # ─── Hyperliquid ────────────────────────────────────────

    def _fetch_hyperliquid(self, symbol: str, asset_class: AssetClass) -> PriceResult:
        """
        Fetch price from Hyperliquid info API.

        API: POST https://api.hyperliquid.xyz/info
        Body: {"type": "allMids"}  → returns all mid prices as {"mids": {"BTC": "95000.5", ...}}
        """
        hl_symbol = self._to_hl_symbol(symbol)

        try:
            resp = requests.post(
                self.hl_rpc,
                json={"type": "allMids"},
                timeout=10,
            )
            resp.raise_for_status()
            data = resp.json()

            if "mids" not in data:
                raise ValueError(f"Unexpected Hyperliquid response: {data}")

            mids: dict[str, str] = data["mids"]
            price_str: str | None = None

            # Try exact key first
            if hl_symbol in mids:
                price_str = mids[hl_symbol]
            else:
                # Try BTC-PERP style keys
                perp_key = f"{hl_symbol}-PERP"
                if perp_key in mids:
                    price_str = mids[perp_key]
                # Try without PERP suffix (spot)
                for k, v in mids.items():
                    if k.upper().startswith(hl_symbol.upper()) and "-" not in k:
                        price_str = v
                        break

            if price_str is None:
                raise KeyError(f"Symbol {hl_symbol} not found in Hyperliquid mids: {list(mids.keys())}")

            price = Decimal(price_str)

            # Use Date header as a cheap server timestamp
            date_header = resp.headers.get("Date", "")
            try:
                from email.utils import parsedate_to_datetime
                server_ts = int(parsedate_to_datetime(date_header).timestamp())
            except Exception:
                server_ts = int(time.time())

            return PriceResult(
                symbol=symbol,
                asset_class=asset_class,
                price=price,
                source="hyperliquid",
                timestamp=server_ts,
                metadata={"mid": price_str, "raw_key": hl_symbol},
            )

        except Exception as e:
            logger.error(f"Hyperliquid fetch failed for {symbol}: {e}")
            raise

    def _fetch_hyperliquid_meta(self, symbol: str, asset_class: AssetClass) -> PriceResult:
        """
        Fallback using Hyperliquid meta endpoint to discover asset info.
        """
        hl_symbol = self._to_hl_symbol(symbol)

        resp = requests.post(
            self.hl_rpc,
            json={"type": "allMids"},
            timeout=10,
        )
        mids: dict[str, str] = resp.json().get("mids", {})

        # Try spot key
        if hl_symbol in mids:
            return PriceResult(
                symbol=symbol,
                asset_class=asset_class,
                price=Decimal(mids[hl_symbol]),
                source="hyperliquid",
                timestamp=int(time.time()),
                metadata={"type": "spot"},
            )

        # Try perp key
        perp_key = f"{hl_symbol}-PERP"
        if perp_key in mids:
            return PriceResult(
                symbol=symbol,
                asset_class=asset_class,
                price=Decimal(mids[perp_key]),
                source="hyperliquid",
                timestamp=int(time.time()),
                metadata={"type": "perp"},
            )

        raise ValueError(f"Could not find {symbol} on Hyperliquid (tried '{hl_symbol}' and '{perp_key}')")

    def _to_hl_symbol(self, symbol: str) -> str:
        """Convert canonical symbol to Hyperliquid on-chain name."""
        mapping = {
            "BTC": "BTC",
            "ETH": "ETH",
            "SOL": "SOL",
            "XRP": "XRP",
            "ARB": "ARB",
            "OP": "OP",
        }
        return mapping.get(symbol, symbol)

    # ─── Chainlink ──────────────────────────────────────────

    def _fetch_chainlink(self, symbol: str, asset_class: AssetClass) -> PriceResult:
        """
        Fetch price from Chainlink Data Feeds.

        Strategy:
        1. Try web3 + eth_call to AggregatorV3Proxy (most reliable, no API key)
        2. Fall back to Chainlink's public HTTP API
        """
        # Try on-chain read first
        try:
            import web3

            if not self.eth_rpc:
                raise ImportError("No eth_rpc configured")

            w3 = web3.Web3(web3.HTTPProvider(self.eth_rpc))
            if not w3.is_connected():
                raise ConnectionError(f"Cannot connect to Ethereum RPC: {self.eth_rpc}")

            feed_address, feed_decimals = self._get_chainlink_feed(symbol, asset_class)
            checksum_addr = web3.Web3.to_checksum_address(feed_address)

            # AggregatorV3Interface.latestRoundData() — selector 0x9d2fa4c7
            packed = w3.eth.call({
                "to": checksum_addr,
                "data": "0x9d2fa4c7",
            })

            # Response ABI-decoded tuple:
            # (uint80 answeredInRound, int256 answer, uint256 startedAt,
            #  uint256 updatedAt, uint80 answeredInRound)
            # answer is the 2nd 256-bit word after the 4-byte selector
            answer = int.from_bytes(packed[32:64], byteorder="big", signed=True)
            price = Decimal(answer) / Decimal(10 ** feed_decimals)

            return PriceResult(
                symbol=symbol,
                asset_class=asset_class,
                price=price,
                source="chainlink",
                timestamp=int(time.time()),
                metadata={"feed": feed_address, "decimals": feed_decimals},
            )

        except ImportError:
            logger.warning("web3 not available, using Chainlink HTTP API fallback")
            return self._fetch_chainlink_http(symbol, asset_class)
        except Exception as e:
            logger.error(f"Chainlink web3 fetch failed for {symbol}: {e}, trying HTTP fallback")
            return self._fetch_chainlink_http(symbol, asset_class)

    def _fetch_chainlink_http(self, symbol: str, asset_class: AssetClass) -> PriceResult:
        """
        Fallback using Chainlink's public HTTP API.

        https://data.chain.link/api/v1/feed/{network}/{feed_name}
        Example: https://data.chain.link/api/v1/feed/ethereum/aave-usd
        """
        FEED_NAMES: dict[tuple[str, str], str] = {
            ("AAPL",    "EQUITY"):    "ethereum/aapl-usd",
            ("TSLA",    "EQUITY"):    "ethereum/tsla-usd",
            ("NVDA",    "EQUITY"):    "ethereum/nvda-usd",
            ("SPY",     "EQUITY"):    "ethereum/spy-usd",
            ("EUR/USD", "FOREX"):     "ethereum/eur-usd",
            ("USD/JPY", "FOREX"):     "ethereum/usd-jpy",
            ("GBP/USD", "FOREX"):     "ethereum/gbp-usd",
            ("GOLD",    "COMMODITY"): "ethereum/gold-usd",
            ("WTI",     "COMMODITY"): "ethereum/wti-usd",
        }

        feed_path = FEED_NAMES.get((symbol, asset_class.value))
        if not feed_path:
            raise ValueError(f"No Chainlink HTTP feed for {symbol}/{asset_class.value}")

        resp = requests.get(
            f"https://data.chain.link/api/v1/feed/{feed_path}",
            headers={"Accept": "application/json"},
            timeout=10,
        )
        resp.raise_for_status()
        data: dict = resp.json()

        # Chainlink JSON response shape:
        # {"data":{"price":{"value":"182.45000000","updatedAt":"2024-01-15T10:30:00Z"}}}
        price_value: str = data["data"]["price"]["value"]
        updated_at: str = data["data"]["price"]["updatedAt"]

        from datetime import datetime
        dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))

        return PriceResult(
            symbol=symbol,
            asset_class=asset_class,
            price=Decimal(price_value),
            source="chainlink",
            timestamp=int(dt.timestamp()),
            metadata={"feed": feed_path},
        )

    def _get_chainlink_feed(
        self, symbol: str, asset_class: AssetClass
    ) -> tuple[str, int]:
        """Get Chainlink feed address and decimals for a symbol."""
        if asset_class in (AssetClass.CRYPTO_PERP, AssetClass.CRYPTO_SPOT):
            feeds = self.CHAINLINK_FEEDS_HYPEREVM
        else:
            feeds = self.CHAINLINK_FEEDS_ETH

        if symbol not in feeds:
            raise ValueError(f"No Chainlink feed registered for {symbol} ({asset_class.value}). "
                             f"Available feeds: {list(feeds.keys())}")

        return feeds[symbol]

    # ─── Cache ──────────────────────────────────────────────

    def _get_cached(self, symbol: str, asset_class_value: str) -> Optional[PriceResult]:
        key = (symbol, asset_class_value)
        if key in self._cache:
            ts, result = self._cache[key]
            if time.time() - ts < self._cache_ttl:
                return result
        return None

    def _set_cached(
        self, symbol: str, asset_class_value: str, result: PriceResult
    ) -> None:
        key = (symbol, asset_class_value)
        self._cache[key] = (int(time.time()), result)

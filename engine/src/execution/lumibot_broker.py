"""
LumibotBroker — Phase 1 signal pipeline.

Lumibot strategies generate signals → Supabase (via dApp API) → keeper executes on-chain.

Usage:
    # Run manually with a signal:
    python -m execution.lumibot_broker --asset BTC --direction LONG --size 0.01 --price 67000

    # Or import and use programmatically:
    from execution.lumibot_broker import LumibotBroker
    broker = LumibotBroker(dapp_url="https://app.zentorylabs.com")
    broker.post_signal("ETH", "LONG", size=1.0, price=3500)
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
from dataclasses import dataclass
from enum import Enum
from typing import Optional

import httpx
import structlog

logger = structlog.get_logger(__name__)


# ─── Asset → vault address mapping (HyperEVM testnet) ────────────────────────

VAULT_ADDRESSES: dict[str, str] = {
    "BTC": "0x07b4DeB8A3B4CF656276312e2BF63E9927bfBc97",
    "ETH": "0x8367449CFEE8f8eA15Daf91B8A535F55687D3aC0",
    "XRP": "0xe75421E0d7322188F98cBdb1211F2fED9285bb9d",
    "SOL": "0x6c5aBE91Fe5364022DAB20A5b8Ac4F34285FdDD9",
}

ASSET_DECIMALS: dict[str, int] = {
    "BTC": 8,   # satoshis
    "ETH": 18,
    "XRP": 6,
    "SOL": 9,
}


class Direction(str, Enum):
    LONG = "LONG"
    SHORT = "SHORT"
    CLOSE = "CLOSE"


@dataclass
class Signal:
    asset: str
    direction: Direction
    size: float      # in asset units (e.g. BTC)
    price: float     # USD
    provider: str = "lumibot"

    def to_dict(self) -> dict:
        return {
            "asset": self.asset,
            "direction": self.direction.value,
            "size": self.size,
            "price": self.price,
            "provider": self.provider,
        }


class LumibotBroker:
    """
    Posts trading signals from Lumibot (or manual input) to Supabase via the
    dApp's signals API endpoint.

    Parameters
    ----------
    dapp_url : str
        Base URL of the deployed dApp (e.g. "https://app.zentorylabs.com").
        If None, reads from DAPP_URL environment variable.
    api_timeout : float
        HTTP request timeout in seconds.
    """

    def __init__(
        self,
        dapp_url: str | None = None,
        api_timeout: float = 15.0,
    ) -> None:
        self.dapp_url = (dapp_url or os.environ.get("DAPP_URL", "")).rstrip("/")
        if not self.dapp_url:
            raise ValueError("dapp_url must be provided or DAPP_URL env var set")
        self._client = httpx.AsyncClient(timeout=api_timeout, follow_redirects=True)

    async def close(self) -> None:
        await self._client.aclose()

    async def post_signal(self, signal: Signal) -> Optional[dict]:
        """
        POST a signal to Supabase via the dApp API.

        Returns the created signal record (with id, created_at) or None on failure.
        """
        url = f"{self.dapp_url}/api/signals"
        try:
            response = await self._client.post(
                url,
                json=signal.to_dict(),
                headers={"Content-Type": "application/json"},
            )
            if response.status_code == 201:
                data = response.json()
                logger.info(
                    "signal.posted",
                    signal_id=data.get("id"),
                    asset=signal.asset,
                    direction=signal.direction.value,
                    size=signal.size,
                    price=signal.price,
                )
                return data
            else:
                logger.error(
                    "signal.post_failed",
                    status=response.status_code,
                    body=response.text[:200],
                )
                return None
        except Exception as exc:
            logger.error("signal.post_exception", error=str(exc))
            return None

    async def get_signals(self, limit: int = 50) -> list[dict]:
        """Fetch recent signals from Supabase via the dApp API."""
        url = f"{self.dapp_url}/api/signals"
        try:
            response = await self._client.get(url, params={"limit": limit})
            if response.status_code == 200:
                return response.json()
            logger.error("signals.fetch_failed", status=response.status_code)
            return []
        except Exception as exc:
            logger.error("signals.fetch_exception", error=str(exc))
            return []

    async def execute_signal(self, signal_id: str, asset: str, direction: str, size: float, price: float) -> Optional[dict]:
        """
        Trigger on-chain execution of a signal via the keeper route.

        Returns execution result with tx_hash or None on failure.
        """
        url = f"{self.dapp_url}/api/signals/execute"
        try:
            response = await self._client.post(
                url,
                json={
                    "signalId": signal_id,
                    "asset": VAULT_ADDRESSES.get(asset.upper(), asset),
                    "direction": direction,
                    "size": int(size * 10 ** ASSET_DECIMALS.get(asset.upper(), 18)),
                    "price": int(price * 1_000_000),  # price * 1e6 for recordTradeManual
                },
                headers={"Content-Type": "application/json"},
            )
            if response.status_code == 200:
                data = response.json()
                logger.info("signal.executed", tx_hash=data.get("txHash"), signal_id=signal_id)
                return data
            else:
                logger.error("signal.execute_failed", status=response.status_code, body=response.text[:200])
                return None
        except Exception as exc:
            logger.error("signal.execute_exception", error=str(exc))
            return None


async def main() -> None:
    parser = argparse.ArgumentParser(description="Post a trading signal to the Zentory dApp")
    parser.add_argument("--asset", required=True, choices=["BTC", "ETH", "XRP", "SOL"], help="Asset symbol")
    parser.add_argument("--direction", required=True, choices=["LONG", "SHORT", "CLOSE"], help="Trade direction")
    parser.add_argument("--size", required=True, type=float, help="Position size in asset units (e.g. 0.01 BTC)")
    parser.add_argument("--price", required=True, type=float, help="Limit price in USD")
    parser.add_argument("--execute", action="store_true", help="Also execute on-chain immediately after posting")
    parser.add_argument("--dapp-url", default=os.environ.get("DAPP_URL", "https://app.zentorylabs.com"), help="dApp base URL")

    args = parser.parse_args()

    broker = LumibotBroker(dapp_url=args.dapp_url)
    try:
        signal = Signal(
            asset=args.asset.upper(),
            direction=Direction(args.direction),
            size=args.size,
            price=args.price,
        )

        logger.info("posting_signal", **signal.to_dict())
        result = await broker.post_signal(signal)

        if result is None:
            logger.error("Failed to post signal. Check DAPP_URL and Supabase connection.")
            sys.exit(1)

        signal_id = result.get("id")
        logger.info("signal_stored", signal_id=signal_id)

        if args.execute:
            logger.info("executing_on_chain", signal_id=signal_id)
            exec_result = await broker.execute_signal(
                signal_id=signal_id,
                asset=args.asset,
                direction=args.direction,
                size=args.size,
                price=args.price,
            )
            if exec_result:
                print(f"\n✅ Executed! TX: https://hypurrscan.io/tx/{exec_result.get('txHash')}")
            else:
                print("\n⚠️  Signal posted but on-chain execution failed. Execute manually from the dApp.")

    finally:
        await broker.close()


if __name__ == "__main__":
    asyncio.run(main())

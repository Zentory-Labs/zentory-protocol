"""Minimal Hyperliquid Info API client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx


@dataclass(frozen=True)
class HyperliquidInfoConfig:
    base_url: str = "https://api.hyperliquid-testnet.xyz/info"


class HyperliquidInfoClient:
    def __init__(self, config: HyperliquidInfoConfig | None = None):
        cfg = config or HyperliquidInfoConfig()
        self._client = httpx.Client(base_url=cfg.base_url.rstrip("/") + "/info", timeout=30.0)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "HyperliquidInfoClient":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def user_fills(self, user: str, *, aggregate_by_time: bool | None = None) -> Any:
        payload: dict[str, Any] = {"type": "userFills", "user": user}
        if aggregate_by_time is not None:
            payload["aggregateByTime"] = aggregate_by_time
        r = self._client.post("", json=payload)
        r.raise_for_status()
        return r.json()

    def user_fills_by_time(
        self,
        user: str,
        *,
        start_time_ms: int,
        end_time_ms: int | None = None,
        aggregate_by_time: bool | None = None,
    ) -> Any:
        payload: dict[str, Any] = {
            "type": "userFillsByTime",
            "user": user,
            "startTime": start_time_ms,
        }
        if end_time_ms is not None:
            payload["endTime"] = end_time_ms
        if aggregate_by_time is not None:
            payload["aggregateByTime"] = aggregate_by_time
        r = self._client.post("", json=payload)
        r.raise_for_status()
        return r.json()

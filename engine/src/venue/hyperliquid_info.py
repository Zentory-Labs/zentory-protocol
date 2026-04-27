"""Minimal Hyperliquid Info API client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx


def _info_http_base(url: str) -> str:
    """
    Accept either API root (https://api.hyperliquid-testnet.xyz) or full info URL
    (https://api.hyperliquid-testnet.xyz/info) and return exactly .../info with no double path.
    """
    u = url.strip().rstrip("/")
    while u.endswith("/info"):
        u = u[: -len("/info")].rstrip("/")
    # No trailing slash — httpx merges paths; a trailing slash on base can break POST to "".
    return (u + "/info").rstrip("/")


@dataclass(frozen=True)
class HyperliquidInfoConfig:
    # Prefer origin only; full ".../info" also works — see _info_http_base.
    base_url: str = "https://api.hyperliquid-testnet.xyz"


class HyperliquidInfoClient:
    def __init__(self, config: HyperliquidInfoConfig | None = None):
        cfg = config or HyperliquidInfoConfig()
        # Always POST to the absolute /info URL (avoid httpx base_url + "" merge quirks).
        self._info_url = _info_http_base(cfg.base_url)
        self._client = httpx.Client(timeout=30.0)

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
        r = self._client.post(self._info_url, json=payload)
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
        r = self._client.post(self._info_url, json=payload)
        r.raise_for_status()
        return r.json()

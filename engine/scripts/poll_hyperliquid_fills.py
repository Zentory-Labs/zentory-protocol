"""Poll Hyperliquid user fills for each vault trading wallet and upsert into Supabase.

Environment variables:
  SUPABASE_URL                 (required)
  SUPABASE_SERVICE_ROLE_KEY    (required)

Optional:
  HYPERLIQUID_INFO_URL         default https://api.hyperliquid-testnet.xyz/info

Mapping:
  VAULT_TRADING_MAP            JSON object: {"<vault_address>":"<hl_user_address>", ...}

Usage:
  python scripts/poll_hyperliquid_fills.py --once
  python scripts/poll_hyperliquid_fills.py --sleep 30
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any

import httpx

# Ensure `src/` is importable when executed as a script file.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from venue.hyperliquid_info import HyperliquidInfoClient, HyperliquidInfoConfig  # noqa: E402


def _fill_key(fill: dict[str, Any]) -> str:
    tid = fill.get("tid")
    h = fill.get("hash")
    t = fill.get("time")
    oid = fill.get("oid")

    parts = []
    if tid is not None:
        parts.append(str(tid))
    if oid is not None:
        parts.append(str(oid))
    if h is not None:
        parts.append(str(h))
    parts.append(str(t))

    key = ":".join(parts)
    # Keep length reasonable but stable
    return key[:512]


def upsert_rows(
    supabase_url: str,
    service_role_key: str,
    rows: list[dict[str, Any]],
) -> None:
    if not rows:
        return

    headers = {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }

    with httpx.Client(timeout=60.0) as client:
        r = client.post(f"{supabase_url.rstrip('/')}/rest/v1/hl_user_fills", headers=headers, json=rows)
        r.raise_for_status()


def poll_once() -> int:
    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    mp = os.environ.get("VAULT_TRADING_MAP", "").strip()

    if not supabase_url or not key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")

    if not mp:
        raise SystemExit(
            'Missing VAULT_TRADING_MAP JSON (example: '
            '\'{"0xvault...":"0xhlUser...","0xvault2":"0xhlUser2..."}\')'
        )

    mapping = json.loads(mp)
    if not isinstance(mapping, dict) or not mapping:
        raise SystemExit("VAULT_TRADING_MAP must be a non-empty JSON object")

    hl_base = os.environ.get("HYPERLIQUID_INFO_URL", "https://api.hyperliquid-testnet.xyz/info")

    rows: list[dict[str, Any]] = []

    with HyperliquidInfoClient(HyperliquidInfoConfig(base_url=hl_base.replace("/info", "").rstrip("/"))) as hl:
        for vault_address, hl_user in mapping.items():
            fills = hl.user_fills(str(hl_user))

            if not isinstance(fills, list):
                raise RuntimeError(f"Unexpected userFills payload for {vault_address}: {type(fills)}")

            for fill in fills:
                if not isinstance(fill, dict):
                    continue

                fk = _fill_key(fill)

                rows.append(
                    {
                        "vault_address": str(vault_address),
                        "hl_user_address": str(hl_user),
                        "source": "hyperliquid_testnet_info",
                        "fill_key": fk,
                        "coin": fill.get("coin"),
                        "px": fill.get("px"),
                        "sz": fill.get("sz"),
                        "side": fill.get("side"),
                        "dir": fill.get("dir"),
                        "fee": fill.get("fee"),
                        "fee_token": fill.get("feeToken"),
                        "closed_pnl": fill.get("closedPnl"),
                        "oid": str(fill["oid"]) if fill.get("oid") is not None else None,
                        "tid": str(fill["tid"]) if fill.get("tid") is not None else None,
                        "time_ms": int(fill["time"]) if fill.get("time") is not None else None,
                        "hash": fill.get("hash"),
                        "raw": fill,
                    }
                )

    upsert_rows(supabase_url, key, rows)
    return len(rows)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--once", action="store_true")
    p.add_argument("--sleep", type=float, default=30.0)
    args = p.parse_args()

    while True:
        n = poll_once()
        print(f"upserted_rows={n}")
        if args.once:
            return
        time.sleep(max(1.0, float(args.sleep)))


if __name__ == "__main__":
    main()

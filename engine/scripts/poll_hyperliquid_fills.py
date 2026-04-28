"""Poll Hyperliquid user fills for each vault trading wallet and upsert into Supabase.

Environment variables:
  SUPABASE_URL                 (required)
  SUPABASE_SERVICE_ROLE_KEY    (required)

Optional:
  HYPERLIQUID_INFO_URL         API root or .../info (default https://api.hyperliquid-testnet.xyz)

Mapping (first match wins):
  1) --map-file / VAULT_TRADING_MAP_FILE file contents
  2) VAULT_TRADING_MAP inline JSON string
  3) Supabase table public.vault_trading_accounts (columns vault_address, hl_user_address)

Usage:
  python scripts/poll_hyperliquid_fills.py --once
  python scripts/poll_hyperliquid_fills.py --once --map-from-supabase
  python scripts/poll_hyperliquid_fills.py --once --map-file ./vault-trading-map.json
  python scripts/poll_hyperliquid_fills.py --sleep 30
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import defaultdict
from typing import Any

import httpx

# Exactly 42 chars: 0x + 40 hex (HyperEVM / HL user addresses).
_EVM_ADDR_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")


def _is_valid_evm_address(s: str) -> bool:
    return bool(_EVM_ADDR_RE.match(s.strip()))

# Ensure `src/` is importable when executed as a script file.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from venue.hyperliquid_info import HyperliquidInfoClient, HyperliquidInfoConfig  # noqa: E402


def _normalize_vault_map(mapping: dict[Any, Any]) -> dict[str, str]:
    out: dict[str, str] = {}
    for k, v in mapping.items():
        ks, vs = str(k).strip(), str(v).strip()
        if not _is_valid_evm_address(ks):
            raise SystemExit(
                f"Invalid vault address key: {ks!r}. "
                "Must be exactly 0x followed by 40 hexadecimal characters (deployed vault contract)."
            )
        if not _is_valid_evm_address(vs):
            raise SystemExit(
                f"Invalid HL user address for vault {ks[:10]}...: {vs!r}. "
                "Must be exactly 0x followed by 40 hexadecimal characters."
            )
        out[ks.lower()] = vs.lower()
    return out


def _fetch_map_from_supabase(supabase_url: str, service_role_key: str) -> dict[str, str]:
    """Load vault_address -> hl_user_address from public.vault_trading_accounts."""
    headers = {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Accept": "application/json",
    }
    url = f"{supabase_url.rstrip('/')}/rest/v1/vault_trading_accounts?select=vault_address,hl_user_address"
    with httpx.Client(timeout=60.0) as client:
        r = client.get(url, headers=headers)
        r.raise_for_status()
        rows = r.json()

    if not isinstance(rows, list):
        raise SystemExit(f"Unexpected vault_trading_accounts response: {type(rows)}")

    d: dict[str, str] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        va = str(row.get("vault_address", "")).strip()
        hu = str(row.get("hl_user_address", "")).strip()
        if not va and not hu:
            continue
        if not _is_valid_evm_address(va):
            print(
                "[vault_trading_accounts] skipping row: vault_address must be full contract hex "
                f"(got {va!r}). Put labels in `notes`, not vault_address.",
                file=sys.stderr,
            )
            continue
        if not _is_valid_evm_address(hu):
            print(
                "[vault_trading_accounts] skipping row: hl_user_address must be full HL user hex "
                f"(vault {va[:10]}..., got {hu!r}).",
                file=sys.stderr,
            )
            continue
        d[va.lower()] = hu.lower()

    if not d:
        raise SystemExit(
            "vault_trading_accounts has no usable rows (need valid vault_address and hl_user_address: "
            "0x + 40 hex chars each). Remove placeholders like '0x…zBTC…'; use real addresses from "
            "frontend/lib/contracts.ts for vaults. Or use --map-file / VAULT_TRADING_MAP."
        )

    return d


def _load_vault_trading_map(
    arg_map_file: str | None,
    *,
    map_from_supabase: bool,
    supabase_url: str,
    service_role_key: str,
) -> dict[str, str]:
    """Resolve vault -> hl_user: file / env JSON, or Supabase table."""
    if map_from_supabase:
        return _fetch_map_from_supabase(supabase_url, service_role_key)

    path = (arg_map_file or os.environ.get("VAULT_TRADING_MAP_FILE", "")).strip()
    raw = os.environ.get("VAULT_TRADING_MAP", "").strip()

    if path:
        p = os.path.abspath(path)
        if not os.path.isfile(p):
            hint = ""
            if arg_map_file:
                hint = " Create it (e.g. copy vault-trading-map.example.json) or fix --map-file."
            else:
                hint = " Create the file or unset VAULT_TRADING_MAP_FILE."
            raise SystemExit(f"Vault trading map file not found: {p}{hint}")
        with open(p, encoding="utf-8") as f:
            raw = f.read()

    if not raw:
        return _fetch_map_from_supabase(supabase_url, service_role_key)

    try:
        mapping = json.loads(raw)
    except json.JSONDecodeError as e:
        raise SystemExit(
            f"Invalid JSON for vault map ({e}). "
            "Tip: use --map-file vault-trading-map.json or use --map-from-supabase."
        ) from e

    if not isinstance(mapping, dict) or not mapping:
        raise SystemExit("Vault map must be a non-empty JSON object")

    return _normalize_vault_map(mapping)


def _vaults_by_hl_user(mapping: dict[str, str]) -> dict[str, list[str]]:
    """Group vaults sharing the same HL user (one userFills call per distinct hl user)."""
    by_hl: dict[str, list[str]] = defaultdict(list)
    for vault, hl in mapping.items():
        by_hl[hl.lower()].append(vault.lower())
    return dict(by_hl)


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


def _dedupe_fill_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One row per (vault_address, fill_key); last wins (same batch may repeat)."""
    merged: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        vk = (str(row["vault_address"]), str(row["fill_key"]))
        merged[vk] = row
    return list(merged.values())


def upsert_rows(
    supabase_url: str,
    service_role_key: str,
    rows: list[dict[str, Any]],
) -> None:
    if not rows:
        return

    rows = _dedupe_fill_rows(rows)

    headers = {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
        # Upsert on logical identity, not bigserial id (otherwise 409 on re-run).
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }

    base = f"{supabase_url.rstrip('/')}/rest/v1/hl_user_fills"
    url = f"{base}?on_conflict=vault_address,fill_key"

    with httpx.Client(timeout=60.0) as client:
        r = client.post(url, headers=headers, json=rows)
        try:
            r.raise_for_status()
        except httpx.HTTPStatusError as e:
            detail = (e.response.text or "")[:800]
            raise RuntimeError(f"hl_user_fills upsert failed {e.response.status_code}: {detail}") from e


def poll_once(map_file: str | None = None, *, map_from_supabase: bool = False) -> int:
    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()

    if not supabase_url or not key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")

    mapping = _load_vault_trading_map(
        map_file,
        map_from_supabase=map_from_supabase,
        supabase_url=supabase_url,
        service_role_key=key,
    )

    hl_base = os.environ.get("HYPERLIQUID_INFO_URL", "https://api.hyperliquid-testnet.xyz").strip()

    rows: list[dict[str, Any]] = []

    with HyperliquidInfoClient(HyperliquidInfoConfig(base_url=hl_base)) as hl:
        for hl_user, vault_addrs in _vaults_by_hl_user(mapping).items():
            fills = hl.user_fills(str(hl_user))

            if not isinstance(fills, list):
                raise RuntimeError(f"Unexpected userFills payload for hl_user={hl_user}: {type(fills)}")

            for vault_address in vault_addrs:
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
    p.add_argument("--map-file", type=str, default=None, help="JSON file: {\"0xvault\":\"0xhlUser\", ...}")
    p.add_argument(
        "--map-from-supabase",
        action="store_true",
        help="Load mapping from public.vault_trading_accounts (overrides JSON / file when set)",
    )
    args = p.parse_args()

    while True:
        n = poll_once(args.map_file, map_from_supabase=args.map_from_supabase)
        print(f"upserted_rows={n}")
        if args.once:
            return
        time.sleep(max(1.0, float(args.sleep)))


if __name__ == "__main__":
    main()

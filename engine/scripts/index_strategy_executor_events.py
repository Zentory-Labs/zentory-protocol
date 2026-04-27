"""
Scan HyperEVM for StrategyExecutor TradeSignalExecuted logs and upsert into Supabase execution_attempts.

TradeSignalExecuted(address indexed vault, uint8 indexed direction, uint256 size, uint256 price,
                   uint256 nonce, address indexed keeper)

Environment:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  HYPEREVM_RPC_URL          default https://rpc.hyperliquid-testnet.xyz/evm
  STRATEGY_EXECUTOR         default deployed StrategyExecutor on testnet

Optional:
  FROM_BLOCK                 default: latest - 2000 blocks (capped)
  TO_BLOCK                   default: latest
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import httpx
from eth_abi import decode

TOPIC0 = "0x7d8a7739c884cee63d3f5dd59938ec9e356acfe8327ab9111a1a32e19d11ac20"


def rpc_call(url: str, method: str, params: list) -> Any:
    r = httpx.post(
        url,
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        timeout=60.0,
    )
    r.raise_for_status()
    j = r.json()
    if "error" in j:
        raise RuntimeError(j["error"])
    return j["result"]


def hex_to_int(h: str) -> int:
    return int(h, 16)


def topic_address(topic: str) -> str:
    return "0x" + topic[-40:].lower()


def upsert_attempts(supabase_url: str, key: str, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }
    with httpx.Client(timeout=60.0) as c:
        r = c.post(f"{supabase_url.rstrip('/')}/rest/v1/execution_attempts", headers=headers, json=rows)
        r.raise_for_status()


def decode_log(log: dict[str, Any]) -> dict[str, Any]:
    topics = log["topics"]
    if len(topics) != 4:
        raise ValueError("unexpected topics")

    vault = topic_address(topics[1])
    direction = hex_to_int(topics[2]) & 0xFF
    keeper = topic_address(topics[3])

    data = bytes.fromhex(log["data"][2:])
    size_u, price_u, nonce_u = decode(["uint256", "uint256", "uint256"], data)

    tx_hash = log["transactionHash"]

    return {
        "vault_address": vault,
        "tx_hash": tx_hash,
        "chain_id": 998,
        "nonce": str(nonce_u),
        "direction": direction,
        "size_raw": str(size_u),
        "price_raw": str(price_u),
        "expiry_ts": None,
        "status": "confirmed",
        "error": None,
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--from-block", type=int, default=None)
    p.add_argument("--to-block", type=int, default=None)
    args = p.parse_args()

    rpc = os.environ.get("HYPEREVM_RPC_URL", "https://rpc.hyperliquid-testnet.xyz/evm").strip()
    exe = os.environ.get("STRATEGY_EXECUTOR", "0x427c94150f3f700Dc2EDf7bCc97155A467E41F21").strip()

    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not supabase_url or not key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")

    latest_hex = rpc_call(rpc, "eth_blockNumber", [])
    latest = hex_to_int(latest_hex)

    to_block = args.to_block if args.to_block is not None else latest
    if args.from_block is not None:
        from_block = args.from_block
    else:
        span = 2000
        from_block = max(0, to_block - span)

    filt = {
        "fromBlock": hex(from_block),
        "toBlock": hex(to_block),
        "address": exe,
        "topics": [TOPIC0],
    }

    logs = rpc_call(rpc, "eth_getLogs", [filt])
    if not isinstance(logs, list):
        raise RuntimeError(f"unexpected eth_getLogs payload: {type(logs)}")

    rows: list[dict[str, Any]] = []
    for log in logs:
        try:
            rows.append(decode_log(log))
        except Exception as e:
            print("skip_log", e, log.get("transactionHash"))

    upsert_attempts(supabase_url, key, rows)
    print(f"blocks {from_block}-{to_block} logs={len(logs)} upserts={len(rows)}")


if __name__ == "__main__":
    main()

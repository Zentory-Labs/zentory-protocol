"""
Zentory Protocol — On-Chain Event Monitor
==========================================
Lightweight monitor that polls HyperEVM for critical events via transaction-receipt
polling. Sends Discord webhook alerts.

Usage:
    python -m monitor.event_monitor
    python -m monitor.event_monitor --alchemy-api-key YOUR_KEY --discord-webhook URL
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

import httpx
import structlog

# ── Logging ────────────────────────────────────────────────────────────────────

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)
log = structlog.get_logger()


# ── Contract Addresses (HyperEVM Testnet) ────────────────────────────────────

CONTRACTS: dict[str, str] = {
    "ZENT": "0x271cd48c1297CacCD810c7B1BCD904f459df7117",
    "ZENTVesting": "0xf7c45f45768d790F388215A44d6E01f6f2568774",
    "zETH": "0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e",
    "zBTC": "0x93669daC07321FF397cf5734Ae8364EA24addF45",
    "zXRP": "0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0",
    "zSOL": "0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052",
    "ZENTStaking": "0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65",
    "FeeDistributor_zETH": "0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73",
    "FeeDistributor_zBTC": "0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c",
    "FeeDistributor_zXRP": "0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F",
    "FeeDistributor_zSOL": "0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0",
    "Timelock": "0x1504cA3C050C88CcCa67696d642F634fc381fD03",
    "Zentroller": "0x24f9401284CE16CFe61e40C1F9e3fb37d15B878E",
    "ZentGovernor": "0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118",
    "HyperCoreAdapter": "0xfFc1Da47f780973e935Bb9F5a9d455aE7A5f7eac",
    "StrategyExecutor": "0x427c94150f3f700Dc2EDf7bCc97155A467E41F21",
}

# ── Event Signatures ───────────────────────────────────────────────────────────

EVENT_SIGNATURES: dict[str, str] = {
    "PausedSet": "0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212",
    "RoleGranted": "0x2f8788117e7eff1d82e926ec794901d17c78024a50270900396234040b2446a",
    "RoleRevoked": "0xf6391c5ce51040ba51727fd3557d502ec8ab4764db999d5e8b01e7cbce7e3f75",
    "ManualTradeRecorded": "0x9f2d5dcbc3e4e2a8d3e8e6c1c1f9d3c6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c",
    "CircuitBreakerActivated": "0x8a4e1c9d6f7a8b3c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3",
    "CircuitBreakerAutoTriggered": "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1",
    "FeesDistributed": "0x2c5f8c4d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2",
    "Staked": "0x9e4a8d1f2c3b4a5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9",
    "Withdrawn": "0x0f1e2d3c4b5a69788a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1",
}

SEVERITY_MAP: dict[str, str] = {
    "PausedSet": "CRITICAL",
    "RoleGranted": "CRITICAL",
    "RoleRevoked": "CRITICAL",
    "CircuitBreakerActivated": "HIGH",
    "CircuitBreakerAutoTriggered": "HIGH",
    "FeesDistributed": "MEDIUM",
    "ManualTradeRecorded": "LOW",
    "Staked": "LOW",
    "Withdrawn": "LOW",
}

SIGNATURE_TO_NAME = {v: k for k, v in EVENT_SIGNATURES.items()}


# ── Dataclasses ──────────────────────────────────────────────────────────────


@dataclass
class EventAlert:
    contract_name: str
    contract_address: str
    event_name: str
    event_signature: str
    tx_hash: str
    block_number: int
    block_timestamp: datetime
    data: dict[str, Any]
    severity: str


@dataclass
class MonitorState:
    last_block_checked: int = 0
    events_seen: set[str] = field(default_factory=set)  # "tx_hash:logIndex"


# ── RPC Client ────────────────────────────────────────────────────────────────


class RPCClient:
    """Minimal HTTP RPC client using httpx."""

    def __init__(self, rpc_url: str, request_timeout: float = 30.0):
        self.rpc_url = rpc_url
        self._client = httpx.Client(timeout=request_timeout)

    def _call(self, method: str, params: list | None = None) -> Any:
        payload = {"jsonrpc": "2.0", "id": 1, "method": method}
        if params is not None:
            payload["params"] = params
        resp = self._client.post(self.rpc_url, json=payload)
        resp.raise_for_status()
        data = resp.json()
        if "error" in data:
            raise RuntimeError(f"RPC error: {data['error']}")
        return data.get("result")

    def eth_block_number(self) -> int:
        result = self._call("eth_blockNumber")
        return int(result, 16) if isinstance(result, str) else result

    def eth_get_block_by_number(self, block_num: int) -> dict | None:
        return self._call("eth_getBlockByNumber", [hex(block_num), True])

    def eth_get_transaction_receipt(self, tx_hash: str) -> dict | None:
        return self._call("eth_getTransactionReceipt", [tx_hash])


# ── Discord Notifier ─────────────────────────────────────────────────────────


class DiscordNotifier:
    def __init__(self, webhook_url: str | None = None):
        self.webhook_url = webhook_url or os.getenv("DISCORD_WEBHOOK_URL", "")
        self.enabled = bool(self.webhook_url)

    def _severity_color(self, severity: str) -> int:
        return {
            "CRITICAL": 0xFF0000,
            "HIGH": 0xFF8800,
            "MEDIUM": 0xFFDD00,
            "LOW": 0x00FF88,
        }.get(severity, 0x888888)

    def send_alert(self, alert: EventAlert) -> bool:
        if not self.enabled:
            log.info("discord_alert_skipped", severity=alert.severity, evt=alert.event_name)
            return False

        explorer_url = f"https://hypurrscan.io/tx/{alert.tx_hash}"
        title_icon = {
            "CRITICAL": ":rotating_light:",
            "HIGH": ":warning:",
            "MEDIUM": ":large_yellow_circle:",
            "LOW": ":information_source:",
        }.get(alert.severity, "")

        fields = [
            {"name": "Contract", "value": f"`{alert.contract_address}`", "inline": True},
            {"name": "Block", "value": str(alert.block_number), "inline": True},
            {"name": "TX", "value": f"[`{alert.tx_hash[:12]}...`]({explorer_url})", "inline": False},
        ]
        if alert.data:
            data_str = ", ".join(f"{k}={v}" for k, v in alert.data.items())
            fields.insert(2, {"name": "Data", "value": f"`{data_str}`", "inline": False})

        payload = {
            "username": "Zentory Monitor",
            "embeds": [{
                "title": f"{title_icon} [{alert.severity}] {alert.event_name} on {alert.contract_name}",
                "color": self._severity_color(alert.severity),
                "description": f"Event `{alert.event_name}` on **{alert.contract_name}**",
                "fields": fields,
                "footer": {"text": "Zentory Protocol — HyperEVM Testnet"},
                "timestamp": alert.block_timestamp.isoformat(),
            }],
        }

        try:
            r = httpx.post(self.webhook_url, json=payload, timeout=10.0)
            r.raise_for_status()
            log.info("discord_alert_sent", tx_hash=alert.tx_hash, evt=alert.event_name)
            return True
        except Exception as e:
            log.error("discord_alert_failed", err=str(e), tx_hash=alert.tx_hash)
            return False

    def send_test_alert(self) -> bool:
        test = EventAlert(
            contract_name="TestContract",
            contract_address="0x" + "0" * 40,
            event_name="TestAlert",
            event_signature="0x" + "0" * 64,
            tx_hash="0x" + "0" * 64,
            block_number=0,
            block_timestamp=datetime.now(timezone.utc),
            data={},
            severity="LOW",
        )
        return self.send_alert(test)


# ── Event Monitor ─────────────────────────────────────────────────────────────


class EventMonitor:
    """
    Polls HyperEVM for critical on-chain events via block + receipt polling.

    Works on any EVM RPC that supports eth_getTransactionReceipt.
    Alchemy recommended for rate-limit-free access.
    """

    def __init__(
        self,
        rpc_url: str | None = None,
        poll_interval: int = 30,
        from_block: int | None = None,
        notifier: DiscordNotifier | None = None,
        verify_fire_on_start: bool = True,
        query_delay: float = 0.1,
        alchemy_api_key: str | None = None,
    ):
        base_url = rpc_url or os.getenv("HYPEREVM_RPC", "")
        if alchemy_api_key:
            base_url = f"https://hyperliquid-testnet.g.alchemy.com/v2/{alchemy_api_key}"
        elif not base_url:
            base_url = "https://rpc.hyperliquid-testnet.xyz/evm"

        self.rpc = RPCClient(base_url)
        self.poll_interval = poll_interval
        self.query_delay = query_delay
        self.notifier = notifier or DiscordNotifier()
        self._override_from_block = from_block  # stored before load
        self.state = MonitorState()
        self._load_state()

        # Explicit from_block argument always wins over loaded state
        if self._override_from_block is not None:
            self.state.last_block_checked = self._override_from_block - 1

        log.info("event_monitor_init", rpc=base_url, poll_interval=poll_interval)

    # ── State persistence ────────────────────────────────────────────────────

    def _state_path(self) -> str:
        return os.path.join(os.path.dirname(__file__), ".monitor_state.json")

    def _load_state(self) -> None:
        path = self._state_path()
        if os.path.exists(path):
            try:
                with open(path) as f:
                    d = json.load(f)
                self.state.last_block_checked = d.get("last_block_checked", 0)
                self.state.events_seen = set(d.get("events_seen", []))
                log.info("state_loaded", last_block=self.state.last_block_checked)
            except Exception as e:
                log.warning("state_load_failed", err=str(e))

    def _save_state(self) -> None:
        try:
            with open(self._state_path(), "w") as f:
                json.dump(
                    {
                        "last_block_checked": self.state.last_block_checked,
                        "events_seen": list(self.state.events_seen),
                    },
                    f,
                )
        except Exception as e:
            log.error("state_save_failed", err=str(e))

    # ── Event decoding ───────────────────────────────────────────────────────

    def _decode_receipt_log(self, log_entry: dict) -> EventAlert | None:
        topics = log_entry.get("topics") or []
        if not topics:
            return None

        sig = topics[0]
        event_name = SIGNATURE_TO_NAME.get(sig)
        if not event_name:
            return None

        address = (log_entry.get("address") or "").lower()
        contract_name = next(
            (name for name, addr in CONTRACTS.items() if addr.lower() == address),
            address,
        )

        tx_hash = log_entry.get("transactionHash", "0x" + "0" * 64)
        block_number = int(log_entry.get("blockNumber", "0x0"), 16)
        data_hex = (log_entry.get("data") or "0x")[2:]

        data: dict[str, Any] = {}
        if event_name == "PausedSet" and data_hex:
            data["paused"] = int(data_hex, 16) != 0
        elif event_name in ("RoleGranted", "RoleRevoked") and len(data_hex) >= 104:
            data["role"] = "0x" + data_hex[:64]
            data["account"] = "0x" + data_hex[64:104]

        block_ts = 0
        try:
            block = self.rpc.eth_get_block_by_number(block_number)
            if block:
                block_ts = int(block.get("timestamp", "0x0"), 16)
        except Exception:
            pass

        return EventAlert(
            contract_name=contract_name,
            contract_address=log_entry.get("address", ""),
            event_name=event_name,
            event_signature=sig,
            tx_hash=tx_hash,
            block_number=block_number,
            block_timestamp=(
                datetime.fromtimestamp(block_ts, tz=timezone.utc)
                if block_ts else datetime.now(timezone.utc)
            ),
            data=data,
            severity=SEVERITY_MAP.get(event_name, "LOW"),
        )

    # ── Polling ────────────────────────────────────────────────────────────

    def _process_receipt(self, tx_hash: str) -> list[EventAlert]:
        alerts = []
        try:
            receipt = self.rpc.eth_get_transaction_receipt(tx_hash)
        except Exception as e:
            log.warning("receipt_fetch_failed", tx=tx_hash, err=str(e))
            return []

        if not receipt:
            return []

        for log_entry in receipt.get("logs", []):
            log_idx = str(log_entry.get("logIndex", "0x0"))
            dedup_key = f"{tx_hash}:{log_idx}"
            if dedup_key in self.state.events_seen:
                continue
            self.state.events_seen.add(dedup_key)

            alert = self._decode_receipt_log(log_entry)
            if not alert:
                continue

            self.notifier.send_alert(alert)
            alerts.append(alert)
            log.info("alert_triggered", severity=alert.severity, evt=alert.event_name, contract=alert.contract_name, tx=alert.tx_hash)

        return alerts

    def poll_once(self, from_block: int | None = None, to_block: int | None = None) -> list[EventAlert]:
        current_block = self.rpc.eth_block_number()
        if from_block is None:
            from_block = max(self.state.last_block_checked + 1, current_block - 10)
        if to_block is None:
            to_block = current_block

        if from_block > to_block:
            return []

        log.info("polling_blocks", from_block=from_block, to_block=to_block)
        all_alerts: list[EventAlert] = []

        for block_num in range(from_block, to_block + 1):
            try:
                block = self.rpc.eth_get_block_by_number(block_num)
            except Exception as e:
                log.warning("block_fetch_failed", block=block_num, err=str(e))
                continue

            if not block:
                continue

            txs = block.get("transactions") or []
            if not txs:
                continue

            log.info("processing_block", block=block_num, tx_count=len(txs))
            for tx in txs:
                tx_hash = tx if isinstance(tx, str) else tx.get("hash")
                if not tx_hash:
                    continue
                alerts = self._process_receipt(tx_hash)
                all_alerts.extend(alerts)
                time.sleep(self.query_delay)

        self.state.last_block_checked = to_block
        self._save_state()
        return all_alerts

    def run(self) -> None:
        log.info("monitor_started", poll_interval=self.poll_interval)

        log.info("verifying_past_events")
        alerts = self.poll_once(
            from_block=getattr(self, '_override_from_block', None),
        )
        log.info("historical_alerts_found", count=len(alerts))

        while True:
            try:
                alerts = self.poll_once()
                if alerts:
                    log.info("new_alerts", count=len(alerts))
            except Exception as e:
                log.error("poll_failed", err=str(e))
            time.sleep(self.poll_interval)


# ── CLI ───────────────────────────────────────────────────────────────────────


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Zentory Protocol Event Monitor")
    parser.add_argument("--alchemy-api-key", type=str, default=os.getenv("ALCHEMY_API_KEY", ""),
        help="Alchemy API key (free at alchemy.com/hyperevm)")
    parser.add_argument("--rpc-url", type=str, default=None,
        help="Custom RPC URL")
    parser.add_argument("--poll-interval", type=int, default=30,
        help="Seconds between polls (default: 30)")
    parser.add_argument("--from-block", type=int, default=None,
        help="Start from this block (default: last saved)")
    parser.add_argument("--discord-webhook", type=str, default=os.getenv("DISCORD_WEBHOOK_URL", ""),
        help="Discord webhook URL")
    parser.add_argument("--test", action="store_true", help="Send test alert and exit")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    notifier = DiscordNotifier(webhook_url=args.discord_webhook)

    if args.test:
        print("Sending test alert to Discord...")
        success = notifier.send_test_alert()
        print("Sent!" if success else "Failed (check webhook URL or network)")
        sys.exit(0 if success else 1)

    monitor = EventMonitor(
        rpc_url=args.rpc_url,
        poll_interval=args.poll_interval,
        from_block=args.from_block,
        notifier=notifier,
        alchemy_api_key=args.alchemy_api_key or None,
    )
    monitor.run()


if __name__ == "__main__":
    main()

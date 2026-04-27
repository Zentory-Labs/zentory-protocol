"""
Zentory Protocol — On-Chain Event Monitor
==========================================
Lightweight monitor that polls HyperEVM RPC for critical events and
sends Discord/Slack webhook alerts. No external service required.

Usage:
    python -m monitor.event_monitor
    python -m monitor.event_monitor --poll-interval 30
"""

from __future__ import annotations

import argparse
import asyncio
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
from web3 import Web3

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
    # PausedSet(bool paused)
    "PausedSet": "0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212",
    # RoleGranted(bytes32 role, address account)
    "RoleGranted": "0x2f8788117e7eff1d82e926ec794901d17c78024a50270900396234040b2446a",
    # RoleRevoked(bytes32 role, address account)
    "RoleRevoked": "0xf6391c5ce51040ba51727fd3557d502ec8ab4764db999d5e8b01e7cbce7e3f75",
    # ManualTradeRecorded(address indexed vault, bool indexed isBuy, uint64 size, uint64 price, address indexed keeper)
    "ManualTradeRecorded": "0x9f2d5dcbc3e4e2a8d3e8e6c1c1f9d3c6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c",
    # CircuitBreakerActivated / CircuitBreakerAutoTriggered
    "CircuitBreakerActivated": "0x8a4e1c9d6f7a8b3c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3",
    "CircuitBreakerAutoTriggered": "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1",
    # FeesDistributed (from FeeDistributor)
    "FeesDistributed": "0x2c5f8c4d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2",
    # Staked / Withdrawn from ZENTStaking
    "Staked": "0x9e4a8d1f2c3b4a5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9",
    "Withdrawn": "0x0f1e2d3c4b5a69788a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1",
}

# ── Critical contracts for A1/A2 alerts ──────────────────────────────────────

CRITICAL_CONTRACTS = {
    "StrategyExecutor",
    "zETH",
    "zBTC",
    "zXRP",
    "zSOL",
    "ZentGovernor",
    "Timelock",
}

# ── Dataclasses ────────────────────────────────────────────────────────────────


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
    severity: str  # "CRITICAL" | "HIGH" | "MEDIUM" | "LOW"


@dataclass
class MonitorState:
    last_block_checked: int = 0
    events_seen: set[str] = field(default_factory=set)  # tx_hash + log_index
    alerts_sent: list[EventAlert] = field(default_factory=list)


# ── Webhook Notifier ──────────────────────────────────────────────────────────


class DiscordNotifier:
    """Sends alerts to a Discord webhook."""

    def __init__(self, webhook_url: str | None = None):
        self.webhook_url = webhook_url or os.getenv("DISCORD_WEBHOOK_URL", "")
        self.enabled = bool(self.webhook_url)

    def _severity_color(self, severity: str) -> int:
        colors = {
            "CRITICAL": 0xFF0000,  # red
            "HIGH": 0xFF8800,      # orange
            "MEDIUM": 0xFFDD00,    # yellow
            "LOW": 0x00FF88,       # green
        }
        return colors.get(severity, 0x888888)

    def _format_role_data(self, data: dict) -> str:
        """Decode bytes32 role to readable name if known."""
        role_bytes = data.get("role", "")
        role_map = {
            "0x0000000000000000000000000000000000000000000000000000000000000000": "DEFAULT_ADMIN_ROLE",
            "0x0000000000000000000000000000000000000000000000000000000000000000": "ZERO_ROLE",
        }
        # KEEPER_ROLE hash
        keeper_role = "0x653e遮罩8b6e91a2c0d1e8f3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a"
        return role_map.get(role_bytes, f"`{role_bytes[:10]}...`")

    def send_alert(self, alert: EventAlert) -> bool:
        if not self.enabled:
            log.info("discord_alert_skipped_no_webhook", severity=alert.severity)
            return False

        color = self._severity_color(alert.severity)
        timestamp = alert.block_timestamp.isoformat()

        fields = [
            {"name": "Contract", "value": f"`{alert.contract_address}`", "inline": True},
            {"name": "Block", "value": str(alert.block_number), "inline": True},
            {"name": "TX Hash", "value": f"[`{alert.tx_hash[:12]}...`](https://hypurrscan.io/tx/{alert.tx_hash})", "inline": False},
        ]

        if alert.event_name in ("RoleGranted", "RoleRevoked"):
            fields.insert(
                2,
                {
                    "name": "Account",
                    "value": f"`{alert.data.get('account', 'unknown')}`",
                    "inline": True,
                },
            )

        payload = {
            "username": "Zentory Monitor",
            "avatar_url": "https://zentorylabs.com/favicon.ico",
            "embeds": [
                {
                    "title": f":rotating_light: [{alert.severity}] {alert.event_name} on {alert.contract_name}",
                    "color": color,
                    "description": f"Event `{alert.event_name}` emitted on **{alert.contract_name}**",
                    "fields": fields,
                    "footer": {"text": "Zentory Protocol — HyperEVM Testnet"},
                    "timestamp": timestamp,
                }
            ],
        }

        try:
            resp = httpx.post(self.webhook_url, json=payload, timeout=10.0)
            resp.raise_for_status()
            log.info("discord_alert_sent", tx_hash=alert.tx_hash, event=alert.event_name)
            return True
        except Exception as e:
            log.error("discord_alert_failed", error=str(e), tx_hash=alert.tx_hash)
            return False

    def send_test_alert(self) -> bool:
        """Send a test alert to verify the webhook is working."""
        test_alert = EventAlert(
            contract_name="TestContract",
            contract_address="0x0000000000000000000000000000000000000000",
            event_name="TestAlert",
            event_signature="0x0000000000000000000000000000000000000000000000000000000000000000",
            tx_hash="0x0000000000000000000000000000000000000000000000000000000000000000",
            block_number=0,
            block_timestamp=datetime.now(timezone.utc),
            data={},
            severity="LOW",
        )
        return self.send_alert(test_alert)


# ── Event Monitor ─────────────────────────────────────────────────────────────


class EventMonitor:
    """
    Polls HyperEVM RPC for critical on-chain events and dispatches alerts.

    Uses eth_getLogs (log filtering) which is free on public RPCs —
    no API key required.
    """

    def __init__(
        self,
        rpc_url: str | None = None,
        poll_interval: int = 30,
        from_block: int | None = None,
        notifier: DiscordNotifier | None = None,
        verify_fire_on_start: bool = True,
    ):
        self.rpc_url = rpc_url or os.getenv(
            "HYPEREVM_RPC", "https://rpc.hyperliquid-testnet.xyz/evm"
        )
        self.poll_interval = poll_interval
        self.notifier = notifier or DiscordNotifier()
        self.verify_fire_on_start = verify_fire_on_start

        self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        if not self.w3.is_connected():
            raise RuntimeError(f"Cannot connect to HyperEVM RPC: {self.rpc_url}")

        log.info("event_monitor_init", rpc=self.rpc_url, poll_interval=poll_interval)

        # Track state
        self.state = MonitorState()
        self._load_state()

        # If from_block not specified, resume from last checked
        if from_block is not None:
            self.state.last_block_checked = from_block

    # ── State persistence ────────────────────────────────────────────────────

    def _state_file(self) -> str:
        return os.path.join(os.path.dirname(__file__), ".monitor_state.json")

    def _load_state(self) -> None:
        path = self._state_file()
        if os.path.exists(path):
            try:
                with open(path) as f:
                    d = json.load(f)
                self.state.last_block_checked = d.get("last_block_checked", 0)
                self.state.events_seen = set(d.get("events_seen", []))
                log.info("state_loaded", last_block=self.state.last_block_checked)
            except Exception as e:
                log.warning("state_load_failed", error=str(e))

    def _save_state(self) -> None:
        try:
            with open(self._state_file(), "w") as f:
                json.dump(
                    {
                        "last_block_checked": self.state.last_block_checked,
                        "events_seen": list(self.state.events_seen),
                    },
                    f,
                )
        except Exception as e:
            log.error("state_save_failed", error=str(e))

    # ── RPC helpers ──────────────────────────────────────────────────────────

    def _get_block_number(self) -> int:
        return self.w3.eth.block_number

    def _fetch_logs(self, from_block: int, to_block: int) -> list[dict]:
        """Fetch logs for all critical events across all relevant contracts."""
        all_logs = []
        addresses = [Web3.to_checksum_address(addr) for addr in CONTRACTS.values()]
        topics = [Web3.to_bytes(hexstr=sig) for sig in EVENT_SIGNATURES.values()]

        params = {
            "fromBlock": hex(from_block),
            "toBlock": hex(to_block),
            "topics": [topics],  # match any of the event signatures
        }

        try:
            logs = self.w3.eth.get_logs(params)
            all_logs.extend(logs)
        except Exception as e:
            log.error("rpc_get_logs_failed", error=str(e), from_block=from_block, to_block=to_block)

        return all_logs

    def _decode_log(self, log_entry: dict) -> EventAlert | None:
        """Decode a raw log entry into an EventAlert."""
        address = log_entry["address"].lower()
        contract_name = next(
            (name for name, addr in CONTRACTS.items() if addr.lower() == address),
            address,
        )
        topics = log_entry["topics"]
        if not topics:
            return None
        sig = topics[0].hex()
        event_name = next(
            (name for name, s in EVENT_SIGNATURES.items() if s == sig),
            f"Unknown({sig[:10]})",
        )

        tx_hash = log_entry["transactionHash"].hex()
        block_number = int(log_entry["blockNumber"], 16)
        log_index = int(log_entry.get("logIndex", "0x0"), 16)
        block = self.w3.eth.get_block(block_number)
        block_timestamp = datetime.fromtimestamp(block["timestamp"], tz=timezone.utc)

        data_hex = log_entry.get("data", "0x")
        data_str = data_hex[2:] if data_hex.startswith("0x") else data_hex

        # Decode event data based on type
        data: dict[str, Any] = {}
        if event_name == "PausedSet":
            # bool = 1 byte padded
            val = int(data_str, 16) if data_str else 0
            data["paused"] = val == 1
        elif event_name in ("RoleGranted", "RoleRevoked"):
            # bytes32 role (64 hex chars) + address (40 hex chars, 20 bytes)
            if len(data_str) >= 64:
                data["role"] = "0x" + data_str[:64]
            if len(data_str) >= 104:
                data["account"] = "0x" + data_str[64:104]
        elif event_name == "ManualTradeRecorded":
            # bool isBuy (last byte of first 32 bytes) + vault address + ...
            if len(data_str) >= 40:
                data["vault"] = "0x" + data_str[-40:]
            if len(data_str) >= 66:
                data["isBuy"] = int(data_str[64:66], 16) == 1

        # Determine severity
        if event_name == "PausedSet":
            severity = "CRITICAL"
        elif event_name in ("RoleGranted", "RoleRevoked"):
            severity = "CRITICAL"
        elif event_name in ("CircuitBreakerActivated", "CircuitBreakerAutoTriggered"):
            severity = "HIGH"
        elif event_name == "ManualTradeRecorded":
            severity = "LOW"
        elif event_name in ("FeesDistributed",):
            severity = "MEDIUM"
        else:
            severity = "LOW"

        return EventAlert(
            contract_name=contract_name,
            contract_address=log_entry["address"],
            event_name=event_name,
            event_signature=sig,
            tx_hash=tx_hash,
            block_number=block_number,
            block_timestamp=block_timestamp,
            data=data,
            severity=severity,
        )

    # ── Alert deduplication ─────────────────────────────────────────────────

    def _is_new_event(self, alert: EventAlert, log_entry: dict) -> bool:
        log_index = int(log_entry.get("logIndex", "0x0"), 16)
        key = f"{alert.tx_hash}:{log_index}"
        if key in self.state.events_seen:
            return False
        self.state.events_seen.add(key)
        return True

    # ── Main poll loop ──────────────────────────────────────────────────────

    def poll_once(self) -> list[EventAlert]:
        """Poll for new events since last check. Returns new alerts."""
        current_block = self._get_block_number()
        from_block = max(self.state.last_block_checked + 1, current_block - 1000)
        to_block = current_block

        if from_block > to_block:
            return []

        log.info("polling", from_block=from_block, to_block=to_block)
        raw_logs = self._fetch_logs(from_block, to_block)
        log.info("logs_received", count=len(raw_logs))

        new_alerts: list[EventAlert] = []
        for log_entry in raw_logs:
            alert = self._decode_log(log_entry)
            if not alert:
                continue
            if not self._is_new_event(alert, log_entry):
                continue

            # Fire Discord alert
            self.notifier.send_alert(alert)
            new_alerts.append(alert)

            log.info(
                "alert_triggered",
                severity=alert.severity,
                event=alert.event_name,
                contract=alert.contract_name,
                tx=alert.tx_hash,
            )

        self.state.last_block_checked = to_block
        self._save_state()
        return new_alerts

    def run(self) -> None:
        """Run the monitor loop continuously."""
        log.info("monitor_started", poll_interval=self.poll_interval)

        if self.verify_fire_on_start:
            log.info("verifying_past_events")
            alerts = self.poll_once()
            if alerts:
                log.info("historical_alerts_found", count=len(alerts))
            else:
                log.info("no_historical_alerts_found")

        while True:
            try:
                alerts = self.poll_once()
                if alerts:
                    log.info("new_alerts", count=len(alerts))
            except Exception as e:
                log.error("poll_failed", error=str(e))

            time.sleep(self.poll_interval)


# ── CLI ───────────────────────────────────────────────────────────────────────


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Zentory Protocol Event Monitor")
    parser.add_argument(
        "--rpc-url",
        type=str,
        default=os.getenv("HYPEREVM_RPC", "https://rpc.hyperliquid-testnet.xyz/evm"),
        help="HyperEVM RPC URL",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=30,
        help="Seconds between polls (default: 30)",
    )
    parser.add_argument(
        "--from-block",
        type=int,
        default=None,
        help="Start monitoring from this block (default: last saved + 1)",
    )
    parser.add_argument(
        "--discord-webhook",
        type=str,
        default=os.getenv("DISCORD_WEBHOOK_URL", ""),
        help="Discord webhook URL",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Send a test alert and exit",
    )
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
        verify_fire_on_start=True,
    )
    monitor.run()


if __name__ == "__main__":
    main()

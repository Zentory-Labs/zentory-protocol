#!/usr/bin/env python3
"""
Deploy the multi-asset signal network contracts via Foundry ``cast`` CLI.

Usage:
    cd ZentoryToken/engine
    PRIVATE_KEY=0x... python scripts/deploy_signal_network.py

Requirements:
    - foundry (``cast``) installed and in PATH
    - Anvil running locally OR a testnet RPC URL set via HYPEREVM_RPC env var
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).parent.parent.parent  # → ZentoryToken/
DEPLOY_SCRIPT = ROOT / "contracts" / "script" / "DeploySignalNetwork.s.sol"
BROADCAST_DIR = (
    ROOT / "contracts" / "broadcast" / "DeploySignalNetwork.s.sol" / "998"
)
ABI_OUT_DIR = ROOT / "engine" / "src" / "signals" / "abi"


def run_cast(cmd: list[str], check: bool = True) -> str:
    """Run a foundry cast command and return stdout."""
    display = " ".join(cmd[:3])
    print(f"  $ cast {display}...")
    result = subprocess.run(
        ["cast"] + cmd,
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if check and result.returncode != 0:
        print(f"  ERROR: {result.stderr.strip()}")
        sys.exit(1)
    return result.stdout.strip()


def parse_broadcast_manifest(broadcast_file: Path) -> dict[str, str]:
    """
    Read a Foundry broadcast manifest (run-latest.json) and return a mapping
    of contract name → deployed address for CREATE transactions.
    """
    manifest = json.loads(broadcast_file.read_text())
    deployed: dict[str, str] = {}

    for tx in manifest.get("transactions", []):
        tx_type = tx.get("transactionType")
        if tx_type == "CREATE":
            name = tx.get("contractName", "?")
            addr = tx.get("contractAddress", "")
            if addr:
                deployed[name] = addr

    return deployed


def save_abi(contract_name: str, address: str, out_dir: Path) -> None:
    """
    Query the deployed contract's ABI via ``cast abi`` and write it to a JSON file
    alongside the address in a ``.address`` file.
    """
    out_dir.mkdir(parents=True, exist_ok=True)

    # Fetch and write ABI
    abi_json = run_cast(["abi", address], check=True)
    abi_path = out_dir / f"{contract_name}.json"
    try:
        abi_data = json.loads(abi_json)
    except json.JSONDecodeError:
        # cast abi returns raw Solidity ABI text if no EIP-712 interface is found;
        # store it as a raw string list (Cast already outputs JSON for standard ABIs)
        abi_data = abi_json

    abi_path.write_text(json.dumps(abi_data, indent=2))
    print(f"  Saved ABI → {abi_path}")

    # Write address file
    addr_path = out_dir / f"{contract_name}.address"
    addr_path.write_text(address)
    print(f"  Saved address → {addr_path}")


def update_env_file(deployed: dict[str, str], env_file: Path) -> None:
    """Append deployed addresses to the engine .env file."""
    timestamp = datetime.now().isoformat()
    lines = [f"# Signal Network — deployed {timestamp}"]
    for name, addr in deployed.items():
        key = f"SIGNAL_{name.upper().replace(' ', '_').replace('-', '_')}_ADDRESS"
        lines.append(f"{key}={addr}")

    existing = env_file.read_text() if env_file.exists() else ""
    env_file.write_text(existing + "\n" + "\n".join(lines) + "\n")
    print(f"Updated {env_file}")


def main() -> None:
    priv_key = os.getenv("PRIVATE_KEY")
    rpc_url = os.getenv("HYPEREVM_RPC", "https://api.hyperliquid.xyz/evm")

    if not priv_key:
        print("ERROR: PRIVATE_KEY env var not set")
        print("  Usage: PRIVATE_KEY=0x... python scripts/deploy_signal_network.py")
        sys.exit(1)

    print("=" * 60)
    print("Signal Network Deployer")
    print("=" * 60)
    print(f"RPC:       {rpc_url}")
    print(f"Broadcast: {BROADCAST_DIR}")

    # ── Step 1: check if broadcast manifest exists ───────────────────────────
    latest_run = BROADCAST_DIR / "latest" / "run-latest.json"
    if latest_run.exists():
        print(f"\n[1] Found broadcast manifest: {latest_run}")
        deployed = parse_broadcast_manifest(latest_run)
        print(f"    Found {len(deployed)} deployed contracts:")
        for name, addr in deployed.items():
            print(f"      {name}: {addr}")

        # ── Step 2: Save ABIs ───────────────────────────────────────────────
        print(f"\n[2] Saving ABIs to {ABI_OUT_DIR}")
        ABI_OUT_DIR.mkdir(parents=True, exist_ok=True)
        for name, addr in deployed.items():
            save_abi(name, addr, ABI_OUT_DIR)

        # ── Step 3: Update .env ──────────────────────────────────────────────
        env_file = ROOT / "engine" / ".env"
        print(f"\n[3] Updating {env_file}")
        update_env_file(deployed, env_file)

        print("\nDeploy complete.")
        return

    # ── No broadcast — run forge script ─────────────────────────────────────
    print(f"\n[1] No broadcast manifest found at {latest_run}")
    print("    Running forge script...")

    forge_script = ROOT / "contracts" / "script" / "DeploySignalNetwork.s.sol"
    if not forge_script.exists():
        print(f"ERROR: Deploy script not found at {forge_script}")
        print("  Create contracts/script/DeploySignalNetwork.s.sol first.")
        sys.exit(1)

    result = subprocess.run(
        [
            "forge", "script", f"DeploySignalNetwork.s.sol",
            "--rpc-url", rpc_url,
            "--private-key", priv_key,
            "--broadcast",
            "--slow",
        ],
        cwd=str(ROOT / "contracts"),
        capture_output=True,
        text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(f"ERROR: forge script failed:\n{result.stderr}")
        sys.exit(1)

    # Re-parse
    if latest_run.exists():
        deployed = parse_broadcast_manifest(latest_run)
    else:
        print("WARNING: broadcast manifest still not found after forge run.")
        deployed = {}

    if deployed:
        ABI_OUT_DIR.mkdir(parents=True, exist_ok=True)
        for name, addr in deployed.items():
            save_abi(name, addr, ABI_OUT_DIR)

        env_file = ROOT / "engine" / ".env"
        update_env_file(deployed, env_file)

    print("\nDeploy complete.")


if __name__ == "__main__":
    main()

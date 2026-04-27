"""Standalone test: poll for historical PausedSet events using Alchemy."""
import httpx, time

ALCHEMY_URL = "https://hyperliquid-testnet.g.alchemy.com/v2/REDACTED-ALCHEMY-KEY"
PAUSED_SET_SIG = "0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212"
STRATEGY_EXECUTOR = "0x427c94150f3f700Dc2EDf7bCc97155A467E41F21"

def rpc(method, params=None):
    r = httpx.post(ALCHEMY_URL, json={"id":1,"jsonrpc":"2.0","method":method,"params":params or []}, timeout=30)
    data = r.json()
    if "error" in data:
        raise RuntimeError(f"RPC error: {data['error']}")
    return data.get("result")

def get_events_in_blocks(from_block, to_block):
    """Get all logs matching PausedSet across all monitored contracts."""
    # This RPC doesn't support OR topics, so query each block for each contract
    alerts = []
    for block_num in range(from_block, to_block + 1):
        block_hex = hex(block_num)
        block = rpc("eth_getBlockByNumber", [block_hex, True])
        if not block:
            continue
        txs = block.get("transactions") or []
        print(f"Block {block_num}: {len(txs)} txs", flush=True)
        for tx in txs:
            tx_hash = tx if isinstance(tx, str) else tx.get("hash")
            if not tx_hash:
                continue
            try:
                receipt = rpc("eth_getTransactionReceipt", [tx_hash])
            except Exception as e:
                print(f"  receipt error for {tx_hash[:12]}: {e}", flush=True)
                continue
            if not receipt:
                continue
            for log in receipt.get("logs", []):
                if log.get("address", "").lower() != STRATEGY_EXECUTOR.lower():
                    continue
                topics = log.get("topics") or []
                if not topics:
                    continue
                if topics[0] == PAUSED_SET_SIG:
                    data_hex = (log.get("data") or "0x")[2:]
                    paused = int(data_hex, 16) != 0 if data_hex else True
                    print(f"  *** FOUND PausedSet({paused}) in tx {tx_hash}")
                    alerts.append({"tx": tx_hash, "block": block_num, "paused": paused})
            time.sleep(0.1)
    return alerts

# Scan blocks around our events: 51978896 (pause) and 51978957 (unpause)
print("Scanning blocks 51978894 to 51978960...")
events = get_events_in_blocks(51978894, 51978960)
print(f"\nTotal events found: {len(events)}")
for e in events:
    print(f"  tx={e['tx']}, block={e['block']}, paused={e['paused']}")

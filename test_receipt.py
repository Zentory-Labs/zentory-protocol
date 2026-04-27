import httpx, time

url = 'https://hyperliquid-testnet.g.alchemy.com/v2/REDACTED-ALCHEMY-KEY'

def rpc(method, params=None):
    r = httpx.post(url, json={'id':1,'jsonrpc':'2.0','method':method,'params':params or []}, timeout=30)
    return r.json().get('result')

# Check current block
current = int(rpc('eth_blockNumber'), 16)
print(f'Current block: {current}')

# Get block 51978896 (our pause event)
block = rpc('eth_getBlockByNumber', ['0x' + hex(51978896)[2:].zfill(8), True])
print(f'Block 51978896 txs: {len(block.get("transactions", []))}')
for tx in block.get('transactions', []):
    tx_hash = tx if isinstance(tx, str) else tx.get('hash')
    print(f'  tx: {tx_hash}')

# Get receipt for our pause tx
receipt = rpc('eth_getTransactionReceipt', ['0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56'])
print(f'Receipt status: {receipt.get("status")}')
print(f'Logs: {len(receipt.get("logs", []))}')
for log in receipt.get('logs', []):
    topics = [t for t in log.get('topics', [])]
    if topics:
        print(f'  topic[0]: {topics[0]}')
        print(f'  address: {log.get("address")}')

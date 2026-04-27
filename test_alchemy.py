import httpx

url = 'https://hyperliquid-testnet.g.alchemy.com/v2/REDACTED-ALCHEMY-KEY'
headers = {'content-type': 'application/json'}

# Test with no address filter, just event sig
payload = {
    'jsonrpc': '2.0', 'id': 1, 'method': 'eth_getLogs',
    'params': [{
        'fromBlock': '0x317db90',  # 51978896
        'toBlock': '0x317dbd5',    # 51978957
        'topics': ['0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212']
    }]
}
r = httpx.post(url, json=payload, headers=headers, timeout=30)
data = r.json()
result = data.get('result', [])
print(f'Alchemy (no address filter): {len(result)} logs')
for log in result:
    print(f'  block: {int(log["blockNumber"],16)}, addr: {log["address"]}, tx: {log["transactionHash"]}')

# Also test Alchemy blockNumber
bn = httpx.post(url, json={'id':1,'jsonrpc':'2.0','method':'eth_blockNumber'}, timeout=10).json()
print(f'Alchemy current block: {int(bn["result"], 16)}')

# Test Alchemy trace / getReceipts for our tx
receipt = httpx.post(url, json={'id':1,'jsonrpc':'2.0','method':'eth_getTransactionReceipt','params':['0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56']}, timeout=15).json()
r_result = receipt.get('result', {})
print(f'Alchemy getTransactionReceipt for our tx:')
print(f'  status: {r_result.get("status")}')
print(f'  logs count: {len(r_result.get("logs", []))}')
for log in r_result.get('logs', []):
    if log.get('topics'):
        print(f'  log topics[0]: {log["topics"][0]}')

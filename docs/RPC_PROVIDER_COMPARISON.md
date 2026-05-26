# RPC provider comparison (M6)

Picking the paid RPC tier for ZENTORY's mainnet keeper, indexer, and
dApp. Public HyperEVM RPC is unreliable at any real volume — keeper missing
an epoch settlement because of rate-limit is a real failure mode.

---

## The workload to plan for

| Service | Calls/day | Burstiness |
|---|---|---|
| Keeper settler (cron 4h) | ~200 RPC calls per run × 6 runs = ~1,200/day | Burst at cron fire |
| Heartbeat (cron 30m) | ~10 calls per run × 48 = ~500/day | Very smooth |
| Indexer (cron 15m, eth_getLogs) | ~50 calls per run × 96 = ~5,000/day | Burst at cron fire |
| dApp reads (wagmi useReadContract) | grows with users — assume 100 daily users × ~50 reads each = ~5,000/day at small TVL | Smooth, follows traffic |
| dApp writes (deposit, withdraw, etc.) | low — ~50/day at small TVL | Spiky around marketing events |
| **Total at small TVL** | **~12,000 calls/day** | |
| **Total at $10M TVL with 1,000 users** | **~50,000 calls/day** | |
| **Total at $100M TVL** | **~500,000+ calls/day** | |

All providers below comfortably handle the small-TVL load on their
**Growth/Pro** tier (~$50/mo). The $10M TVL load needs the **Scale** tier
(~$100–200/mo). Plan to upgrade once at $10M.

---

## Provider comparison for HyperEVM specifically

⚠️ **Important caveat:** as of May 2026, the major RPC infrastructure
providers (Alchemy, Infura, QuickNode) **do not yet have HyperEVM in
their standard catalog**. They support most major EVM chains but
HyperEVM is too new.

Options:

### 1. Hyperliquid public RPC (free, current)

URL: `https://rpc.hyperliquid-testnet.xyz/evm`
URL: `https://rpc.hyperliquid.xyz/evm` (mainnet)

- **Cost:** Free
- **Reliability:** Generally OK but no SLA, periodic rate limits, no support
- **Best for:** Testnet, low-volume dev
- **Risk:** Outage = your dApp + keeper down with no recourse

### 2. QuickNode Custom HyperEVM Node (recommended)

QuickNode supports adding custom chains via their "Custom Chains" feature
for paying customers. Send them a support ticket asking for a dedicated
HyperEVM endpoint.

- **Cost:** ~$50–200/mo (Build → Scale tier)
- **Reliability:** 99.99% SLA, dedicated endpoint URL
- **Best for:** Production keeper + indexer + dApp
- **Setup:** Email support@quicknode.com explaining you need a HyperEVM
  endpoint; they typically respond in 24-48h
- **Contact:** https://www.quicknode.com/contact

### 3. Self-hosted HyperEVM full node (most control, most ops)

Run our own HyperEVM node on a Hetzner CCX42 / CCX52 (~$30–60/mo).

- **Cost:** $30–60/mo VPS + ~5–10 hr/mo ops time
- **Reliability:** Depends entirely on us — single point of failure unless
  we run 2 nodes
- **Best for:** Cost-conscious teams who are happy doing devops
- **Setup:** Follow Hyperliquid's node deploy guide; ~2 days to bootstrap
  + sync the chain

### 4. Drpc.org HyperEVM endpoint

Drpc is a community RPC aggregator that has started supporting newer
chains faster than the big providers. As of May 2026 their HyperEVM
support is "beta" — usable but no SLA.

- **Cost:** Free up to 100k req/day, then ~$20–80/mo
- **Reliability:** Decent for community traffic, not production-grade
- **Best for:** Backup / fallback in a multi-RPC setup

### 5. Ankr HyperEVM (check at launch)

Ankr is rolling out HyperEVM support per their public roadmap. Worth
checking at mainnet launch — they're typically the cheapest of the
"real" providers.

- **Cost:** $30–100/mo
- **Reliability:** Good for major chains, unknown for HyperEVM yet

---

## Recommended setup

**Use a multi-provider fallback configuration.** Not one paid endpoint
+ hoping — two providers, automatic failover, written in viem.

```typescript
// lib/rpc.ts (conceptual — implement in dApp Providers and keeper config)
const transports = [
  http("https://<your-quicknode-endpoint>"),         // primary
  http("https://rpc.hyperliquid.xyz/evm"),           // fallback to public
  http("https://lb.drpc.org/ogrpc?network=hyperliquid"), // second fallback
];

export const transport = fallback(transports, {
  rank: { interval: 60_000 },  // re-rank endpoints every 60s by latency
  retryCount: 3,
});
```

Cost: **~$50/mo for QuickNode + free fallbacks = $50/mo, no SLA gap.**

## Migration plan

1. **Today (testnet):** keep using public RPC. It's free and "good enough"
   for testnet load.
2. **At audit kickoff:** contact QuickNode support to provision a HyperEVM
   testnet endpoint as a rehearsal. Verify the keeper + indexer work
   against it from Railway.
3. **At mainnet deploy:** provision the mainnet endpoint. Migrate the dApp,
   keeper, and indexer to it via env var. Keep public RPC as a fallback
   transport so a QuickNode outage doesn't take down the protocol.

## What I need from you to move forward

1. **Decision:** QuickNode (cleanest) vs self-host on Hetzner (cheapest)
2. **Budget approval:** $50/mo for the smallest tier, scaling to ~$200 at $10M TVL
3. **Email QuickNode support** at audit kickoff to start the HyperEVM endpoint
   provisioning conversation — typical lead time is 1–2 weeks

---

*Last updated: 2026-05-25. Tracked as task #98 (M6).*

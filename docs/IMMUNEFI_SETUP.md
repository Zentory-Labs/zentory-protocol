# Immunefi Bug Bounty Setup Guide

## Step 1: Create Immunefi Account

1. Go to [https://immunefi.com](https://immunefi.com) and create a project
2. Verify ownership of the repository via GitHub integration
3. Add your smart contracts (list in scope below)

## Step 2: Configure Rewards

Set rewards based on the severity table:

| Severity | Reward |
|----------|--------|
| Critical | Up to $25,000 USDC |
| High     | Up to $10,000 USDC |
| Medium   | Up to $3,000 USDC |
| Low      | Up to $500 USDC |

Most projects start at the lower end of the range and increase after the first audit passes with no critical findings.

## Step 3: Add Your Contracts

For each contract:

- **Source code URL:** `https://github.com/Zentory-Labs/zentory-protocol/blob/main/contracts/src/<CONTRACT>.sol`
- **Deployment address:** TBD — add after mainnet deployment
- **Chain:** HyperEVM (Chain ID: 998 for testnet, TBD for mainnet)

### In-Scope Contracts

```
contracts/src/
  ZENT.sol
  ZENTStaking.sol
  FeeDistributor.sol
  ProtocolTreasury.sol
  ZENTBuyback.sol
  SignalRegistry.sol
  EpochScoring.sol
  BaseVault.sol
  SubscriptionVault.sol
```

### Out-of-Scope

- Frontend bugs
- Social engineering attacks
- DDOS attacks
- Smart contract bugs in third-party dependencies

## Step 4: Publish & Promote

- Publish the bug bounty program on Immunefi
- Add a link from the ZENTORY website footer (navigate to `/bug-bounty`)
- Announce on Discord (#security channel) and Twitter/X

## Step 5: Triage Process

1. Security team reviews within **24 hours**
2. Severity assessed within **7 days**
3. Fix deployed + reward within **30 days** for critical bugs

## Budget Recommendation

Set aside **$50,000–$100,000** for bug bounty payouts in year 1.

Critical bugs in DeFi can cost $10M+ — see Euler Finance 2023: $197M exploit. A proactive bug bounty is dramatically cheaper than a post-exploit response.

## Quick Links

- Immunefi: https://immunefi.com
- ZENTORY Bug Bounty Page: https://zentorytoken.xyz/bug-bounty
- Security Contact: security@zentorylabs.com
- GitHub Repo: https://github.com/Zentory-Labs/zentory-protocol

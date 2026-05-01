# ZENTORY Labs Referral Program Design

## Overview

The ZENTORY Labs Referral Program is a multi-channel growth mechanism that rewards users for bringing new participants into the protocol across three product lines: Alpha Vault, Research Network, and ZENT Token. The program uses a tiered reward structure where active referrers earn escalating ZENT incentives and perks, enabling organic network effects to compound faster than paid acquisition channels while keeping reward economics predictable and anti-gaming controls robust.

## Program Mechanics

### Tier Structure

Referrers earn based on the tier they reach:

| Tier | Requirements | Reward per Referral |
|------|---|---|
| Bronze | 0–2 successful referrals | 5 ZENT |
| Silver | 3–9 referrals | 10 ZENT |
| Gold | 10–24 referrals | 20 ZENT + 1% vault fee discount |
| Platinum | 25+ referrals | 50 ZENT + 0.5% vault fee discount + early access |

### Reward Mechanics

#### For Vault Referrals
- Referee deposits $X in vault assets
- Referrer earns: 5 ZENT (Bronze) → 50 ZENT (Platinum)
- Referee earns: 50 ZENT sign-on bonus (for deposits ≥ $500 equivalent)

#### For Research Referrals
- Referee subscribes to any paid tier
- Referrer earns: 1 month free ZENT subscription credit
- Referee earns: 20 ZENT credit toward first subscription

#### For ZENT Token Referrals
- Referee buys ≥ 100 ZENT
- Referrer earns: 1 ZENT per 10 ZENT bought (0.1 ZENT per ZENT)
- Referee earns: nothing (price neutral)

### Reward Distribution
- Vault referral rewards: paid out in ZENT at epoch settlement
- Research referral rewards: credited immediately to ZENT subscription balance
- ZENT purchase referral rewards: paid out in ZENT after 30-day lock (anti-fraud)

## Anti-Gaming Rules

1. **Self-referral is prohibited** — same wallet/SoulBound NFT = no reward
2. **Wash trading is prohibited** — depositing and immediately withdrawing = no reward
3. **Fake accounts are prohibited** — multi-account detection via on-chain behavior analysis
4. **Referral code is non-transferable** — cannot sell referral codes
5. **One referral code per user** — cannot create multiple codes to accumulate tier faster

## Program Governance

- Minimum referral amount: $50 equivalent (to prevent spam)
- Maximum reward per referral: 500 ZENT (anti-abuse cap)
- Program can be modified with 30-day notice
- ZENTORY Labs can terminate abusive accounts

## Technical Implementation

### On-Chain Referral Tracking

Use Supabase for referral tracking:

```sql
CREATE TABLE public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer TEXT NOT NULL,  -- wallet address
  referee TEXT NOT NULL,   -- wallet address
  referral_type TEXT NOT NULL CHECK (referral_type IN ('vault', 'research', 'token')),
  referral_code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'rejected')),
  referee_deposit_usd NUMERIC,  -- for vault referrals
  reward_paid_zent NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activated_at TIMESTAMPTZ
);
```

### Referral Code Generation

Referral codes are deterministic:
```
keccak256(abi.encode(referrer_address, block.timestamp))[:8]
```

### Smart Contract Integration

No changes to vault contracts needed — referral rewards are distributed from the ZENT treasury (not from vault funds).

## Timeline

- v1 (MVP): Supabase referral tracking + manual ZENT payout
- v2: On-chain referral tracking + automatic ZENT payout via keeper
- v3: SoulBound NFTs for tier badges + governance-gated referral pools

## Budget

| Year 1 | Calculation |
|---|---|
| Target: 1,000 active referrers | |
| Avg 5 referrals each = 5,000 new users | |
| At 50 ZENT/referral average = 250,000 ZENT rewards | |
| At $0.50/ZENT = $125,000 opportunity cost | |
| Plus engineering: 2 weeks dev time | |

## Legal Notes

- Referral rewards are taxable in most jurisdictions (reward = income)
- We must say "rewards are for informational purposes only" in program terms
- EU users have additional restrictions on promotional incentives (see EU Digital Services Act)
- US users: referral rewards >$600 require 1099 (consult a tax professional)

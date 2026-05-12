# ZENTORY Labs — Monitoring & Runbook

## Uptime Monitoring (UptimeRobot — Free Tier)

### Setup
1. Sign up at https://uptimerobot.com (free tier: 50 monitors)
2. Add the following monitors:

| Monitor Name | URL | Interval | Alert Contact |
|---|---|---|---|
| zentorylabs.com | https://zentorylabs.com | 60s | Email + Discord |
| app.zentorylabs.com | https://app.zentorylabs.com | 60s | Email + Discord |
| Supabase API | https://kwofgotuirdnolaktoznor.supabase.co | 120s | Email |

### Alert Response Runbook

#### app.zentorylabs.com DOWN
1. Check Vercel dashboard: https://vercel.com/edgeza/zentorytoken
2. Check Vercel deployment logs for the latest deploy
3. Check GitHub Actions: https://github.com/Zentory-Labs/zentory-protocol/actions
4. If Vercel error: check build logs, fix, push
5. If CI failure: fix tests, push

#### zentorylabs.com DOWN
1. Check Vercel dashboard for zentorylabs.com
2. Check GitHub Actions: https://github.com/edgeza/Zentorylabs.com/actions

#### Supabase DOWN
1. Check Supabase status: https://status.supabase.com
2. Check Supabase project dashboard
3. If prolonged outage (>5 min): activate incident response

## Keeper Heartbeat Monitoring

The keeper runs a heartbeat to `keeper_heartbeats` Supabase table on every epoch settlement.

A Vercel Cron job checks the heartbeat every 30 minutes (`api/cron/heartbeat`):
- If no heartbeat within 5 hours → status = 'missed_heartbeat' + Discord alert
- If 3+ consecutive misses → status = 'failed' + CRITICAL Discord alert

The keeper calls `update_keeper_heartbeat()` RPC after every successful epoch settlement (including empty epochs), which resets its `missed_heartbeats` counter to 0.

Alert contact: Discord webhook (configure in keeper environment via `DISCORD_WEBHOOK_URL`)

### Keeper Dead Man's Switch Table

| Column | Type | Description |
|---|---|---|
| `keeper_address` | TEXT | Keeper Ethereum address (UNIQUE) |
| `last_heartbeat` | TIMESTAMPTZ | Last time keeper checked in |
| `last_epoch_settled` | BIGINT | Most recent epoch number settled |
| `status` | TEXT | 'active' \| 'missed_heartbeat' \| 'failed' \| 'recovered' |
| `missed_heartbeats` | INTEGER | Consecutive missed heartbeat count |
| `updated_at` | TIMESTAMPTZ | Last row update time |

### Useful Queries

```sql
-- Check keeper status
SELECT * FROM keeper_heartbeats WHERE keeper_address = '0x0dF78A7dFb84F93E0BC6500AA90a27617aF89dDA';

-- Is keeper alive (within 5 hours)?
SELECT is_keeper_alive('0x0dF78A7dFb84F93E0BC6500AA90a27617aF89dDA');
```

## Contract Event Monitoring

Monitor these events on HyperEVM (chain 998):
- `SignalSubmitted` — new research submissions
- `EpochSettled` — epoch completed
- `SubscriptionActivated` — new subscriber
- `VaultDeposited` — new vault deposit

Tools:
- HyperEVM testnet explorer: https://testnet.hyperliquid.xyz/
- AlchemyNFT event monitoring (or similar)

## Alert Contacts

- Primary: Juan (email/phone via UptimeRobot)
- Discord: [your Discord webhook URL]

/**
 * Keeper Heartbeat Script — Dead Man's Switch
 * Run this every 30 minutes via cron or Vercel Cron
 *
 * If the keeper misses 3 consecutive heartbeats:
 * 1. Update status to 'failed'
 * 2. Send Discord alert
 *
 * Usage: npx ts-node src/heartbeat.ts
 */

import * as dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

// Node 20+ exposes `fetch` as a global. We deliberately do NOT depend on
// node-fetch — keeps the dep tree smaller and avoids ESM/CJS interop pain.

dotenv.config();

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const KEEPER_ADDRESS = process.env.KEEPER_ADDRESS!.toLowerCase();
const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL; // optional
const HEARTBEAT_INTERVAL_HOURS = 5; // Alert if no heartbeat in 5 hours

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function checkKeeperHeartbeat() {
  console.log(`[${new Date().toISOString()}] Checking keeper heartbeat for ${KEEPER_ADDRESS}...`);

  const { data: keepers, error } = await supabase
    .from('keeper_heartbeats')
    .select('*')
    .eq('keeper_address', KEEPER_ADDRESS.toLowerCase())
    .order('updated_at', { ascending: false })
    .limit(1);

  if (error) {
    console.error('Supabase error:', error);
    return;
  }

  const lastHeartbeat = keepers?.[0];

  if (!lastHeartbeat) {
    console.log('No heartbeat record found. Keeper may not be registered.');
    // Try to insert initial record
    await supabase.from('keeper_heartbeats').insert({
      keeper_address: KEEPER_ADDRESS.toLowerCase(),
      status: 'missed_heartbeat',
      missed_heartbeats: 1,
    });
    await sendAlert('Keeper not registered — no heartbeat record found');
    return;
  }

  const lastSeen = new Date(lastHeartbeat.last_heartbeat);
  const hoursSince = (Date.now() - lastSeen.getTime()) / (1000 * 60 * 60);

  if (hoursSince > HEARTBEAT_INTERVAL_HOURS) {
    const missedCount = (lastHeartbeat.missed_heartbeats ?? 0) + 1;
    console.warn(`Keeper missed heartbeat! Last seen ${hoursSince.toFixed(1)} hours ago. Missed count: ${missedCount}`);

    const newStatus = missedCount >= 3 ? 'failed' : 'missed_heartbeat';

    await supabase
      .from('keeper_heartbeats')
      .update({
        status: newStatus,
        missed_heartbeats: missedCount,
        updated_at: new Date().toISOString(),
      })
      .eq('id', lastHeartbeat.id);

    if (missedCount >= 3) {
      await sendAlert(
        `CRITICAL: Keeper failed! Missed ${missedCount} consecutive heartbeats. Last epoch settled: ${lastHeartbeat.last_epoch_settled}. Immediate intervention required.`
      );
    } else {
      await sendAlert(
        `Keeper missed heartbeat #${missedCount}. Last seen ${hoursSince.toFixed(1)} hours ago.`
      );
    }
  } else {
    console.log(`Keeper is healthy. Last heartbeat ${hoursSince.toFixed(1)} hours ago.`);
    // Mark as active/recovered if it was previously missed
    if (lastHeartbeat.status !== 'active') {
      await supabase
        .from('keeper_heartbeats')
        .update({ status: 'recovered', updated_at: new Date().toISOString() })
        .eq('id', lastHeartbeat.id);
    }
  }
}

async function sendAlert(message: string) {
  console.error(`ALERT: ${message}`);

  if (DISCORD_WEBHOOK_URL) {
    try {
      await fetch(DISCORD_WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          content: `\`[ZENTORY KEEPER]\` ${message}`,
          components: [
            {
              type: 1,
              components: [
                {
                  type: 2,
                  style: 4,
                  label: 'View UptimeRobot',
                  url: 'https://uptimerobot.com/dashboard',
                },
              ],
            },
          ],
        }),
      });
    } catch (e) {
      console.error('Failed to send Discord alert:', e);
    }
  }
}

checkKeeperHeartbeat().catch(console.error);

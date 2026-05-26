import {
  checkEpochReady,
  settleEpoch as chainSettleEpoch,
  setAccuracy,
  applyPayout,
  getCurrentEpochId,
  getLastEpochStart,
  isEpochSettled,
  getPublicClient,
  signalIdToHex,
} from './chain';
import {
  getActiveSignalsForEpoch,
  insertEpochHistory,
  updateProviderStats,
  insertSignalScore,
  insertAuditLog,
  markSignalsAsResolved,
  updateKeeperHeartbeat,
} from './supabase';
import { computeAccuracy, fetchCryptoPrice, batchFetchPrices } from './scoring';
import { AccuracyResult, PayoutResult } from './types';

const LOG_PREFIX = `[${new Date().toISOString()}] [keeper]`;

interface SettleResult {
  epochId: number;
  totalSignals: number;
  settledSignals: number;
  failedSignals: number;
  avgAccuracyBps: number;
  settleTx: string;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForTransaction(hash: string, timeoutMs = 60000): Promise<boolean> {
  const client = getPublicClient();
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const receipt = await client.getTransactionReceipt({ hash: hash as `0x${string}` });
    if (receipt) {
      return receipt.status === 'success';
    }
    await sleep(2000);
  }
  return false;
}

async function processSignal(
  signal: { id: string; provider: string; assetId: string; direction: number; submittedAt: number; expiresAt: number },
  endTime: number,
  epochId: number
): Promise<{ accuracyResult?: AccuracyResult; payoutResult?: PayoutResult; error?: string }> {
  const signalIdHex = signalIdToHex(signal.id);

  // Check if already settled
  try {
    const settled = await isEpochSettled(BigInt(epochId));
    if (settled) {
      return { error: 'epoch already settled' };
    }
  } catch (e) {
    console.warn(`${LOG_PREFIX} Could not check settlement status: ${(e as Error).message}`);
  }

  // Check if signal is expired
  if (signal.expiresAt < endTime) {
    console.log(`${LOG_PREFIX} Signal ${signal.id} is expired (expiresAt: ${signal.expiresAt} < endTime: ${endTime}), skipping`);
    return { error: 'signal expired' };
  }

  try {
    // Fetch prices
    const [submissionPrice, settlementPrice] = await Promise.all([
      fetchCryptoPrice(signal.assetId, signal.submittedAt),
      fetchCryptoPrice(signal.assetId, endTime),
    ]);

    // Compute accuracy
    const accuracyResult = await computeAccuracy(
      {
        ...signal,
        submittedAt: signal.submittedAt,
        expiresAt: signal.expiresAt,
        status: 'Active',
        confidence: 0,
        assetClass: '',
      },
      settlementPrice,
      submissionPrice
    );

    console.log(
      `${LOG_PREFIX} Signal ${signal.id}: direction=${signal.direction}, ` +
      `priceChange=${accuracyResult.priceChangeBps}bps, accuracy=${accuracyResult.accuracyBps}bps`
    );

    // Set accuracy on-chain
    const accuracyTx = await setAccuracy(signalIdHex, accuracyResult.accuracyBps);
    const accuracyConfirmed = await waitForTransaction(accuracyTx);
    if (!accuracyConfirmed) {
      console.warn(`${LOG_PREFIX} setAccuracy tx not confirmed for ${signal.id}: ${accuracyTx}`);
    }

    // Apply payout on-chain
    const payoutResult = await applyPayout(signalIdHex);
    if (!payoutResult.success) {
      console.error(`${LOG_PREFIX} applyPayout failed for ${signal.id}: ${payoutResult.error}`);
    }

    // Persist to Supabase
    try {
      await insertSignalScore(
        signal.id,
        epochId,
        accuracyResult.accuracyBps,
        payoutResult.success ? payoutResult.payoutZent.toString() : '0'
      );
      await updateProviderStats(
        signal.provider,
        epochId,
        accuracyResult.accuracyBps,
        payoutResult.success ? payoutResult.payoutZent : 0n
      );
    } catch (dbError) {
      console.error(`${LOG_PREFIX} Failed to persist scores to Supabase: ${(dbError as Error).message}`);
    }

    return { accuracyResult, payoutResult };
  } catch (error) {
    const err = error as Error;
    console.error(`${LOG_PREFIX} Error processing signal ${signal.id}: ${err.message}`);
    return { error: err.message };
  }
}

async function main(): Promise<SettleResult> {
  console.log(`${LOG_PREFIX} Keeper starting...`);

  // F-03: assert the RPC actually serves chain 998 before any writes.
  // Catches misconfigured RPC URLs that would otherwise sign mainnet txns
  // with the keeper's testnet authorization. Bails out loud if mismatched.
  const { assertChainId } = await import('./chain');
  await assertChainId();
  console.log(`${LOG_PREFIX} Chain ID verified: 998`);

  // Verify keeper is authorized
  try {
    const oracle = await import('./chain').then((m) => m.getScoringOracle());
    console.log(`${LOG_PREFIX} Scoring oracle: ${oracle}`);
  } catch (e) {
    console.warn(`${LOG_PREFIX} Could not verify scoring oracle: ${(e as Error).message}`);
  }

  // Step 1: Check if epoch is ready
  let ready = false;
  try {
    ready = await checkEpochReady();
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to check epoch readiness: ${(e as Error).message}`);
    throw e;
  }

  if (!ready) {
    console.log(`${LOG_PREFIX} Epoch not ready yet, skipping this run.`);
    throw new Error('EPOCH_NOT_READY');
  }

  console.log(`${LOG_PREFIX} Epoch is ready, beginning settlement...`);

  // Step 2: Get epoch timing
  const currentEpochId = await getCurrentEpochId();
  const lastEpochStart = await getLastEpochStart();
  const endTime = Math.floor(Date.now() / 1000);
  const startTime = Number(lastEpochStart);
  const epochId = Number(currentEpochId);

  console.log(
    `${LOG_PREFIX} Settling epoch ${epochId} (window: ${startTime} → ${endTime}, ` +
    `duration: ${endTime - startTime}s)`
  );

  // Step 3: Get all active signals in this epoch window
  let signals: Awaited<ReturnType<typeof getActiveSignalsForEpoch>> = [];
  try {
    signals = await getActiveSignalsForEpoch(startTime, endTime);
    console.log(`${LOG_PREFIX} Found ${signals.length} active signals in epoch window`);
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to fetch signals from Supabase: ${(e as Error).message}`);
    throw e;
  }

  let settledSignals = 0;
  let failedSignals = 0;
  const accuracyResults: AccuracyResult[] = [];

  if (signals.length === 0) {
    console.log(`${LOG_PREFIX} No signals to score, settling empty epoch...`);
    try {
      const settleTx = await chainSettleEpoch();
      console.log(`${LOG_PREFIX} Empty epoch settled: ${settleTx}`);
      // Fire heartbeat for empty epoch too
      try {
        await updateKeeperHeartbeat(epochId);
      } catch (e) {
        console.error(`${LOG_PREFIX} Failed to update keeper heartbeat: ${(e as Error).message}`);
      }
      return { epochId, totalSignals: 0, settledSignals: 0, failedSignals: 0, avgAccuracyBps: 0, settleTx };
    } catch (e) {
      console.error(`${LOG_PREFIX} Failed to settle empty epoch: ${(e as Error).message}`);
      throw e;
    }
  }

  // Step 4: Process each signal
  for (const signal of signals) {
    console.log(`${LOG_PREFIX} Processing signal ${signal.id} (provider: ${signal.provider})`);

    const result = await processSignal(signal, endTime, epochId);

    if (result.accuracyResult) {
      accuracyResults.push(result.accuracyResult);
      settledSignals++;
    } else {
      failedSignals++;
    }

    // Small delay between signals to avoid rate limiting
    await sleep(500);
  }

  // Step 5: Settle epoch on-chain
  console.log(`${LOG_PREFIX} Settling epoch on-chain...`);
  let settleTx = '';
  try {
    settleTx = await chainSettleEpoch();
    const confirmed = await waitForTransaction(settleTx);
    if (!confirmed) {
      console.warn(`${LOG_PREFIX} settleEpoch tx not confirmed: ${settleTx}`);
    }
    console.log(`${LOG_PREFIX} Epoch settled on-chain: ${settleTx}`);
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to settle epoch: ${(e as Error).message}`);
    throw e;
  }

  // Step 6: Update epoch history in Supabase
  const avgAccuracyBps =
    accuracyResults.length > 0
      ? Math.round(accuracyResults.reduce((sum, r) => sum + r.accuracyBps, 0) / accuracyResults.length)
      : 0;

  try {
    await insertEpochHistory({
      epoch_id: epochId,
      start_time: startTime,
      end_time: endTime,
      total_signals: signals.length,
      settled_signals: settledSignals,
      avg_accuracy_bps: avgAccuracyBps,
    });
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to insert epoch history: ${(e as Error).message}`);
  }

  // Step 7: Mark signals as resolved
  try {
    await markSignalsAsResolved(signals.map((s) => s.id));
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to mark signals as resolved: ${(e as Error).message}`);
  }

  // Step 8: Audit log
  try {
    await insertAuditLog('keeper', 'epoch_settle', {
      epochId,
      totalSignals: signals.length,
      settledSignals,
      failedSignals,
      avgAccuracyBps,
      settleTx,
    });
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to insert audit log: ${(e as Error).message}`);
  }

  // Step 9: Update keeper heartbeat (dead man's switch)
  try {
    await updateKeeperHeartbeat(epochId);
    console.log(`${LOG_PREFIX} Keeper heartbeat updated for epoch ${epochId}`);
  } catch (e) {
    console.error(`${LOG_PREFIX} Failed to update keeper heartbeat: ${(e as Error).message}`);
  }

  console.log(
    `${LOG_PREFIX} Keeper finished. Epoch ${epochId}: ${settledSignals}/${signals.length} signals settled, ` +
    `avg accuracy: ${avgAccuracyBps}bps`
  );

  return {
    epochId,
    totalSignals: signals.length,
    settledSignals,
    failedSignals,
    avgAccuracyBps,
    settleTx,
  };
}

// Run as standalone script
main()
  .then((result) => {
    console.log(JSON.stringify({ status: 'success', ...result }));
    process.exit(0);
  })
  .catch((error) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error(JSON.stringify({ status: 'error', error: message }));
    process.exit(1);
  });

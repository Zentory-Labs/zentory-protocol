"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const chain_1 = require("./chain");
const supabase_1 = require("./supabase");
const scoring_1 = require("./scoring");
const LOG_PREFIX = `[${new Date().toISOString()}] [keeper]`;
async function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
async function waitForTransaction(hash, timeoutMs = 60000) {
    const client = (0, chain_1.getPublicClient)();
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const receipt = await client.getTransactionReceipt({ hash: hash });
        if (receipt) {
            return receipt.status === 'success';
        }
        await sleep(2000);
    }
    return false;
}
async function processSignal(signal, endTime, epochId) {
    const signalIdHex = (0, chain_1.signalIdToHex)(signal.id);
    // Check if already settled
    try {
        const settled = await (0, chain_1.isEpochSettled)(BigInt(epochId));
        if (settled) {
            return { error: 'epoch already settled' };
        }
    }
    catch (e) {
        console.warn(`${LOG_PREFIX} Could not check settlement status: ${e.message}`);
    }
    // Check if signal is expired
    if (signal.expiresAt < endTime) {
        console.log(`${LOG_PREFIX} Signal ${signal.id} is expired (expiresAt: ${signal.expiresAt} < endTime: ${endTime}), skipping`);
        return { error: 'signal expired' };
    }
    try {
        // Fetch prices
        const [submissionPrice, settlementPrice] = await Promise.all([
            (0, scoring_1.fetchCryptoPrice)(signal.assetId, signal.submittedAt),
            (0, scoring_1.fetchCryptoPrice)(signal.assetId, endTime),
        ]);
        // Compute accuracy
        const accuracyResult = await (0, scoring_1.computeAccuracy)({
            ...signal,
            submittedAt: signal.submittedAt,
            expiresAt: signal.expiresAt,
            status: 'Active',
            confidence: 0,
            assetClass: '',
        }, settlementPrice, submissionPrice);
        console.log(`${LOG_PREFIX} Signal ${signal.id}: direction=${signal.direction}, ` +
            `priceChange=${accuracyResult.priceChangeBps}bps, accuracy=${accuracyResult.accuracyBps}bps`);
        // Set accuracy on-chain
        const accuracyTx = await (0, chain_1.setAccuracy)(signalIdHex, accuracyResult.accuracyBps);
        const accuracyConfirmed = await waitForTransaction(accuracyTx);
        if (!accuracyConfirmed) {
            console.warn(`${LOG_PREFIX} setAccuracy tx not confirmed for ${signal.id}: ${accuracyTx}`);
        }
        // Apply payout on-chain
        const payoutResult = await (0, chain_1.applyPayout)(signalIdHex);
        if (!payoutResult.success) {
            console.error(`${LOG_PREFIX} applyPayout failed for ${signal.id}: ${payoutResult.error}`);
        }
        // Persist to Supabase
        try {
            await (0, supabase_1.insertSignalScore)(signal.id, epochId, accuracyResult.accuracyBps, payoutResult.success ? payoutResult.payoutZent.toString() : '0');
            await (0, supabase_1.updateProviderStats)(signal.provider, epochId, accuracyResult.accuracyBps, payoutResult.success ? payoutResult.payoutZent : 0n);
        }
        catch (dbError) {
            console.error(`${LOG_PREFIX} Failed to persist scores to Supabase: ${dbError.message}`);
        }
        return { accuracyResult, payoutResult };
    }
    catch (error) {
        const err = error;
        console.error(`${LOG_PREFIX} Error processing signal ${signal.id}: ${err.message}`);
        return { error: err.message };
    }
}
async function main() {
    console.log(`${LOG_PREFIX} Keeper starting...`);
    // Verify keeper is authorized
    try {
        const oracle = await Promise.resolve().then(() => __importStar(require('./chain'))).then((m) => m.getScoringOracle());
        console.log(`${LOG_PREFIX} Scoring oracle: ${oracle}`);
    }
    catch (e) {
        console.warn(`${LOG_PREFIX} Could not verify scoring oracle: ${e.message}`);
    }
    // Step 1: Check if epoch is ready
    let ready = false;
    try {
        ready = await (0, chain_1.checkEpochReady)();
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to check epoch readiness: ${e.message}`);
        throw e;
    }
    if (!ready) {
        console.log(`${LOG_PREFIX} Epoch not ready yet, skipping this run.`);
        throw new Error('EPOCH_NOT_READY');
    }
    console.log(`${LOG_PREFIX} Epoch is ready, beginning settlement...`);
    // Step 2: Get epoch timing
    const currentEpochId = await (0, chain_1.getCurrentEpochId)();
    const lastEpochStart = await (0, chain_1.getLastEpochStart)();
    const endTime = Math.floor(Date.now() / 1000);
    const startTime = Number(lastEpochStart);
    const epochId = Number(currentEpochId);
    console.log(`${LOG_PREFIX} Settling epoch ${epochId} (window: ${startTime} → ${endTime}, ` +
        `duration: ${endTime - startTime}s)`);
    // Step 3: Get all active signals in this epoch window
    let signals = [];
    try {
        signals = await (0, supabase_1.getActiveSignalsForEpoch)(startTime, endTime);
        console.log(`${LOG_PREFIX} Found ${signals.length} active signals in epoch window`);
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to fetch signals from Supabase: ${e.message}`);
        throw e;
    }
    let settledSignals = 0;
    let failedSignals = 0;
    const accuracyResults = [];
    if (signals.length === 0) {
        console.log(`${LOG_PREFIX} No signals to score, settling empty epoch...`);
        try {
            const settleTx = await (0, chain_1.settleEpoch)();
            console.log(`${LOG_PREFIX} Empty epoch settled: ${settleTx}`);
            return { epochId, totalSignals: 0, settledSignals: 0, failedSignals: 0, avgAccuracyBps: 0, settleTx };
        }
        catch (e) {
            console.error(`${LOG_PREFIX} Failed to settle empty epoch: ${e.message}`);
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
        }
        else {
            failedSignals++;
        }
        // Small delay between signals to avoid rate limiting
        await sleep(500);
    }
    // Step 5: Settle epoch on-chain
    console.log(`${LOG_PREFIX} Settling epoch on-chain...`);
    let settleTx = '';
    try {
        settleTx = await (0, chain_1.settleEpoch)();
        const confirmed = await waitForTransaction(settleTx);
        if (!confirmed) {
            console.warn(`${LOG_PREFIX} settleEpoch tx not confirmed: ${settleTx}`);
        }
        console.log(`${LOG_PREFIX} Epoch settled on-chain: ${settleTx}`);
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to settle epoch: ${e.message}`);
        throw e;
    }
    // Step 6: Update epoch history in Supabase
    const avgAccuracyBps = accuracyResults.length > 0
        ? Math.round(accuracyResults.reduce((sum, r) => sum + r.accuracyBps, 0) / accuracyResults.length)
        : 0;
    try {
        await (0, supabase_1.insertEpochHistory)({
            epoch_id: epochId,
            start_time: startTime,
            end_time: endTime,
            total_signals: signals.length,
            settled_signals: settledSignals,
            avg_accuracy_bps: avgAccuracyBps,
        });
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to insert epoch history: ${e.message}`);
    }
    // Step 7: Mark signals as resolved
    try {
        await (0, supabase_1.markSignalsAsResolved)(signals.map((s) => s.id));
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to mark signals as resolved: ${e.message}`);
    }
    // Step 8: Audit log
    try {
        await (0, supabase_1.insertAuditLog)('keeper', 'epoch_settle', {
            epochId,
            totalSignals: signals.length,
            settledSignals,
            failedSignals,
            avgAccuracyBps,
            settleTx,
        });
    }
    catch (e) {
        console.error(`${LOG_PREFIX} Failed to insert audit log: ${e.message}`);
    }
    console.log(`${LOG_PREFIX} Keeper finished. Epoch ${epochId}: ${settledSignals}/${signals.length} signals settled, ` +
        `avg accuracy: ${avgAccuracyBps}bps`);
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

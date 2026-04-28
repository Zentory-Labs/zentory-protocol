"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.supabase = void 0;
exports.getActiveSignalsForEpoch = getActiveSignalsForEpoch;
exports.getAssetPriceOnDate = getAssetPriceOnDate;
exports.insertEpochHistory = insertEpochHistory;
exports.updateProviderStats = updateProviderStats;
exports.insertSignalScore = insertSignalScore;
exports.insertAuditLog = insertAuditLog;
exports.getUnsettledSignals = getUnsettledSignals;
exports.markSignalsAsResolved = markSignalsAsResolved;
const supabase_js_1 = require("@supabase/supabase-js");
const config_1 = require("./config");
exports.supabase = (0, supabase_js_1.createClient)(config_1.config.supabase.url, config_1.config.supabase.serviceRoleKey);
async function getActiveSignalsForEpoch(startTime, endTime) {
    const { data, error } = await exports.supabase
        .from('signals')
        .select('*')
        .eq('status', 'Active')
        .gte('submitted_at', startTime.toString())
        .lt('submitted_at', endTime.toString());
    if (error) {
        throw new Error(`Failed to fetch signals: ${error.message}`);
    }
    return (data ?? []);
}
async function getAssetPriceOnDate(assetId, timestamp) {
    const { data, error } = await exports.supabase
        .from('price_data')
        .select('price_usd')
        .eq('asset_id', assetId)
        .lte('timestamp', timestamp.toString())
        .order('timestamp', { ascending: false })
        .limit(1);
    if (error) {
        throw new Error(`Failed to fetch price: ${error.message}`);
    }
    if (!data || data.length === 0) {
        throw new Error(`No price data found for asset ${assetId} at timestamp ${timestamp}`);
    }
    return parseFloat(data[0].price_usd);
}
async function insertEpochHistory(epochData) {
    const { error } = await exports.supabase.from('epoch_history').insert([epochData]);
    if (error) {
        throw new Error(`Failed to insert epoch history: ${error.message}`);
    }
}
async function updateProviderStats(provider, epochId, accuracy, payout) {
    const record = {
        provider,
        epoch_id: epochId,
        accuracy_bps: accuracy,
        payout_zent: payout.toString(),
    };
    const { error } = await exports.supabase.from('provider_stats').insert([record]);
    if (error) {
        throw new Error(`Failed to update provider stats: ${error.message}`);
    }
}
async function insertSignalScore(signalId, epochId, accuracyBps, payoutZent) {
    const record = {
        signal_id: signalId,
        epoch_id: epochId,
        accuracy_bps: accuracyBps,
        payout_zent: payoutZent,
    };
    const { error } = await exports.supabase.from('signal_scores').insert([record]);
    if (error) {
        throw new Error(`Failed to insert signal score: ${error.message}`);
    }
}
async function insertAuditLog(actor, action, payload) {
    const record = {
        actor,
        action,
        payload,
        timestamp: Math.floor(Date.now() / 1000),
    };
    const { error } = await exports.supabase.from('audit_logs').insert([record]);
    if (error) {
        console.error(`Failed to insert audit log: ${error.message}`);
    }
}
async function getUnsettledSignals(limit = 100) {
    const { data, error } = await exports.supabase
        .from('signals')
        .select('*')
        .eq('status', 'Active')
        .order('submitted_at', { ascending: true })
        .limit(limit);
    if (error) {
        throw new Error(`Failed to fetch unsettled signals: ${error.message}`);
    }
    return (data ?? []);
}
async function markSignalsAsResolved(signalIds) {
    const { error } = await exports.supabase
        .from('signals')
        .update({ status: 'Resolved' })
        .in('id', signalIds);
    if (error) {
        throw new Error(`Failed to mark signals as resolved: ${error.message}`);
    }
}

"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchCryptoPrice = fetchCryptoPrice;
exports.computeAccuracy = computeAccuracy;
exports.batchFetchPrices = batchFetchPrices;
const axios_1 = __importDefault(require("axios"));
// Asset ID to CoinGecko coin IDs
const ASSET_COINGECKO_IDS = {
    BTC: 'bitcoin',
    ETH: 'ethereum',
    SOL: 'solana',
    XRP: 'ripple',
    BNB: 'binancecoin',
    ADA: 'cardano',
    AVAX: 'avalanche-2',
    DOGE: 'dogecoin',
    DOT: 'polkadot',
    MATIC: 'matic-network',
    LINK: 'chainlink',
    UNI: 'uniswap',
    AAVE: 'aave',
    MKR: 'maker',
    SNX: 'havven',
    CRV: 'curve-dao-token',
    COMP: 'compound-governance-token',
    SUSHI: 'sushi',
    YFI: 'yearn-finance',
    ALGO: 'algorand',
};
async function fetchCryptoPrice(assetId, timestamp) {
    const coinId = ASSET_COINGECKO_IDS[assetId];
    if (!coinId) {
        throw new Error(`Unknown crypto asset: ${assetId}`);
    }
    const date = new Date(timestamp * 1000);
    const dateStr = `${date.getUTCDate().toString().padStart(2, '0')}-${(date.getUTCMonth() + 1).toString().padStart(2, '0')}-${date.getUTCFullYear()}`;
    try {
        const response = await axios_1.default.get(`https://api.coingecko.com/api/v3/coins/${coinId}/history`, {
            params: { date: dateStr },
            timeout: 10000,
        });
        return response.data.market_data.current_price.usd;
    }
    catch (historyError) {
        const err = historyError;
        // Fallback to current price if historical not available
        if (err.response?.status === 404 || err.response?.status === 400) {
            console.warn(`Historical price not available for ${assetId}, falling back to current price`);
            const current = await axios_1.default.get(`https://api.coingecko.com/api/v3/simple/price`, {
                params: { ids: coinId, vs_currencies: 'usd' },
                timeout: 10000,
            });
            return current.data[coinId].usd;
        }
        throw new Error(`Failed to fetch price for ${assetId}: ${err.message}`);
    }
}
async function computeAccuracy(signal, settlementPrice, submissionPrice) {
    if (submissionPrice === 0) {
        throw new Error(`Invalid submission price of 0 for signal ${signal.id}`);
    }
    const priceChangeBps = Math.round(((settlementPrice - submissionPrice) / submissionPrice) * 10000);
    let accuracyBps;
    if (signal.direction >= 0) {
        accuracyBps = Math.round(5000 + (signal.direction / 10000) * priceChangeBps);
    }
    else {
        accuracyBps = Math.round(5000 + (Math.abs(signal.direction) / 10000) * (-priceChangeBps));
    }
    accuracyBps = Math.max(0, Math.min(10000, accuracyBps));
    return {
        signalId: signal.id,
        accuracyBps,
        priceChangeBps,
    };
}
async function batchFetchPrices(assetIds, timestamp) {
    const prices = new Map();
    const uniqueAssets = [...new Set(assetIds)];
    await Promise.all(uniqueAssets.map(async (assetId) => {
        try {
            const price = await fetchCryptoPrice(assetId, timestamp);
            prices.set(assetId, price);
        }
        catch (e) {
            console.error(`Failed to fetch price for ${assetId}: ${e.message}`);
        }
    }));
    return prices;
}

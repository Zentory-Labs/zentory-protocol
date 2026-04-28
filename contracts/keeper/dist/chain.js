"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EpochScoringABI = exports.SignalRegistryABI = void 0;
exports.getPublicClient = getPublicClient;
exports.getKeeperWallet = getKeeperWallet;
exports.checkEpochReady = checkEpochReady;
exports.getCurrentEpochId = getCurrentEpochId;
exports.getLastEpochStart = getLastEpochStart;
exports.isEpochSettled = isEpochSettled;
exports.getCachedAccuracy = getCachedAccuracy;
exports.getScoringOracle = getScoringOracle;
exports.setAccuracy = setAccuracy;
exports.setAccuracyBatch = setAccuracyBatch;
exports.applyPayout = applyPayout;
exports.settleEpoch = settleEpoch;
exports.hexToSignalId = hexToSignalId;
exports.signalIdToHex = signalIdToHex;
const viem_1 = require("viem");
const accounts_1 = require("viem/accounts");
const config_1 = require("./config");
// ─── HyperEVM Testnet Chain Definition ───────────────────────────────────────
const hyperEVMTestnet = (0, viem_1.defineChain)({
    id: 998,
    name: 'HyperEVM Testnet',
    nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
    rpcUrls: {
        default: { http: [config_1.config.rpcUrl] },
        public: { http: [config_1.config.rpcUrl] },
    },
    blockExplorers: {
        default: {
            name: 'HyperEVM Explorer',
            url: 'https://testnet-explorer.hyperliquid.xyz',
        },
    },
});
// ─── ABI Fragments ────────────────────────────────────────────────────────────
exports.SignalRegistryABI = [
    {
        name: 'getSignal',
        type: 'function',
        inputs: [{ name: 'signalId', type: 'bytes32' }],
        outputs: [{
                name: '',
                type: 'tuple',
                components: [
                    { name: 'provider', type: 'address' },
                    { name: 'assetClass', type: 'uint8' },
                    { name: 'assetId', type: 'bytes32' },
                    { name: 'direction', type: 'int256' },
                    { name: 'confidence', type: 'uint256' },
                    { name: 'expiresAt', type: 'uint256' },
                    { name: 'submittedAt', type: 'uint256' },
                ],
            }],
        stateMutability: 'view',
    },
    {
        name: 'signalExists',
        type: 'function',
        inputs: [{ name: 'signalId', type: 'bytes32' }],
        outputs: [{ name: '', type: 'bool' }],
        stateMutability: 'view',
    },
    {
        name: 'providerNonce',
        type: 'function',
        inputs: [{ name: 'provider', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
        stateMutability: 'view',
    },
];
exports.EpochScoringABI = [
    {
        name: 'checkUpkeep',
        type: 'function',
        inputs: [{ name: '', type: 'bytes' }],
        outputs: [
            { name: 'upkeepNeeded', type: 'bool' },
            { name: 'performData', type: 'bytes' },
        ],
        stateMutability: 'view',
    },
    {
        name: 'performUpkeep',
        type: 'function',
        inputs: [{ name: 'performData', type: 'bytes' }],
        outputs: [],
        stateMutability: 'nonpayable',
    },
    {
        name: 'settleEpoch',
        type: 'function',
        inputs: [],
        outputs: [],
        stateMutability: 'nonpayable',
    },
    {
        name: 'setAccuracy',
        type: 'function',
        inputs: [
            { name: 'signalId', type: 'bytes32' },
            { name: 'accuracyBps', type: 'uint256' },
        ],
        outputs: [],
        stateMutability: 'nonpayable',
    },
    {
        name: 'setAccuracyBatch',
        type: 'function',
        inputs: [
            { name: 'signalIds', type: 'bytes32[]' },
            { name: 'accuraciesBps', type: 'uint256[]' },
        ],
        outputs: [],
        stateMutability: 'nonpayable',
    },
    {
        name: 'applyPayout',
        type: 'function',
        inputs: [{ name: 'signalId', type: 'bytes32' }],
        outputs: [{ name: 'payout', type: 'int256' }],
        stateMutability: 'nonpayable',
    },
    {
        name: 'accuracyCache',
        type: 'function',
        inputs: [{ name: 'signalId', type: 'bytes32' }],
        outputs: [{ name: '', type: 'uint256' }],
        stateMutability: 'view',
    },
    {
        name: 'currentEpochId',
        type: 'function',
        inputs: [],
        outputs: [{ name: '', type: 'uint256' }],
        stateMutability: 'view',
    },
    {
        name: 'lastEpochStart',
        type: 'function',
        inputs: [],
        outputs: [{ name: '', type: 'uint256' }],
        stateMutability: 'view',
    },
    {
        name: 'epochStates',
        type: 'function',
        inputs: [{ name: '', type: 'uint256' }],
        outputs: [
            { name: 'totalSignals', type: 'uint256' },
            { name: 'settledSignals', type: 'uint256' },
            { name: 'settled', type: 'bool' },
        ],
        stateMutability: 'view',
    },
    {
        name: 'scoringOracle',
        type: 'function',
        inputs: [],
        outputs: [{ name: '', type: 'address' }],
        stateMutability: 'view',
    },
];
// ─── Client Factories ─────────────────────────────────────────────────────────
function getPublicClient() {
    return (0, viem_1.createPublicClient)({
        transport: (0, viem_1.http)(config_1.config.rpcUrl),
        chain: hyperEVMTestnet,
    });
}
function getKeeperWallet() {
    const account = (0, accounts_1.privateKeyToAccount)(config_1.config.keeperPrivateKey);
    return (0, viem_1.createWalletClient)({
        account,
        transport: (0, viem_1.http)(config_1.config.rpcUrl),
        chain: hyperEVMTestnet,
    });
}
// ─── Read Operations ─────────────────────────────────────────────────────────
async function checkEpochReady() {
    const client = getPublicClient();
    const [upkeepNeeded] = await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'checkUpkeep',
        args: ['0x'],
    });
    return upkeepNeeded;
}
async function getCurrentEpochId() {
    const client = getPublicClient();
    return await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'currentEpochId',
    });
}
async function getLastEpochStart() {
    const client = getPublicClient();
    return await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'lastEpochStart',
    });
}
async function isEpochSettled(epochId) {
    const client = getPublicClient();
    const state = await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'epochStates',
        args: [epochId],
    });
    return state[2];
}
async function getCachedAccuracy(signalId) {
    const client = getPublicClient();
    return await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'accuracyCache',
        args: [signalId],
    });
}
async function getScoringOracle() {
    const client = getPublicClient();
    return await client.readContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'scoringOracle',
    });
}
// ─── Write Operations ────────────────────────────────────────────────────────
async function setAccuracy(signalId, accuracyBps) {
    const wallet = getKeeperWallet();
    const hash = await wallet.writeContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'setAccuracy',
        args: [signalId, BigInt(accuracyBps)],
    });
    return hash;
}
async function setAccuracyBatch(signalIds, accuraciesBps) {
    const wallet = getKeeperWallet();
    const hash = await wallet.writeContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'setAccuracyBatch',
        args: [signalIds, accuraciesBps.map(BigInt)],
    });
    return hash;
}
async function applyPayout(signalId) {
    const wallet = getKeeperWallet();
    try {
        await wallet.writeContract({
            address: config_1.config.contracts.epochScoring,
            abi: exports.EpochScoringABI,
            functionName: 'applyPayout',
            args: [signalId],
        });
        const client = getPublicClient();
        const signal = await client.readContract({
            address: config_1.config.contracts.signalRegistry,
            abi: exports.SignalRegistryABI,
            functionName: 'getSignal',
            args: [signalId],
        });
        return {
            signalId,
            provider: signal.provider,
            payoutZent: 0n,
            success: true,
        };
    }
    catch (e) {
        const error = e;
        return {
            signalId,
            provider: signalId,
            payoutZent: 0n,
            success: false,
            error: error.message,
        };
    }
}
async function settleEpoch() {
    const wallet = getKeeperWallet();
    const hash = await wallet.writeContract({
        address: config_1.config.contracts.epochScoring,
        abi: exports.EpochScoringABI,
        functionName: 'settleEpoch',
        args: [],
    });
    return hash;
}
// ─── Utilities ───────────────────────────────────────────────────────────────
function hexToSignalId(hex) {
    const clean = hex.replace('0x', '').padStart(64, '0');
    return `0x${clean}`;
}
function signalIdToHex(signalId) {
    if (!signalId.startsWith('0x')) {
        return `0x${signalId}`;
    }
    return signalId;
}

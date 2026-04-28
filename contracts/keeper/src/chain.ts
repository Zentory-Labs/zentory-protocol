import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { config } from './config';
import { PayoutResult } from './types';

// ─── HyperEVM Testnet Chain Definition ───────────────────────────────────────

const hyperEVMTestnet = defineChain({
  id: 998,
  name: 'HyperEVM Testnet',
  nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: [config.rpcUrl] },
    public: { http: [config.rpcUrl] },
  },
  blockExplorers: {
    default: {
      name: 'HyperEVM Explorer',
      url: 'https://testnet-explorer.hyperliquid.xyz',
    },
  },
});

// ─── ABI Fragments ────────────────────────────────────────────────────────────

export const SignalRegistryABI = [
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
] as const;

export const EpochScoringABI = [
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
] as const;

// ─── Client Factories ─────────────────────────────────────────────────────────

export function getPublicClient() {
  return createPublicClient({
    transport: http(config.rpcUrl),
    chain: hyperEVMTestnet,
  });
}

export function getKeeperWallet() {
  const account = privateKeyToAccount(config.keeperPrivateKey as `0x${string}`);
  return createWalletClient({
    account,
    transport: http(config.rpcUrl),
    chain: hyperEVMTestnet,
  });
}

// ─── Read Operations ─────────────────────────────────────────────────────────

export async function checkEpochReady(): Promise<boolean> {
  const client = getPublicClient();
  const [upkeepNeeded] = await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'checkUpkeep',
    args: ['0x'] as const,
  });
  return upkeepNeeded;
}

export async function getCurrentEpochId(): Promise<bigint> {
  const client = getPublicClient();
  return await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'currentEpochId',
  });
}

export async function getLastEpochStart(): Promise<bigint> {
  const client = getPublicClient();
  return await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'lastEpochStart',
  });
}

export async function isEpochSettled(epochId: bigint): Promise<boolean> {
  const client = getPublicClient();
  const state = await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'epochStates',
    args: [epochId],
  });
  return state[2];
}

export async function getCachedAccuracy(signalId: `0x${string}`): Promise<bigint> {
  const client = getPublicClient();
  return await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'accuracyCache',
    args: [signalId],
  });
}

export async function getScoringOracle(): Promise<`0x${string}`> {
  const client = getPublicClient();
  return await client.readContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'scoringOracle',
  });
}

// ─── Write Operations ────────────────────────────────────────────────────────

export async function setAccuracy(
  signalId: `0x${string}`,
  accuracyBps: number
): Promise<`0x${string}`> {
  const wallet = getKeeperWallet();
  const hash = await wallet.writeContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'setAccuracy',
    args: [signalId, BigInt(accuracyBps)] as const,
  });
  return hash;
}

export async function setAccuracyBatch(
  signalIds: `0x${string}`[],
  accuraciesBps: number[]
): Promise<`0x${string}`> {
  const wallet = getKeeperWallet();
  const hash = await wallet.writeContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'setAccuracyBatch',
    args: [signalIds, accuraciesBps.map(BigInt)] as const,
  });
  return hash;
}

export async function applyPayout(signalId: `0x${string}`): Promise<PayoutResult> {
  const wallet = getKeeperWallet();
  try {
    await wallet.writeContract({
      address: config.contracts.epochScoring,
      abi: EpochScoringABI,
      functionName: 'applyPayout',
      args: [signalId] as const,
    });

    const client = getPublicClient();
    const signal = await client.readContract({
      address: config.contracts.signalRegistry,
      abi: SignalRegistryABI,
      functionName: 'getSignal',
      args: [signalId],
    });

    return {
      signalId,
      provider: signal.provider,
      payoutZent: 0n,
      success: true,
    };
  } catch (e: unknown) {
    const error = e as Error;
    return {
      signalId,
      provider: signalId,
      payoutZent: 0n,
      success: false,
      error: error.message,
    };
  }
}

export async function settleEpoch(): Promise<`0x${string}`> {
  const wallet = getKeeperWallet();
  const hash = await wallet.writeContract({
    address: config.contracts.epochScoring,
    abi: EpochScoringABI,
    functionName: 'settleEpoch',
    args: [],
  });
  return hash;
}

// ─── Utilities ───────────────────────────────────────────────────────────────

export function hexToSignalId(hex: string): `0x${string}` {
  const clean = hex.replace('0x', '').padStart(64, '0');
  return `0x${clean}` as `0x${string}`;
}

export function signalIdToHex(signalId: string): `0x${string}` {
  if (!signalId.startsWith('0x')) {
    return `0x${signalId}` as `0x${string}`;
  }
  return signalId as `0x${string}`;
}

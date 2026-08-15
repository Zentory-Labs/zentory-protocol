import * as dotenv from 'dotenv';
import { privateKeyToAccount } from 'viem/accounts';
dotenv.config();

const keeperPrivateKey = process.env.KEEPER_PRIVATE_KEY!;
const keeperAccount = privateKeyToAccount(keeperPrivateKey as `0x${string}`);

// Comma-separated list of secondary RPC URLs. Used by viem's `fallback`
// transport: the public client and the wallet client both try the primary
// URL first, then walk this list on transport failure. See chain.ts.
const rpcFallbackUrls: string[] = (process.env.HYPEREVM_RPC_URL_FALLBACK ?? '')
  .split(',')
  .map((u) => u.trim())
  .filter((u) => u.length > 0);

export const config = {
  rpcUrl: process.env.HYPEREVM_RPC_URL!,
  rpcFallbackUrls,
  keeperPrivateKey,
  keeperAddress: keeperAccount.address,
  chainId: parseInt(process.env.CHAIN_ID || '998'),
  contracts: {
    signalRegistry: process.env.SIGNAL_REGISTRY_ADDRESS! as `0x${string}`,
    epochScoring: process.env.EPOCH_SCORING_ADDRESS! as `0x${string}`,
    zentStaking: process.env.ZENT_STAKING_ADDRESS! as `0x${string}`,
    zentToken: process.env.ZENT_TOKEN_ADDRESS! as `0x${string}`,
  },
  supabase: {
    url: process.env.SUPABASE_URL!,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
  },
  scoringOracle: process.env.SCORING_ORACLE_ADDRESS! as `0x${string}`,
} as const;

// Validate required env vars
const required = [
  'HYPEREVM_RPC_URL',
  'KEEPER_PRIVATE_KEY',
  'SIGNAL_REGISTRY_ADDRESS',
  'EPOCH_SCORING_ADDRESS',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
];

for (const key of required) {
  if (!process.env[key]) {
    throw new Error(`Missing required env var: ${key}`);
  }
}

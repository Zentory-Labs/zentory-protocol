import * as dotenv from 'dotenv';
dotenv.config();

export const config = {
  rpcUrl: process.env.HYPEREVM_RPC_URL!,
  keeperPrivateKey: process.env.KEEPER_PRIVATE_KEY!,
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

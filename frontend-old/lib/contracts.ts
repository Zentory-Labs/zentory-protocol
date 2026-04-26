// Deployed contract addresses on HyperEVM testnet (chain 998)
export const addresses = {
  // Core
  ZENT: "0x526aaa271f5e54d737f79a6173b3a0fd7185dc33",
  Vesting: "0x413e61d6f8bb881fdd02546bbc04c1b92429410c",

  // Vaults
  zETH: "0x29e9d6d167db74485ccae763a8692688c28c8d93",
  zBTC: "0xae5a4352c002a7d323f37bf682a29f81a5241c21",
  zXRP: "0x9e6a4ebf70533ddf0350bf69ad1b998c75e5422c",
  zSOL: "0xc56cf443a4e622d91fd786b218164e4b0178a997",

  // Mock assets (for testnet — replace with real tokens on mainnet)
  WETH: "0x45a85401c657802a6cdea33bf887a30335149e61",
  WBTC: "0x1a23fba455c6e625def7f69cc2bb3b3a628f372a",
  WXRP: "0x16dea5d797a97ba130c708de40efd6dfda37efd4",
  WSOL: "0x27d9e82104890f772fc86030bb439efb14752ddb",

  // Staking & Fees
  ZENTStaking: "0x4861420f0a7baab69ae2d4c1c1de1155728a161b",
  ModelBonding: "0x99b8bc5c86f27ec38d6abbc6e76dcbdfbb2201f1",
  FeeDistributor: {
    zETH: "0x701199c86342c0fec304530a0fc5dcc533cfe3c8",
    zBTC: "0x7e49a37c1b93ad8cb2bb3527a108b3ead6bc0333",
    zXRP: "0x19940b4ee59e823ed7e93bf1d9012ff13f715e8e",
    zSOL: "0xb21a10b910193a145e5f042a8781768a52482d1a",
  },

  // Governance
  Timelock: "0x47e11c831e355f3566a33f913ea3bcb12b6983cb",
  Zentroller: "0xa56fb921e139f971677cf7b942d16aeb8d1e9cc7",
  ZentGovernor: "0x661b753bdefe3d7fde2154dc0bbbdd9f18ec801b",

  // Keeper
  HyperCoreAdapter: "0x05b6921967d75e189aeaad2b39291fe03a1e5094",
  StrategyExecutor: "0x337a9fce9fc0a3ac50c6f924af5ccb4dff65586f",
} as const;

// ─── ABIs ───────────────────────────────────────────────────────────────────

export const ZENT_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function transferFrom(address,address,uint256) returns (bool)",
] as const;

export const VAULT_ABI = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function convertToShares(uint256) view returns (uint256)",
  "function convertToAssets(uint256) view returns (uint256)",
  "function deposit(uint256,address) returns (uint256)",
  "function mint(uint256,address) returns (uint256)",
  "function withdraw(uint256,address,address) returns (uint256)",
  "function redeem(uint256,address,address) returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
  "function maxMint(address) view returns (uint256)",
  "function highWaterMark() view returns (uint256)",
  "function getNavPerShare() view returns (uint256)",
  "function currentDirection() view returns (int8)",
  "function currentPositionSize() view returns (uint256)",
  "function performanceFeeAccrued() view returns (uint256)",
  "function performanceFee() view returns (uint256)",
  "function isCircuitBreakerActive() view returns (bool)",
  "function hasRole(bytes32,address) view returns (bool)",
  "event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares)",
  "event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)",
] as const;

export const STAKING_ABI = [
  "function stake(uint256,uint64) returns (uint64)",
  "function increaseAmount(uint256)",
  "function extendLock(uint64) returns (uint64)",
  "function withdraw()",
  "function veBalance(address) view returns (uint256)",
  "function hasAccess(address) view returns (bool)",
  "function stakedBalance(address) view returns (uint256)",
  "function lockEndOf(address) view returns (uint64)",
  "function totalStaked() view returns (uint256)",
  "function minStake() view returns (uint256)",
  "event Staked(address indexed user, uint256 amount, uint64 lockEnd)",
  "event Withdrawn(address indexed user, uint256 amount)",
] as const;

export const GOVERNOR_ABI = [
  "function name() view returns (string)",
  "function version() view returns (string)",
  "function quorum(uint256) view returns (uint256)",
  "function proposalThreshold() view returns (uint256)",
  "function votingDelay() view returns (uint256)",
  "function votingPeriod() view returns (uint256)",
  "function propose(address[],uint256[],bytes[],string) returns (uint256)",
  "function castVote(uint256,uint8) returns (uint256)",
  "function castVoteWithReason(uint256,uint8,string) returns (uint256)",
  "function state(uint256) view returns (uint8)",
  "function proposalDeadline(uint256) view returns (uint256)",
  "function proposalSnapshot(uint256) view returns (uint256)",
] as const;

export const EXECUTOR_ABI = [
  "function paused() view returns (bool)",
  "function maxPositionSize(address) view returns (uint256)",
  "function maxLeverageBPS(address) view returns (uint256)",
  "function nonces(address) view returns (uint256)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function recordTradeManual(address,bool,uint64,uint64)",
  "function setPaused(bool)",
  "function setMaxPositionSize(address,uint256)",
  "function setMaxLeverageBPS(address,uint256)",
  "function DOMAIN_SEPARATOR() view returns (bytes32)",
  "function KEEPER_ROLE() view returns (bytes32)",
  "function GOVERNOR_ROLE() view returns (bytes32)",
  "function GUARDIAN_ROLE() view returns (bytes32)",
  "event ManualTradeRecorded(address indexed vault, bool indexed isBuy, uint64 size, uint64 price, address indexed keeper)",
  "event PausedSet(bool paused)",
] as const;

export const HYPERCORE_ADAPTER_ABI = [
  "function sendLimitOrder(uint8,bool,uint64,uint64,bool,uint8,uint128)",
  "function vaultRegistry(address) view returns (uint8)",
  "function lastTradePrice(uint8) view returns (uint256)",
] as const;

// ─── Chain config ────────────────────────────────────────────────────────────

export const HYPEREVM_TESTNET = {
  id: 998,
  name: "Hyperliquid Testnet",
  nativeCurrency: { name: "Hyperliquid", symbol: "HYPE", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.hyperliquid-testnet.xyz/evm"] },
    public: { http: ["https://rpc.hyperliquid-testnet.xyz/evm"] },
  },
  blockExplorers: {
    default: {
      name: "HypurrScan",
      url: "https://hypurrscan.io",
      apiUrl: "https://api.hypurrscan.io",
    },
  },
} as const;

// ─── Helpers ─────────────────────────────────────────────────────────────────

export const vaultMeta: Record<string, { name: string; symbol: string; color: string; asset: string }> = {
  [addresses.zETH]: { name: "zETH Vault", symbol: "zETH", color: "#627EEA", asset: "ETH" },
  [addresses.zBTC]: { name: "zBTC Vault", symbol: "zBTC", color: "#F7931A", asset: "BTC" },
  [addresses.zXRP]: { name: "zXRP Vault", symbol: "zXRP", color: "#23292F", asset: "XRP" },
  [addresses.zSOL]: { name: "zSOL Vault", symbol: "zSOL", color: "#9945FF", asset: "SOL" },
};

// Alias for backward compatibility
export const strategyExecutorABI = EXECUTOR_ABI;

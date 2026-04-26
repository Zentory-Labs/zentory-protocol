// Deployed contract addresses on HyperEVM testnet (chain 998)
export const addresses = {
  // Core
  ZENT: "0xb6387CDF70804687eD68b4eE91f7F3C81eF479Ca",
  Vesting: "0x7baee73a735375e17dF6A1C5d50eE86700B7039A",

  // Vaults
  zETH: "0xe34fe1537648104c571a04D0e2Ed425D4eC05661",
  zBTC: "0x128D65cd5650CB9c079070e6cfF067F1945B8051",
  zXRP: "0x2c1876928a3B8a095a5bb1364601f2Df72970A90",
  zSOL: "0x088043D7e068eF678498A266Acd669B516552F47",

  // Mock assets (for testnet — replace with real tokens on mainnet)
  WETH: "0xb9BD979509c6Da50dC6b14BA4E6a90707C132CF5",
  WBTC: "0x7600439c95E8e7263256Ec872DFF65aeB91a3D8c",
  WXRP: "0x0abBD235B5c433B25270be00085bfAE1888583ea",
  WSOL: "0xAF994F6c7Acb653C0359e462f8f7576D114771A8",

  // Staking & Fees
  ZENTStaking: "0x606C854274fF8873EA83FA9913e60D2B576d934f",
  ModelBonding: "0x7d3c330604eA55eC7b5b4713865F3c713f42F0a9",
  FeeDistributor: {
    zETH: "0x7B71eeD7FD0670bb6dC3F3207441998242f9F158",
    zBTC: "0x562DA6047467Cee4EE9dA2a644CB48790E1862Eb",
    zXRP: "0x5c3a05203a587a08a038f6aDEdB11b996D3C05f0",
    zSOL: "0xB8E1eDcAfa83DFE199EaA028Fc11a5D1b77958da",
  },

  // Governance
  Timelock: "0x8bB94d7e81a314Ce6e6C830A1aEC3759FA69A4Fa",
  Zentroller: "0x9dC82631d9E5ADC3059535598125ec4dB376F906",
  ZentGovernor: "0x407Cdb109aA355C6CC21ba80c905A8f13B82AaF4",

  // Keeper
  HyperCoreAdapter: "0x0794c919E0698fEEAb5eA4ad1c1cb19FE4eb12D8",
  StrategyExecutor: "0x7e6df18bF031FCB77B52Bc76cbB933d3E2a0e185",
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

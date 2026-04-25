// Deployed contract addresses on HyperEVM testnet (chain 998)
export const addresses = {
  // Core
  ZENT: "0x24EC47b4F1Ee9DC3aBea2132b2721509E2E970cb",
  Vesting: "0x1dc57196cCbC2Ef9a325725F2033043cbDb606cc",

  // Vaults
  zETH: "0x8367449CFEE8f8eA15Daf91B8A535F55687D3aC0",
  zBTC: "0x07b4DeB8A3B4CF656276312e2BF63E9927bfBc97",
  zXRP: "0xe75421E0d7322188F98cBdb1211F2fED9285bb9d",
  zSOL: "0x6c5aBE91Fe5364022DAB20A5b8Ac4F34285FdDD9",

  // Mock assets (for testnet — replace with real tokens on mainnet)
  WETH: "0x9b075A31D8Bb475c48529b2FAcC9732C20109246",
  WBTC: "0x82A7863D588fBC961757F01C98022fbB44ef7B84",
  WXRP: "0xD50E6BB9f57172Db7a7980BE37F8b1F7516233A0",
  WSOL: "0x4aad3776f2EF8e26F05ecfB2046cc5984F062251",

  // Staking & Fees
  ZENTStaking: "0xEbc04Ba2CC015f7af33a6Dc58159c1484aCf9409",
  ModelBonding: "0x985481B75CB5D20a5E1979071FF6f8Bd64541a1b",
  FeeDistributor: {
    zETH: "0xCE4DdC77C9A32918Ad687659c299f47Abd494C19",
    zBTC: "0x0c40138b850E4deFdD1E6cdd0C0420cbF7EA80EF",
    zXRP: "0x4dD34e80Da434B48b3937e8bde237594Cd328647",
    zSOL: "0x16D128082749779670bD8c000e6Ca3BA15Ec8d13",
  },

  // Governance
  Timelock: "0x891ce345595Ab197c04EfA8EBb1bb383Cdc696dA",
  Zentroller: "0xeBCE023De03CEBD11Ee97494Bf8ef8A2144cD066",
  ZentGovernor: "0x7a2682512F7483D15b8bD899645c64397FaD408C",

  // Keeper
  HyperCoreAdapter: "0xa42Cb6bE26Db7252b8dED3d6df29a164E15AD750",
  StrategyExecutor: "0xe9FF22Ab0F5b032e84120142A23253f18facd1DD",
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

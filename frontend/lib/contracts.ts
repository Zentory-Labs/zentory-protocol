// Deployed contract addresses on HyperEVM testnet (chain 998)
// Verified live on-chain — deployed 2026-04-27 by 0x3F07367008158dC272Dd8A38812e1460eF5a390a
export const addresses = {
  // Core
  ZENT: "0x271cd48c1297CacCD810c7B1BCD904f459df7117",
  Vesting: "0xf7c45f45768d790F388215A44d6E01f6f2568774",

  // Vaults
  zETH: "0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e",
  zBTC: "0x93669daC07321FF397cf5734Ae8364EA24addF45",
  zXRP: "0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0",
  zSOL: "0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052",

  // Mock assets (for testnet — replace with real tokens on mainnet)
  WETH: "0x80F727AF3f7932718fEb25FC28818Ad103040BD2",
  WBTC: "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40",
  WXRP: "0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371",
  WSOL: "0x2b9d5bBD8C5FEfc71E985d993C13db2770469972",

  // Staking & Fees
  ZENTStaking: "0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65",
  ModelBonding: "0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007",
  FeeDistributor: {
    zETH: "0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73",
    zBTC: "0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c",
    zXRP: "0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F",
    zSOL: "0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0",
  },

  // Governance
  Timelock: "0x1504cA3C050C88CcCa67696d642F634fc381fD03",
  Zentroller: "0x24f9401284CE16CFe61e40C1F9e3fb37d15B878E",
  ZentGovernor: "0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118",

  // Keeper
  HyperCoreAdapter: "0xfFc1Da47f780973e935Bb9F5a9d455aE7A5f7eac",
  StrategyExecutor: "0x427c94150f3f700Dc2EDf7bCc97155A467E41F21",
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

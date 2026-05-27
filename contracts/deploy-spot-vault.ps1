# Zentory SpotVault deploy (HyperEVM testnet, chain 998).
# PRIVATE_KEY is read from contracts\.env automatically by forge (never typed here).
#
# Fill the four prerequisite addresses below, then run:  .\deploy-spot-vault.ps1
# (If scripts are disabled: Set-ExecutionPolicy -Scope Process Bypass -Force)

$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"

# ─── REQUIRED — fill these in ────────────────────────────────────────────────
# $env:UNDERLYING   = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"  # testnet WBTC mock (zBTC underlying)
# $env:CASH         = "0x..."   # USDC ERC-20 (cash leg)
# $env:ORACLE       = "0x..."   # Chainlink BTC/USD AggregatorV3 feed
# $env:SWAP_ADAPTER = "0x..."   # ISpotSwapAdapter (use a MOCK for shadow mode)

# ─── OPTIONAL (sensible defaults in the script) ──────────────────────────────
$env:KEEPER_ADDRESS        = "0x2251F2D8541f5D5263316E2921611c74D6d30D94"
$env:MAX_ORACLE_STALENESS  = "3600"   # MATCH the Chainlink feed heartbeat
$env:REBALANCE_THRESHOLD_BPS = "200"
$env:MAX_SLIPPAGE_BPS      = "100"
$env:PERFORMANCE_FEE_BPS   = "2000"   # 20%

$required = @("UNDERLYING","CASH","ORACLE","SWAP_ADAPTER")
$missing = $required | Where-Object { -not (Test-Path "env:$_") }
if ($missing) {
    Write-Host "Set these env vars first (edit this script or set inline):" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  `$env:$_ = `"0x...`"" }
    Write-Host "`nNOTE: SWAP_ADAPTER must be a deployed ISpotSwapAdapter. The production"
    Write-Host "CoreWriter spot adapter needs HyperCore docs + audit; for SHADOW mode"
    Write-Host "(deposit/withdraw/NAV only, no real fills) a mock adapter is fine."
    return
}

forge script script/DeploySpotVault.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

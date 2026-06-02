# Zentory SpotVault deploy (HyperEVM testnet, chain 998).
# PRIVATE_KEY is read from contracts\.env automatically by forge (never typed here).
#
# Fill the four prerequisite addresses below, then run:  .\deploy-spot-vault.ps1
# (If scripts are disabled: Set-ExecutionPolicy -Scope Process Bypass -Force)

$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"

# ─── REQUIRED — shadow-stack addresses (deployed 2026-06-02, on-chain verified) ──
$env:UNDERLYING   = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"  # testnet WBTC mock (zBTC underlying)
$env:CASH         = "0x2DF6A937da1430B4B593fE3EB2C9AB986cC3AF9e"  # ShadowUSDC (sUSDC, 6 dec)
$env:ORACLE       = "0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4"  # ShadowPriceOracle (BTC/USD, push-updated)
$env:SWAP_ADAPTER = "0x385Ba1f9A9d74A28974C8F6c03762D03B0e4a00c"  # ShadowSpotAdapter

# ─── OPTIONAL (sensible defaults in the script) ──────────────────────────────
$env:KEEPER_ADDRESS        = "0x2251F2D8541f5D5263316E2921611c74D6d30D94"
$env:MAX_ORACLE_STALENESS  = "86400"  # 24h — generous for the testnet shadow oracle (pushed ~4-hourly); a 1h staleness would make a flat vault revert. Mainnet: match the real Chainlink feed heartbeat.
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

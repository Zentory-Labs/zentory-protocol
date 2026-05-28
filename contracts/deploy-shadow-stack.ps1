# Deploy the testnet SHADOW stack (sUSDC + oracle + spot adapter).
# Then run deploy-spot-vault.ps1 with the addresses this prints.
# PRIVATE_KEY is read from contracts\.env automatically.

$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"

# ─── REQUIRED ────────────────────────────────────────────────────────────────
# $env:UNDERLYING = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"  # testnet WBTC mock

# ─── OPTIONAL ────────────────────────────────────────────────────────────────
$env:KEEPER_ADDRESS         = "0x2251F2D8541f5D5263316E2921611c74D6d30D94"
$env:INITIAL_PRICE_USD_8DEC = "10500000000000"   # $105,000 (BTC) -- set close to current
$env:SIMULATED_SLIPPAGE_BPS = "10"

if (-not $env:UNDERLYING) {
    Write-Host "Set `$env:UNDERLYING (the WBTC mock address) first." -ForegroundColor Yellow
    return
}

forge script script/DeployShadowStack.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

# ============================================================
# Zentory Protocol — E2E Simulation via cast (no forge deps)
# All actions signed by DEPLOYER_KEY (msg.sender = deployer)
# ============================================================

$RPC = "https://rpc.hyperliquid-testnet.xyz/evm"
$DEPLOYER_KEY = "0x0000000000000000000000000000000000000000000000000000000000000000-REDACTED-LEAKED-DEPLOYER-KEY"
$FOUNDRY_BIN = "$env:TEMP\foundry"

# ── Addresses ──────────────────────────────────────────────
$ZENT        = "0x271cd48c1297CacCD810c7B1BCD904f459df7117"
$WETH        = "0x80F727AF3f7932718fEb25FC28818Ad103040BD2"
$WBTC        = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"
$WXRP        = "0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371"
$WSOL        = "0x2b9d5bBD8C5FEfc71E985d993C13db2770469972"
$ZENTStaking = "0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65"
$zETH        = "0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e"
$zBTC        = "0x93669daC07321FF397cf5734Ae8364EA24addF45"
$zXRP        = "0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0"
$zSOL        = "0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052"

# Derive deployer address to confirm
$DEPLOYER = & "$FOUNDRY_BIN\cast.exe" wallet address $DEPLOYER_KEY
Write-Host "Deployer address: $DEPLOYER" -ForegroundColor Cyan

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ZENTORY PROTOCOL — E2E SIMULATION" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ── Step 1: Check balances ────────────────────────────────
Write-Host ""
Write-Host "[1/5] Checking deployer balances..." -ForegroundColor Yellow

$zentBal = & "$FOUNDRY_BIN\cast.exe" balance-of $ZENT $DEPLOYER --rpc-url $RPC
Write-Host "  ZENT: $([double]$zentBal / 1e18) ZENT" -ForegroundColor Gray

$wethBal = & "$FOUNDRY_BIN\cast.exe" balance-of $WETH $DEPLOYER --rpc-url $RPC
$wethDec = & "$FOUNDRY_BIN\cast.exe" call $WETH "decimals()" --rpc-url $RPC
$wethDec = [int]($wethDec -replace "0x[0-9a-fA-F]+","")
Write-Host "  WETH: $([double]$wethBal / [Math]::Pow(10,$wethDec)) WETH" -ForegroundColor Gray

# ── Step 2: Transfer ZENT to self ──────────────────────────
Write-Host ""
Write-Host "[2/5] Sending 750 ZENT to self (750 = 5 users x 150 ZENT)..." -ForegroundColor Yellow
$ZENT_TO_SEND = "750000000000000000000"  # 750 ZENT
& "$FOUNDRY_BIN\cast.exe" send $ZENT "transfer(address,uint256)" $DEPLOYER $ZENT_TO_SEND --private-key $DEPLOYER_KEY --rpc-url $RPC | Out-Null
$zentBal2 = & "$FOUNDRY_BIN\cast.exe" balance-of $ZENT $DEPLOYER --rpc-url $RPC
Write-Host "  ZENT after transfer: $([double]$zentBal2 / 1e18) ZENT" -ForegroundColor Green

# ── Step 3: Approve + stake ZENT ─────────────────────────
Write-Host ""
Write-Host "[3/5] Approving + staking 150 ZENT (minStake = 100 ZENT)..." -ForegroundColor Yellow

$ZENT_STAKE = "150000000000000000000"   # 150 ZENT
$LOCK_7D   = "604800"                  # 7 days

# Approve staking contract to pull ZENT
& "$FOUNDRY_BIN\cast.exe" send $ZENT "approve(address,uint256)" $ZENTStaking $ZENT_STAKE --private-key $DEPLOYER_KEY --rpc-url $RPC | Out-Null

# Stake
Write-Host "  Calling stake(150 ZENT, 7 days)..." -ForegroundColor Gray
& "$FOUNDRY_BIN\cast.exe" send $ZENTStaking "stake(uint256,uint64)" $ZENT_STAKE $LOCK_7D --private-key $DEPLOYER_KEY --rpc-url $RPC | Out-Null

$hasAccess = & "$FOUNDRY_BIN\cast.exe" call $ZENTStaking "hasAccess(address)" $DEPLOYER --rpc-url $RPC
$hasAccessStr = ($hasAccess -replace "\s+", "")[-1]
Write-Host "  hasAccess: $($hasAccessStr -eq '01' ? 'TRUE' : 'FALSE')" -ForegroundColor ($hasAccessStr -eq '01' ? 'Green' : 'Red')

$totalStaked = & "$FOUNDRY_BIN\cast.exe" call $ZENTStaking "totalStaked()" --rpc-url $RPC
$totalStaked = [double]($totalStaked.Trim() -replace "^0x", "") / 1e18
Write-Host "  totalStaked: $totalStaked ZENT" -ForegroundColor White

# ── Step 4: Mint vault assets to deployer + deposit ────────
Write-Host ""
Write-Host "[4/5] Minting vault assets + depositing into all 4 vaults..." -ForegroundColor Yellow

# Amounts per asset
$WETH_AMOUNT = "10000000000000000000"   # 10 ETH
$WBTC_AMOUNT = "100000000"              # 1 BTC (8 decimals)
$WSOL_AMOUNT = "100000000000000000000"   # 100 SOL
$WXRP_AMOUNT = "10000000000"            # 10,000 XRP (6 decimals)

function Invoke-MintAndDeposit($asset, $vault, $amount, $name) {
    Write-Host "  Processing $name..." -ForegroundColor Gray

    # Mint asset tokens to deployer
    $mintTx = & "$FOUNDRY_BIN\cast.exe" send $asset "mint(address,uint256)" $DEPLOYER $amount --private-key $DEPLOYER_KEY --rpc-url $RPC 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    [WARN] Mint failed (may not be mintable) — skipping deposit" -ForegroundColor DarkYellow
        return
    }

    # Approve vault to pull asset
    & "$FOUNDRY_BIN\cast.exe" send $asset "approve(address,uint256)" $vault $amount --private-key $DEPLOYER_KEY --rpc-url $RPC | Out-Null

    # Deposit into vault — receiver = DEPLOYER
    & "$FOUNDRY_BIN\cast.exe" send $vault "deposit(uint256,address)" $amount $DEPLOYER --private-key $DEPLOYER_KEY --rpc-url $RPC | Out-Null

    Write-Host "    $name deposited." -ForegroundColor Green
}

Invoke-MintAndDeposit $WETH $zETH $WETH_AMOUNT "zETH"
Invoke-MintAndDeposit $WBTC $zBTC $WBTC_AMOUNT "zBTC"
Invoke-MintAndDeposit $WSOL $zSOL $WSOL_AMOUNT "zSOL"
Invoke-MintAndDeposit $WXRP $zXRP $WXRP_AMOUNT "zXRP"

# ── Step 5: Final state ─────────────────────────────────
Write-Host ""
Write-Host "[5/5] Final state:" -ForegroundColor Yellow

function Get-VaultTVL($vault, $asset, $label) {
    $tvlHex = & "$FOUNDRY_BIN\cast.exe" call $vault "totalAssets()" --rpc-url $RPC
    $decHex = & "$FOUNDRY_BIN\cast.exe" call $asset "decimals()" --rpc-url $RPC
    $dec = [int]($decHex -replace "^0x0*", "")
    if ($dec -eq 0) { $dec = 18 }
    $tvl = [double]($tvlHex -replace "^0x0*", "") / [Math]::Pow(10, $dec)
    Write-Host "  $label TVL: $tvl" -ForegroundColor White
}

Get-VaultTVL $zETH $WETH "zETH"
Get-VaultTVL $zBTC $WBTC "zBTC"
Get-VaultTVL $zSOL $WSOL "zSOL"
Get-VaultTVL $zXRP $WXRP "zXRP"

$totalStaked2 = & "$FOUNDRY_BIN\cast.exe" call $ZENTStaking "totalStaked()" --rpc-url $RPC
Write-Host "  ZENT Staked: $([double]($totalStaked2 -replace '^0x0*', '') / 1e18) ZENT" -ForegroundColor White

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SIMULATION COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Refresh the frontend — ChainStats + VaultCards" -ForegroundColor White
Write-Host "will now show live non-zero values." -ForegroundColor White
Write-Host ""

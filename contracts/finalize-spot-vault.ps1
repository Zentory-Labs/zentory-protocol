# Finalize the SHADOW-mode SpotVault so deposits/redeems + the signal-driven
# rebalance loop work end-to-end. Run ONCE, after deploy-spot-vault.ps1.
# Does three things in a single broadcast (PRIVATE_KEY read from contracts\.env):
#   1. grants VAULT_ROLE on the adapter -> the SpotVault
#   2. funds both adapter reserve legs (sUSDC + WBTC)
#   3. seeds the first deposit (anchors the ERC4626 share price)
#
# (If scripts are disabled: Set-ExecutionPolicy -Scope Process Bypass -Force)

$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"

# ─── Addresses (deployed + on-chain verified 2026-06-02) ─────────────────────
$env:SPOT_VAULT   = "0x504E998B32D165cfd6470a8a0000235550C33cBc"  # SpotVault (shadow)
$env:SWAP_ADAPTER = "0x385Ba1f9A9d74A28974C8F6c03762D03B0e4a00c"  # ShadowSpotAdapter
$env:CASH         = "0x2DF6A937da1430B4B593fE3EB2C9AB986cC3AF9e"  # ShadowUSDC (sUSDC, 6 dec)
$env:UNDERLYING   = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"  # WBTC mock (8 dec) = vault asset

# ─── OPTIONAL reserve sizing (sensible testnet defaults in the script) ───────
# $env:CASH_RESERVE  = "50000000000000"  # 50,000,000 sUSDC (6 dec)
# $env:UNDER_RESERVE = "100000000000"    # 1,000 WBTC (8 dec)
# $env:SEED_ASSETS   = "1000000"         # 0.01 WBTC (8 dec)

forge script script/FinalizeSpotVault.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

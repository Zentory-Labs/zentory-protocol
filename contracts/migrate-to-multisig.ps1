# Migrate ZENTORY admin control from the hot-wallet admin to a Gnosis Safe
# multisig (HyperEVM testnet, chain 998).
#
# Runs script/MigrateToMultisig.s.sol. The migration is TWO-PHASE and SAFE:
#   PHASE 1 (default)        : grant DEFAULT_ADMIN_ROLE to the Safe. The hot
#                              wallet KEEPS admin. Fully reversible.
#   PHASE 2 (RENOUNCE_OLD)   : renounce the hot wallet's admin (only where the
#                              Safe already verifiably holds it).
#   Timelock renounce        : additionally gated behind RENOUNCE_TIMELOCK so
#                              you cannot relinquish Timelock admin by accident.
#
# PRIVATE_KEY (the CURRENT hot-wallet admin key) is read from contracts\.env
# automatically by forge — you never type it here.
#
# HOW TO RUN (from PowerShell, in this folder):
#     cd "C:\Users\juan\OneDrive\Documents\GitHub\ZENTORY LABS\zentory-protocol\contracts"
#     # Phase 1 — grant only (reversible):
#     $env:NEW_ADMIN = "0x<your-gnosis-safe-address>"
#     .\migrate-to-multisig.ps1
#
#     # Phase 2 — renounce hot wallet (after verifying the Safe works), Timelock spared:
#     $env:NEW_ADMIN = "0x<your-gnosis-safe-address>"; $env:RENOUNCE_OLD = "true"
#     .\migrate-to-multisig.ps1
#
#     # Final — renounce Timelock admin too (only once ZentGovernor proposer wiring is proven):
#     $env:RENOUNCE_OLD = "true"; $env:RENOUNCE_TIMELOCK = "true"
#     .\migrate-to-multisig.ps1
#
# (If scripts are disabled: Set-ExecutionPolicy -Scope Process Bypass -Force)
#
# NOTE: this DOES broadcast (it sends the grant/renounce txs). Dry-run first by
# running the forge command at the bottom WITHOUT --broadcast, or read the
# console2 plan it prints. Re-running is idempotent (skips no-ops).

$ErrorActionPreference = "Stop"

# 1. Put Foundry on PATH for this session (forge.exe lives here).
$env:PATH += ";$env:USERPROFILE\.foundry\bin"

# 2. Chain guard. The script reverts unless block.chainid == 998.
$env:EXPECTED_CHAIN_ID = "998"

# 3. Required: the Gnosis Safe address receiving admin. Read from env (set it
#    before calling this script) or from .env via forge. We surface a clear
#    error if it's missing rather than letting forge fail opaquely.
if (-not (Test-Path "env:NEW_ADMIN")) {
    # Allow NEW_ADMIN to live in .env instead of the shell env.
    $hasEnvFile = (Test-Path ".env") -and (Get-Content ".env" | Where-Object { $_ -match '^\s*NEW_ADMIN\s*=' })
    if (-not $hasEnvFile) {
        Write-Host "NEW_ADMIN is not set. Provide the Gnosis Safe address first:" -ForegroundColor Yellow
        Write-Host '    $env:NEW_ADMIN = "0x<your-gnosis-safe-address>"'
        Write-Host "  (or add NEW_ADMIN=0x... to contracts\.env)"
        return
    }
}

# 4. Phase flags. Default = Phase 1 (grant only). Echo what we're about to do.
if (-not (Test-Path "env:RENOUNCE_OLD"))      { $env:RENOUNCE_OLD = "false" }
if (-not (Test-Path "env:RENOUNCE_TIMELOCK")) { $env:RENOUNCE_TIMELOCK = "false" }

$phase = if ($env:RENOUNCE_OLD -eq "true") { "2 (GRANT verify + RENOUNCE hot wallet)" } else { "1 (GRANT only - reversible)" }

Write-Host "forge: $((Get-Command forge).Source)"
forge --version

# 5. Pick the RPC. The public endpoint is flaky for forge's simulate step, so
#    prefer the Alchemy URL from keeper\.env if present. The URL (which contains
#    the API key) is read at runtime and never printed or committed.
$rpc = "https://rpc.hyperliquid-testnet.xyz/evm"
$keeperEnv = "keeper\.env"
if (Test-Path $keeperEnv) {
    $line = Get-Content $keeperEnv | Where-Object { $_ -match '^HYPEREVM_RPC_URL=' } | Select-Object -First 1
    if ($line) {
        $rpc = ($line -replace '^HYPEREVM_RPC_URL=', '').Trim().Trim('"')
        Write-Host "Using Alchemy RPC from keeper\.env (more reliable than the public endpoint)."
    }
}

Write-Host ""
Write-Host "Migrating admin control to the Gnosis Safe on HyperEVM testnet (chain 998)..."
Write-Host "  Phase            : $phase"
if ($env:RENOUNCE_OLD -eq "true") {
    Write-Host "  Renounce Timelock: $($env:RENOUNCE_TIMELOCK)"
}
Write-Host "  PRIVATE_KEY (hot wallet) is read from .env automatically."
Write-Host ""

# 6. Broadcast. forge auto-loads .env for PRIVATE_KEY (and NEW_ADMIN if set there).
#    --slow --legacy mirror the rotation/deploy scripts' broadcast flags.
forge script script/MigrateToMultisig.s.sol `
  --rpc-url $rpc `
  --broadcast --slow --legacy

Write-Host ""
Write-Host "============================================================"
if ($env:RENOUNCE_OLD -eq "true") {
    Write-Host "PHASE 2 complete. Hot wallet relinquished admin where the Safe"
    Write-Host "verifiably held it. Verify with the cast hasRole checks above."
} else {
    Write-Host "PHASE 1 complete (grant only). The hot wallet STILL holds admin."
    Write-Host "VERIFY the Safe works, then re-run with RENOUNCE_OLD=true."
}
Write-Host "============================================================"

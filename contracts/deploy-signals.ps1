# Redeploy the ZENTORY signal network (SignalRegistry + EpochScoring +
# SubscriptionVault) from current source, with all cross-contract roles wired.
#
# WHY: the live signal contracts are version-mismatched (the deployed
# SignalRegistry predates getSignalCount/advanceEpoch), so EpochScoring.
# settleEpoch() reverts and the keeper loop is stalled at epoch 1. A fresh
# deploy with the corrected role wiring fixes it.
#
# HOW TO RUN (from PowerShell, in this folder):
#     cd "C:\Users\juan\OneDrive\Documents\GitHub\ZENTORY LABS\zentory-protocol\contracts"
#     .\deploy-signals.ps1
#
# Your deployer key, ZENT address and staking address are read automatically
# from .env by forge — you never type them here. You only need the deployer
# wallet to hold a little testnet HYPE for gas.

$ErrorActionPreference = "Stop"

# 1. Put Foundry on PATH for this session (forge.exe lives here).
$env:PATH += ";$env:USERPROFILE\.foundry\bin"

# 2. The two settings not already in .env.
$env:EXPECTED_CHAIN_ID = "998"                                          # ChainGuard guard
$env:KEEPER_ADDRESS    = "0x2251F2D8541f5D5263316E2921611c74D6d30D94"   # keeper bot wallet

Write-Host "forge: $((Get-Command forge).Source)"
forge --version

# 3. Pick the RPC. The public rpc.hyperliquid-testnet.xyz endpoint is flaky for
#    forge's fork/simulate step ("invalid block height"), so prefer the Alchemy
#    URL from keeper\.env if present. The URL (which contains the API key) is
#    read at runtime and never printed or committed.
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
Write-Host "Deploying signal network to HyperEVM testnet (chain 998)..."
Write-Host "PRIVATE_KEY / ZENT_ADDRESS / STAKING_ADDRESS are read from .env automatically."
Write-Host ""

# 4. Deploy. forge auto-loads .env for PRIVATE_KEY/ZENT_ADDRESS/STAKING_ADDRESS.
#    No --private-key flag needed: the script broadcasts with PRIVATE_KEY from env.
forge script script/deploy_signal_network.s.sol `
  --rpc-url $rpc `
  --broadcast

Write-Host ""
Write-Host "============================================================"
Write-Host "DONE. Copy the three addresses printed above:"
Write-Host "  SIGNAL_REGISTRY=, EPOCH_SCORING=, SUBSCRIPTION_VAULT="
Write-Host "and paste them back so the dApp + keeper get repointed."
Write-Host "============================================================"

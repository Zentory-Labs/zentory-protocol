# One-time fix for the SignalRegistry/EpochScoring epoch off-by-one: bump the
# registry's currentEpochId up to equal EpochScoring's, so settleEpoch reads the
# bucket where new signals are filed and scoring actually fires. Temporarily grants
# SCORING_ORACLE to the admin EOA, advances, and revokes (net role state unchanged).
# Run by the registry DEFAULT_ADMIN_ROLE holder; PRIVATE_KEY read from contracts\.env.
$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"
$env:SIGNAL_REGISTRY = "0x9685F25E75758E18b2b109be64271102497D800e"
$env:EPOCH_SCORING   = "0x31b7082f1e1B3cC373dE3d9c3575701b9aa24538"

forge script script/ReSyncSignalEpoch.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

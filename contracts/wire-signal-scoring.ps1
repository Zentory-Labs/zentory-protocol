# Activate on-chain signal scoring: point EpochScoring's reference-asset price
# feed at the ShadowPriceOracle (one admin txn). Run by the EpochScoring
# DEFAULT_ADMIN_ROLE holder; PRIVATE_KEY read from contracts\.env. Idempotent.
$env:PATH += ";$env:USERPROFILE\.foundry\bin"
$env:EXPECTED_CHAIN_ID = "998"

$env:EPOCH_SCORING = "0x659569A6f195698745779E59fef88e3B5Fe0484A"  # EpochScoring
$env:ORACLE        = "0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4"  # ShadowPriceOracle (push-updated)

forge script script/WireSignalScoring.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

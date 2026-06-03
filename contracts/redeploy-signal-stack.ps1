# Fresh redeploy of the signal scoring stack (ZENTStaking + SignalRegistry +
# EpochScoring) from current source, with all roles + the BTC price feed wired in
# one broadcast. Fixes the stale-staking blocker (getProviderStake reverts for
# unstaked providers → keeper bricks on the first real signal), keeps the epoch
# counters aligned at genesis, and revokes the deployer's bootstrap SCORING_ORACLE.
#
# KEEPS the existing SubscriptionVault + ZENT + vaults (independent of the stack).
# Run by the deployer; PRIVATE_KEY is read from contracts\.env (Foundry auto-loads).
# After it prints the 3 new addresses, follow REDEPLOY_SIGNAL_STACK.md to re-point
# the keeper / engine / dApp / docs, then redeploy the keeper service.
$env:PATH += ";$env:USERPROFILE\.foundry\bin"

forge script script/RedeploySignalStack.s.sol `
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

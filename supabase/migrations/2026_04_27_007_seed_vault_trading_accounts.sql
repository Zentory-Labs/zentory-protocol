-- Seed vault → Hyperliquid trading wallet mapping (replace hl_user_address with live wallets).
insert into public.vault_trading_accounts (vault_address, hl_user_address, asset, notes)
values
  (
    '0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e',
    '0x0000000000000000000000000000000000000001',
    'ETH',
    'Update hl_user_address to the Hyperliquid user (testnet) for zETH.'
  ),
  (
    '0x93669daC07321FF397cf5734Ae8364EA24addF45',
    '0x0000000000000000000000000000000000000001',
    'BTC',
    'Update hl_user_address to the Hyperliquid user (testnet) for zBTC.'
  ),
  (
    '0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0',
    '0x0000000000000000000000000000000000000001',
    'XRP',
    'Update hl_user_address to the Hyperliquid user (testnet) for zXRP.'
  ),
  (
    '0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052',
    '0x0000000000000000000000000000000000000001',
    'SOL',
    'Update hl_user_address to the Hyperliquid user (testnet) for zSOL.'
  )
on conflict (vault_address) do nothing;

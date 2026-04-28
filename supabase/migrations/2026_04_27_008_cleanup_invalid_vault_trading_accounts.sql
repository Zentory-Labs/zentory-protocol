-- Drop mistaken rows where vault_address was a label (e.g. "0x…zBTC…") instead of the contract hex.
-- Valid vault addresses are exactly: 0x + 40 hexadecimal characters.
delete from public.vault_trading_accounts
where vault_address !~ '^0x[0-9a-fA-F]{40}$';

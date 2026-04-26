"""Signal generator — produces signed TradeSignal dicts for StrategyExecutor."""
from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass
from typing import Optional

from genetic_programming.chromosome import Chromosome
from strategy.trend_follower import Direction, generate_signal


@dataclass
class TradeSignal:
    """A signed trade signal to be submitted to StrategyExecutor."""

    vault: str           # vault contract address
    direction: int      # 1=long, 0=short, 2=close
    size: int           # raw size (e.g. 1000000 = 1 BTC at 6 decimals)
    price: int          # limit price in 10^8 format (e.g. 6500000000 = $65,000)
    nonce: int          # unique per-vault nonce
    expiry: int         # unix timestamp after which signal is invalid
    signature: str      # hex ECDSA signature over signal digest

    def to_bytes(self) -> bytes:
        """Encode signal for signing: keccak256(domain, vault, direction, size, nonce, expiry)."""
        return b"".join([
            self.vault.encode(),
            str(self.direction).encode(),
            str(self.size).encode(),
            str(self.price).encode(),
            str(self.nonce).encode(),
            str(self.expiry).encode(),
        ])

    def digest(self, domain_separator: bytes) -> bytes:
        """Full EIP-712 digest: keccak256(domain || encoding(self))."""
        return hashlib.sha256(domain_separator + self.to_bytes()).digest()


def build_signal(
    chrom: Chromosome,
    prices: list[float],
    vault_address: str,
    nonce: int,
    expiry_seconds: int = 300,
    priv_key: Optional[str] = None,
) -> TradeSignal:
    """
    Generate a TradeSignal from the elite chromosome and current market data.

    Parameters
    ----------
    chrom : Chromosome
        The elite strategy chromosome.
    prices : list[float]
        Recent price series (most recent = last).
    vault_address : str
        Target vault contract address.
    nonce : int
        Current nonce for this vault (from StrategyExecutor.nonces()).
    expiry_seconds : int
        Signal validity window (default 5 min).
    priv_key : str, optional
        Private key for ECDSA signing (hex). If None, signature is empty (testing mode).
    """
    import numpy as np

    prices_arr = np.array(prices, dtype=np.float64)
    signal = generate_signal(chrom, prices_arr)

    direction_map = {Direction.LONG: 1, Direction.SHORT: 0, Direction.CLOSE: 2}
    direction = direction_map[signal.direction]

    # Size: use position size gene (0.05–1.0 fraction) as a fraction of a notional unit
    # We use a fixed base size of 1_000_000 (1 BTC at 6 decimals)
    base_size = 1_000_000
    pos_pct = max(chrom.gene_named("position_size_pct"), 0.05)
    size = int(base_size * pos_pct)

    # Price: use current price as limit price
    current_price = prices[-1]
    # Convert to HyperCore format: price_10_8 = human_price * 1e8
    # e.g. $65,000 → 6_500_000_000
    price_10_8 = int(current_price * 1e8)

    expiry = int(time.time()) + expiry_seconds

    sig_hex = ""
    if priv_key:
        sig_hex = _sign_signal(
            priv_key=priv_key,
            vault=vault_address,
            direction=direction,
            size=size,
            nonce=nonce,
            expiry=expiry,
        )

    return TradeSignal(
        vault=vault_address,
        direction=direction,
        size=size,
        price=price_10_8,
        nonce=nonce,
        expiry=expiry,
        signature=sig_hex,
    )


# ─── ECDSA signing ──────────────────────────────────────────────────────────

def _sign_signal(
    priv_key: str,
    vault: str,
    direction: int,
    size: int,
    nonce: int,
    expiry: int,
) -> str:
    """Sign a signal digest using eth-account. Returns hex signature."""
    from eth_account import Account
    from eth_hash.auto import keccak

    # Build the same digest as StrategyExecutor._getVotes
    # domain = chainId + address(executor)
    # For test: chainId=31337 (Foundry), executor=vault (placeholder)
    # In production the executor is the StrategyExecutor address

    payload = vault + str(direction) + str(size) + str(nonce) + str(expiry)
    msg_hash = keccak(payload.encode())

    acct = Account.from_key(priv_key)
    signed = acct.sign_hash(msg_hash)
    return signed.signature.hex()


def signal_to_payload(sig: TradeSignal) -> dict:
    """Serialize a TradeSignal to a dict matching StrategyExecutor.executeSignal params."""
    return {
        "vault":     sig.vault,
        "direction": sig.direction,
        "size":      sig.size,
        "price":     sig.price,
        "nonce":     sig.nonce,
        "expiry":    sig.expiry,
        "signature":  sig.signature,
    }

"""GPProvider — ISignalProvider backed by the elite genetic-programming chromosome."""
from __future__ import annotations

from typing import Optional

import numpy as np

from genetic_programming.chromosome import Chromosome
from strategy.signal_generator import generate_signal
from strategy.trend_follower import Direction as GPDirection

from .interface import Direction, ISignalProvider, SignalBatch, TradingSignal


class GPProvider(ISignalProvider):
    """
    Signal provider that runs the elite GP chromosome against live price data.

    The elite chromosome is set once per generation via :meth:`set_elite_chromosome`.
    Until a chromosome is set, :meth:`get_signals` returns an empty batch.
    """

    name: str = "gp"

    def __init__(
        self,
        vault_addresses: dict[str, str],
        *,
        default_size: int = 1_000_000,
        default_price_10_8: int = 0,
    ) -> None:
        """
        Parameters
        ----------
        vault_addresses : dict[str, str]
            Mapping from asset symbol to vault contract address.
            Example: ``{"BTC": "0x...btc_vault", "ETH": "0x...eth_vault"}``.
        default_size : int
            Base size in vault decimal units (default 1_000_000 = 1 BTC at 6 decimals).
        default_price_10_8 : int
            Default limit price in 10^8 format when no price is available.
        """
        self._vault_addresses: dict[str, str] = vault_addresses
        self._elite_chromosome: Optional[Chromosome] = None
        self._default_size = default_size
        self._default_price_10_8 = default_price_10_8

    def set_elite_chromosome(self, chrom: Chromosome) -> None:
        """Set the current generation's elite chromosome for signal generation."""
        self._elite_chromosome = chrom

    def preferred_size_fraction(self) -> float:
        """GP strategies use 50 % of vault TVL by default."""
        return 0.5

    async def get_signals(
        self,
        vault_addresses: list[str],
        prices: dict[str, float],
        **kwargs,
    ) -> SignalBatch:
        """
        Generate trading signals using the elite chromosome.

        Parameters
        ----------
        vault_addresses : list[str]
            Vault contract addresses to generate signals for.
        prices : dict[str, float]
            Current prices keyed by asset symbol (e.g. ``{"BTC": 65000.0}``).

        Returns
        -------
        SignalBatch
            Batch of ``TradingSignal`` objects, one per vault.
        """
        if self._elite_chromosome is None:
            return SignalBatch(signals=[], provider=self.name, evaluated_at=int(__import__("time").time()))

        import time

        signals: list[TradingSignal] = []

        for vault_address in vault_addresses:
            asset_symbol = self._asset_for_vault(vault_address)
            if asset_symbol is None or asset_symbol not in prices:
                continue

            price_float = prices[asset_symbol]
            prices_array = np.array([price_float], dtype=np.float64)

            gp_signal = generate_signal(self._elite_chromosome, prices_array)

            direction = self._map_direction(gp_signal.direction)

            # Use position_size_pct gene to scale base size, default to 50 %
            pos_pct = max(self._elite_chromosome.gene_named("position_size_pct"), 0.05)
            size = int(self._default_size * pos_pct)

            # Convert human price to 10^8 format
            price_10_8 = int(price_float * 1e8) if price_float > 0 else self._default_price_10_8

            signals.append(
                TradingSignal(
                    vault=vault_address,
                    direction=direction,
                    size=size,
                    price=price_10_8,
                    confidence=gp_signal.confidence,
                    metadata={"reason": gp_signal.reason, "provider": self.name},
                )
            )

        evaluated_at = int(time.time())
        return SignalBatch(signals=signals, provider=self.name, evaluated_at=evaluated_at)

    # ── helpers ────────────────────────────────────────────────────────────────

    def _asset_for_vault(self, vault_address: str) -> Optional[str]:
        """Reverse-lookup asset symbol from vault address."""
        for symbol, addr in self._vault_addresses.items():
            if addr.lower() == vault_address.lower():
                return symbol
        return None

    @staticmethod
    def _map_direction(gp_dir: GPDirection) -> Direction:
        """Map trend_follower Direction → interface Direction."""
        mapping = {
            GPDirection.LONG:  Direction.LONG,   # 1 → 1
            GPDirection.SHORT: Direction.SHORT,  # -1 → 0
            GPDirection.CLOSE: Direction.CLOSE,  # 0 → 2
        }
        return mapping[gp_dir]

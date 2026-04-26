"""Signal abstraction layer — ISignalProvider interface and concrete implementations."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import IntEnum


class Direction(IntEnum):
    """Trade direction matching StrategyExecutor."""

    LONG = 1
    SHORT = 0
    CLOSE = 2


@dataclass
class TradingSignal:
    """
    A single trading signal — direction, size, and price.
    Provider-agnostic; converted to a TradeSignal before on-chain submission.
    """

    vault: str  # Vault contract address (checksummed)
    direction: Direction
    size: int  # Asset units in vault's decimal representation (e.g. satoshis for BTC)
    price: int  # Limit price in 10^8 format (e.g. 6_500_000_000 for $65,000 BTC)
    confidence: float = 1.0  # 0.0–1.0 signal confidence (used for position sizing)
    metadata: dict = field(default_factory=dict)  # Provider-specific data (for logging/audit)


@dataclass
class SignalBatch:
    """
    A batch of signals from a provider for one evaluation cycle.
    May contain signals for multiple vaults.
    """

    signals: list[TradingSignal]
    provider: str  # "lumibot", "gp", "manual"
    evaluated_at: int  # Unix timestamp
    metadata: dict = field(default_factory=dict)


class ISignalProvider(ABC):
    """
    Abstract signal provider.

    Implementations: LumibotProvider, GPProvider, ManualProvider.
    All providers produce SignalBatch objects that the SignalRouter converts
    to on-chain TradeSignals before submission to StrategyExecutor.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable provider name."""
        ...

    @abstractmethod
    async def get_signals(
        self,
        vault_addresses: list[str],
        prices: dict[str, float],
        **kwargs,
    ) -> SignalBatch:
        """
        Generate trading signals for the given vaults and price data.

        Parameters
        ----------
        vault_addresses : list[str]
            Vault contract addresses to generate signals for.
        prices : dict[str, float]
            Current prices keyed by asset symbol (e.g. {"BTC": 65000.0, "ETH": 3500.0}).
        **kwargs : dict
            Provider-specific parameters (e.g. lookback for Lumibot, generation for GP).

        Returns
        -------
        SignalBatch
            Batch containing TradingSignal objects for each vault.
        """
        ...

    @abstractmethod
    def preferred_size_fraction(self) -> float:
        """
        Fraction of vault TVL to use as base position size (0.0–1.0).
        Manual provider returns 1.0 (full conviction by operator).
        """
        ...

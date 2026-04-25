"""ManualProvider — ISignalProvider for operator-managed signal submission."""
from __future__ import annotations

import time
from typing import List

from .interface import ISignalProvider, SignalBatch, TradingSignal


class ManualProvider(ISignalProvider):
    """
    Phase-1 operator signal provider.

    Signals are queued manually via :meth:`add_signal` and returned as a batch
    on the next call to :meth:`get_signals`. After a batch is returned the
    pending queue is cleared (signals are consumed).
    """

    name: str = "manual"

    def __init__(self, pending_signals: List[TradingSignal] | None = None) -> None:
        """
        Parameters
        ----------
        pending_signals : list[TradingSignal], optional
            Initial queue of signals awaiting operator review.
        """
        self._pending_signals: list[TradingSignal] = list(pending_signals) if pending_signals else []

    def add_signal(self, sig: TradingSignal) -> None:
        """Add a signal to the pending review queue."""
        self._pending_signals.append(sig)

    def preferred_size_fraction(self) -> float:
        """Operator has full conviction — use 100 % of vault TVL."""
        return 1.0

    def pending_count(self) -> int:
        """Number of signals currently awaiting submission."""
        return len(self._pending_signals)

    async def get_signals(
        self,
        vault_addresses: list[str],
        prices: dict[str, float],
        **kwargs,
    ) -> SignalBatch:
        """
        Return and consume all pending signals.

        Parameters
        ----------
        vault_addresses : list[str]
            Ignored for manual provider (signals carry their own vault address).
        prices : dict[str, float]
            Ignored for manual provider.

        Returns
        -------
        SignalBatch
            Batch containing all pending signals; the queue is cleared afterwards.
        """
        evaluated_at = int(time.time())
        batch = SignalBatch(
            signals=list(self._pending_signals),
            provider=self.name,
            evaluated_at=evaluated_at,
        )
        self._pending_signals.clear()
        return batch

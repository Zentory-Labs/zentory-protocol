"""Signal abstraction layer — providers, routing, and on-chain execution."""
from __future__ import annotations

from .executor import SignalExecutor
from .gp_provider import GPProvider
from .interface import Direction, ISignalProvider, SignalBatch, TradingSignal
from .lumibot_provider import LumibotProvider
from .manual_provider import ManualProvider
from .router import SignalRouter, SignedSignalPayload
from .signer import SignalSigner

__all__ = [
    "Direction",
    "EXECUTOR_ABI",
    "GPProvider",
    "ISignalProvider",
    "LumibotProvider",
    "ManualProvider",
    "SignalBatch",
    "SignalExecutor",
    "SignalRouter",
    "SignalSigner",
    "SignedSignalPayload",
    "TradingSignal",
]

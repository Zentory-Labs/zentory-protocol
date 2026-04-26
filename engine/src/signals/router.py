"""SignalRouter — converts SignalBatch objects into signed, on-chain executable payloads."""
from __future__ import annotations

import time
from typing import TypedDict

from .interface import SignalBatch
from .signer import SignalSigner


class SignedSignalPayload(TypedDict):
    """Single signed signal ready for StrategyExecutor.executeSignal."""

    vault: str
    direction: int
    size: int
    price: int
    nonce: int
    expiry: int
    signature: str


class SignalRouter:
    """
    Signs and serialises a ``SignalBatch`` into a list of execution payloads
    ready to be submitted to ``StrategyExecutor``.

    Parameters
    ----------
    signer : SignalSigner
        EIP-712 signer used to produce ECDSA signatures.
    strategy_executor : str
        StrategyExecutor contract address (checksummed).
    chain_id : int
        Chain ID used in the EIP-712 domain separator.
    expiry_seconds : int, optional
        Validity window for each signal in seconds. Subclassed by GP router
        for shorter windows; defaults to 3600 (1 hour).
    """

    expiry_seconds: int = 3600  # 1-hour window for manual signals

    def __init__(
        self,
        signer: SignalSigner,
        strategy_executor: str,
        chain_id: int,
        *,
        expiry_seconds: int | None = None,
    ) -> None:
        self._signer = signer
        self._executor = strategy_executor
        self._chain_id = chain_id
        if expiry_seconds is not None:
            self.expiry_seconds = expiry_seconds

    def route(self, batch: SignalBatch, nonces: dict[str, int]) -> list[SignedSignalPayload]:
        """
        Convert a ``SignalBatch`` into signed payloads for each signal.

        Parameters
        ----------
        batch : SignalBatch
            The batch of signals to route.
        nonces : dict[str, int]
            Per-vault nonce map from ``StrategyExecutor.nonces()``.
            Keys must match the vault addresses in ``batch.signals``.

        Returns
        -------
        list[SignedSignalPayload]
            One dict per signal with all fields required by
            ``StrategyExecutor.executeSignal``.
        """
        now = int(time.time())
        expiry = now + self.expiry_seconds
        payloads: list[SignedSignalPayload] = []

        for signal in batch.signals:
            vault = signal.vault
            nonce = nonces.get(vault, 0)

            sig_hex = self._signer.sign_hex(
                vault=vault,
                direction=signal.direction,
                size=signal.size,
                nonce=nonce,
                expiry=expiry,
                chain_id=self._chain_id,
                executor_address=self._executor,
            )

            payloads.append(
                {
                    "vault": vault,
                    "direction": int(signal.direction),
                    "size": signal.size,
                    "price": signal.price,
                    "nonce": nonce,
                    "expiry": expiry,
                    "signature": sig_hex,
                }
            )

        return payloads

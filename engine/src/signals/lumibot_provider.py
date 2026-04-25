"""LumibotProvider — ISignalProvider integrating the Lumibot algorithmic trading broker."""
from __future__ import annotations

import time

from .interface import ISignalProvider, SignalBatch


class LumibotProvider(ISignalProvider):
    """
    Signal provider backed by Lumibot's broker API.

    Parameters
    ----------
    api_key : str
        Lumibot API key.
    api_secret : str
        Lumibot API secret.
    paper_mode : bool
        If True, operates in paper-trading mode without real capital (default True).

    Note
    ----
    The Lumibot broker integration (``lumibot_client``) is not yet available.
    :meth:`get_signals` currently returns an empty batch. Once the Lumibot
    broker API is ready, replace the stub implementation in :meth:`get_signals`
    with live API calls.
    """

    name: str = "lumibot"

    def __init__(
        self,
        api_key: str,
        api_secret: str,
        *,
        paper_mode: bool = True,
    ) -> None:
        self._api_key = api_key
        self._api_secret = api_secret
        self._paper_mode = paper_mode

    def preferred_size_fraction(self) -> float:
        """Lumibot strategies use 75 % of vault TVL to leave room for risk management."""
        return 0.75

    async def get_signals(
        self,
        vault_addresses: list[str],
        prices: dict[str, float],
        **kwargs,
    ) -> SignalBatch:
        """
        Generate trading signals from Lumibot's broker API.

        Parameters
        ----------
        vault_addresses : list[str]
            Vault contract addresses to generate signals for.
        prices : dict[str, float]
            Current prices keyed by asset symbol (e.g. ``{"BTC": 65000.0}``).
        **kwargs : dict
            Additional parameters passed through to the Lumibot broker API
            (e.g. ``lookback`` for lookback window).

        Returns
        -------
        SignalBatch
            Batch of signals produced by Lumibot, or an empty batch if the
            broker API is not yet available.
        """
        # TODO: integrate lumibot_client when Lumibot broker API is ready
        # from lumibot import Lumibot
        #
        # broker = Lumibot(
        #     api_key=self._api_key,
        #     api_secret=self._api_secret,
        #     paper=self._paper_mode,
        # )
        # signals = broker.get_signals(asset=asset_symbol, prices=prices, **kwargs)
        # return SignalBatch(signals=signals, provider=self.name, evaluated_at=int(time.time()))

        # Stub: return empty batch until Lumibot integration is complete
        return SignalBatch(signals=[], provider=self.name, evaluated_at=int(time.time()))

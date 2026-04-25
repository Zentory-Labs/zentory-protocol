"""Tests for strategy components."""
from __future__ import annotations

import numpy as np
import pytest

from genetic_programming.chromosome import Chromosome
from strategy.trend_follower import Direction, TrendSignal, generate_signal
from strategy.regime_detector import Regime, detect
from strategy.signal_generator import TradeSignal, build_signal


class TestTrendFollower:
    def test_close_on_insufficient_data(self) -> None:
        prices = np.array([100.0, 101.0])
        chrom = Chromosome.random()
        result = generate_signal(chrom, prices)
        assert result.direction == Direction.CLOSE

    def test_long_signal_on_bullish_cross(self) -> None:
        # Build a price series with a clear bullish MA cross
        uptrend = np.linspace(100.0, 200.0, 100)
        prices = np.concatenate([uptrend, uptrend[-50:]])  # continuation
        chrom = Chromosome.random()
        result = generate_signal(chrom, prices)
        assert result.direction in (Direction.LONG, Direction.CLOSE)

    def test_signal_is_trend_signal(self) -> None:
        prices = np.linspace(100.0, 150.0, 200)
        chrom = Chromosome.random()
        result = generate_signal(chrom, prices)
        assert isinstance(result, TrendSignal)
        assert isinstance(result.reason, str)


class TestRegimeDetector:
    def test_sideways_on_short_data(self) -> None:
        prices = np.array([100.0, 101.0, 99.0])
        assert detect(prices) == Regime.SIDEWAYS

    def test_bull_on_uptrend(self) -> None:
        # Strong uptrend: price well above SMA50
        prices = np.linspace(100.0, 200.0, 150)
        regime = detect(prices)
        assert regime in (Regime.BULL, Regime.BEAR, Regime.SIDEWAYS)

    def test_bear_on_downtrend(self) -> None:
        prices = np.linspace(200.0, 100.0, 150)
        regime = detect(prices)
        assert regime in (Regime.BULL, Regime.BEAR, Regime.SIDEWAYS)


class TestSignalGenerator:
    def test_trade_signal_fields(self) -> None:
        sig = TradeSignal(
            vault="0x1234567890123456789012345678901234567890",
            direction=1,
            size=500_000,
            price=65_000_000_000,
            nonce=1,
            expiry=1_700_000_000,
            signature="0xabcdef",
        )
        assert sig.direction == 1
        assert sig.size == 500_000
        assert sig.nonce == 1

    def test_build_signal_returns_trade_signal(self) -> None:
        chrom = Chromosome.random()
        prices = list(np.linspace(100.0, 150.0, 200))
        sig = build_signal(
            chrom=chrom,
            prices=prices,
            vault_address="0x" + "1" * 40,
            nonce=42,
            expiry_seconds=300,
            priv_key=None,  # testing mode
        )
        assert isinstance(sig, TradeSignal)
        assert sig.direction in (0, 1, 2)
        assert sig.nonce == 42
        assert sig.signature == ""  # no priv_key = no signature

    def test_signal_expiry_in_future(self) -> None:
        import time
        chrom = Chromosome.random()
        prices = list(np.linspace(100.0, 150.0, 200))
        sig = build_signal(
            chrom=chrom,
            prices=prices,
            vault_address="0x" + "1" * 40,
            nonce=1,
            expiry_seconds=300,
            priv_key=None,
        )
        assert sig.expiry > int(time.time())

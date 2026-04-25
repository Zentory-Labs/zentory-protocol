"""Market regime detection — bull / bear / sideways classification."""
from __future__ import annotations

import numpy as np
import numpy.typing as npt
from enum import Enum

Array = npt.NDArray[np.float64]


class Regime(Enum):
    BULL     = "bull"
    BEAR     = "bear"
    SIDEWAYS = "sideways"


def detect(prices: Array, lookback: int = 100) -> Regime:
    """
    Classify the current market regime using:
    1. Trend direction: price vs N-period SMA
    2. Momentum: 20-period RSI
    3. Volatility: 20-period ATR vs 100-period ATR
    """
    if len(prices) < lookback:
        return Regime.SIDEWAYS

    price = prices[-lookback:]
    current = prices[-1]

    # ── Trend: price vs SMA ─────────────────────────────────────────────
    sma50 = float(np.mean(price[-50:])) if len(price) >= 50 else float(np.mean(price))
    trend_pct = (current - sma50) / sma50 if sma50 != 0 else 0.0

    # ── Momentum: RSI(14) ───────────────────────────────────────────────
    rsi = _rsi(prices, period=14)

    # ── Volatility regime ───────────────────────────────────────────────
    atr20  = _atr(prices, period=20)
    atr100 = _atr(prices, period=100) if len(prices) >= 100 else atr20
    vol_ratio = atr20 / atr100 if atr100 != 0 else 1.0

    # ── Classification ─────────────────────────────────────────────────
    # Bull: price above SMA50, RSI > 50, normal volatility
    # Bear: price below SMA50, RSI < 50, or extreme vol
    # Sideways: everything else

    bull_score = 0.0
    bear_score = 0.0

    if trend_pct > 0.02:
        bull_score += 1.0
    elif trend_pct < -0.02:
        bear_score += 1.0

    if rsi > 55:
        bull_score += 1.0
    elif rsi < 45:
        bear_score += 1.0

    if vol_ratio > 1.5:
        # High vol: increase bear weight (uncertainty)
        bear_score += 0.5
    elif vol_ratio < 0.7:
        bull_score += 0.5  # calm markets often trending

    if bull_score > bear_score:
        return Regime.BULL
    elif bear_score > bull_score:
        return Regime.BEAR
    else:
        return Regime.SIDEWAYS


def _rsi(prices: Array, period: int = 14) -> float:
    if len(prices) < period + 1:
        return 50.0  # neutral
    deltas = np.diff(prices, prepend=prices[0])
    gains = np.maximum(deltas, 0.0)
    losses = np.maximum(-deltas, 0.0)
    avg_gain = float(np.mean(gains[-period:]))
    avg_loss = float(np.mean(losses[-period:]))
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return 100.0 - (100.0 / (1.0 + rs))


def _atr(prices: Array, period: int = 14) -> float:
    if len(prices) < period + 1:
        return float(np.std(prices)) if len(prices) > 1 else 0.0
    highs = prices[1:]
    lows  = prices[:-1]
    tr = np.abs(highs - lows)
    atr = float(np.mean(tr[-period:]))
    return atr

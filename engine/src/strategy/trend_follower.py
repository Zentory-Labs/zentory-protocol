"""Trend-following strategy logic — applies chromosome genes to generate signals."""
from __future__ import annotations

import numpy as np
import numpy.typing as npt
from dataclasses import dataclass
from enum import Enum

from genetic_programming.chromosome import Chromosome


Array = npt.NDArray[np.float64]


class Direction(Enum):
    LONG  =  1
    SHORT = -1
    CLOSE =  0  # exit to cash


@dataclass
class TrendSignal:
    direction: Direction
    confidence: float   # 0.0–1.0 (unused in v1, reserved for future)
    reason: str         # human-readable debug tag


def generate_signal(chrom: Chromosome, prices: Array) -> TrendSignal:
    """
    Apply trend-following genes to the most recent price window.

    Uses a lookback window equal to the slow MA period × 3 for stability.
    Returns a single Direction to act on at the current epoch.
    """
    if len(prices) < 50:
        return TrendSignal(Direction.CLOSE, 0.0, "insufficient_data")

    # ── Parse genes ──────────────────────────────────────────────────────
    fast_ma    = max(2,  int(chrom.gene_named("fast_ma_period")))
    slow_ma    = max(fast_ma + 1, int(chrom.gene_named("slow_ma_period")))
    vol_filter = max(chrom.gene_named("volatility_filter"), 1e-6)

    # ── Moving averages ────────────────────────────────────────────────────
    fast_ma_vals = _sma(prices, fast_ma)
    slow_ma_vals = _sma(prices, slow_ma)

    if len(fast_ma_vals) < 2 or len(slow_ma_vals) < 2:
        return TrendSignal(Direction.CLOSE, 0.0, "ma_window_too_small")

    fast = fast_ma_vals[-1]
    slow = slow_ma_vals[-1]
    prev_fast = fast_ma_vals[-2]
    prev_slow = slow_ma_vals[-2]

    # ── Regime: bull if price above its own slow MA ──────────────────────
    price_now  = prices[-1]

    bull = price_now > slow
    bear = price_now < slow

    # ── Trend: bullish if fast crosses above slow ────────────────────────
    bullish_cross = (prev_fast <= prev_slow) and (fast > slow)
    bearish_cross = (prev_fast >= prev_slow) and (fast < slow)
    bullish_trend = fast > slow
    bearish_trend = fast < slow

    # ── Volatility filter ─────────────────────────────────────────────────
    returns = np.diff(prices[-slow_ma:])
    float(np.std(returns)) if len(returns) > 1 else 0.0
    max(vol_filter, 1e-6)

    # ── Regime weight from genes ──────────────────────────────────────────
    chrom.gene_named("regime_bull_alpha")
    chrom.gene_named("regime_bear_alpha")

    # ── Decision logic ───────────────────────────────────────────────────
    if not bullish_cross and not bearish_cross:
        # No crossover — hold current trend direction if confirmed by regime
        if bullish_trend and bull:
            return TrendSignal(Direction.LONG, 0.8, "ma_trend_confirmed_bull")
        elif bearish_trend and bear:
            return TrendSignal(Direction.SHORT, 0.8, "ma_trend_confirmed_bear")
        else:
            return TrendSignal(Direction.CLOSE, 0.6, "no_regime_signal")

    # Crossover events
    if bullish_cross and bull:
        return TrendSignal(Direction.LONG, 0.9, "bullish_ma_cross_bull_regime")
    elif bearish_cross and bear:
        return TrendSignal(Direction.SHORT, 0.9, "bearish_ma_cross_bear_regime")
    elif bullish_cross and not bull:
        return TrendSignal(Direction.CLOSE, 0.5, "bullish_cross_no_regime")
    elif bearish_cross and not bear:
        return TrendSignal(Direction.CLOSE, 0.5, "bearish_cross_no_regime")

    return TrendSignal(Direction.CLOSE, 0.0, "fallback_close")


def _sma(prices: Array, window: int) -> Array:
    """Simple moving average — returns Array of shape (len - window + 1,)."""
    if window > len(prices):
        return np.array([], dtype=np.float64)
    out = np.convolve(prices, np.ones(window) / window, mode="valid")
    return out.astype(np.float64)

"""Fitness function: alpha vs HODL benchmark with risk/fees/drawdown penalties."""
from __future__ import annotations

import numpy as np
import numpy.typing as npt
from dataclasses import dataclass

from .chromosome import Chromosome


Array = npt.NDArray[np.float64]


@dataclass
class FitnessConfig:
    max_drawdown_penalty: float = 0.5
    fee_per_trade: float = 0.0004   # 4 bps per round-trip
    risk_penalty_threshold: float = 0.20
    out_of_sample_ratio: float = 0.20


def _sma(arr: Array, window: int) -> Array:
    """Simple moving average, same length as input."""
    if window > len(arr):
        return np.array([], dtype=np.float64)
    out = np.convolve(arr, np.ones(window) / window, mode="valid")
    return out.astype(np.float64)


def _rsi(arr: Array, period: int) -> Array:
    """RSI array, same length as input minus `period`."""
    if len(arr) < period + 1:
        return np.full(len(arr), 50.0, dtype=np.float64)
    deltas = np.diff(arr, prepend=arr[0])
    gains = np.maximum(deltas, 0.0)
    losses = np.maximum(-deltas, 0.0)
    avg_gains = _sma(gains, period)
    avg_losses = _sma(losses, period)
    rs = np.divide(
        avg_gains, avg_losses,
        where=avg_losses != 0,
        out=np.zeros_like(avg_gains),
    )
    return 100.0 - (100.0 / (1.0 + rs))


def evaluate(chrom: Chromosome, prices: Array) -> float:
    """
    Evaluate chromosome fitness on a price series.

    Fitness = annualised alpha vs HODL
             - fee penalty
             - drawdown penalty
    """
    if len(prices) < 200:
        return -1e9

    # Parse genes
    fast_ma    = max(2, int(chrom.gene_named("fast_ma_period")))
    slow_ma    = max(fast_ma + 1, int(chrom.gene_named("slow_ma_period")))
    rsi_buy   = chrom.gene_named("rsi_buy_threshold")
    rsi_sell  = chrom.gene_named("rsi_sell_threshold")
    pos_size  = max(chrom.gene_named("position_size_pct"), 0.01)
    stop_loss = max(chrom.gene_named("stop_loss_pct"), 0.001)
    take_profit = max(chrom.gene_named("take_profit_pct"), 0.001)
    regime_bull = chrom.gene_named("regime_bull_alpha")
    regime_bear = chrom.gene_named("regime_bear_alpha")

    # Maximum lookback across all indicators
    max_win = max(slow_ma, fast_ma, 50, 20, 14)
    p = prices[-max_win:] if len(prices) > max_win else prices

    # ── Compute all indicators on the same-length window ───────────────
    fast_vals = _sma(p, fast_ma)          # len(p) - fast_ma + 1
    slow_vals = _sma(p, slow_ma)         # len(p) - slow_ma + 1
    rsi_vals  = _rsi(p, 14)              # len(p) - 14 + 1

    # Truncate all to the shortest
    min_len = min(len(fast_vals), len(slow_vals), len(rsi_vals))
    fast_vals = fast_vals[-min_len:]
    slow_vals = slow_vals[-min_len:]
    rsi_vals  = rsi_vals[-min_len:]
    price_win = p[-min_len:]

    # Regime: price vs slow MA
    regime_bull_arr = np.where(
        price_win > slow_vals,
        np.full(min_len, regime_bull),
        np.full(min_len, -regime_bear),
    )

    # Trend
    diff = fast_vals - slow_vals
    trend = np.where(diff > 0, 1.0, -1.0)

    # RSI signal
    rsi_long  = (rsi_vals < rsi_buy).astype(float)
    rsi_short = (rsi_vals > rsi_sell).astype(float)
    rsi_signal = rsi_long - rsi_short

    # Combined signal
    raw = trend * regime_bull_arr * rsi_signal
    signal = np.where(np.abs(diff) > 0, raw, 0.0)

    # ── Simulate trading ────────────────────────────────────────────────
    strat_rets = np.zeros(min_len, dtype=np.float64)
    position = 0.0
    entry = 0.0

    for t in range(1, min_len):
        prev_pos = position
        sig = float(signal[t - 1])

        # Entry / exit
        if sig > 0 and prev_pos <= 0:
            position = pos_size
            entry = price_win[t]
        elif sig < 0 and prev_pos >= 0:
            position = -pos_size
            entry = price_win[t]
        elif sig == 0 and prev_pos != 0:
            position = 0.0

        # Stop-loss / take-profit
        if prev_pos > 0 and entry > 0:
            pnl = (price_win[t] - entry) / entry
            if pnl <= -stop_loss or pnl >= take_profit:
                position = 0.0
        elif prev_pos < 0 and entry > 0:
            pnl = (entry - price_win[t]) / entry
            if pnl <= -stop_loss or pnl >= take_profit:
                position = 0.0

        if t > 0:
            ret = (price_win[t] / price_win[t - 1]) - 1.0 if price_win[t - 1] != 0 else 0.0
            strat_rets[t] = position * ret

    # ── Alpha vs HODL ─────────────────────────────────────────────────
    hodl_rets = (price_win[1:] / price_win[:-1]) - 1.0
    strat_trim = strat_rets[1:]

    alpha = strat_trim - hodl_rets
    fitness = float(np.mean(alpha)) * 252  # annualised

    # ── Penalties ──────────────────────────────────────────────────────
    # Fee penalty
    n_trades = max(1.0, float(np.sum(np.abs(np.diff(signal != 0)))))
    fitness -= n_trades * 2 * FitnessConfig.fee_per_trade

    # Drawdown penalty
    cumulative = np.cumprod(1.0 + strat_trim)
    running_max = np.maximum.accumulate(cumulative)
    drawdown = (cumulative - running_max) / np.maximum(running_max, 1e-10)
    max_dd = float(abs(np.min(drawdown))) if len(drawdown) > 0 else 0.0
    if max_dd > FitnessConfig.risk_penalty_threshold:
        fitness -= FitnessConfig.max_drawdown_penalty * max_dd

    return fitness


def evaluate_oos(chrom: Chromosome, prices: Array) -> float:
    """Out-of-sample: evaluate on last 20% of price data."""
    if len(prices) < 200:
        return -1e9
    split = int(len(prices) * (1.0 - FitnessConfig.out_of_sample_ratio))
    return evaluate(chrom, prices[split:])

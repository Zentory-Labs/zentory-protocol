"""Chromosome encoding for strategy genes."""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Sequence


# ─── Gene definitions ────────────────────────────────────────────────────────

@dataclass
class GeneDef:
    name: str
    min_val: float
    max_val: float
    step: float = 0.0  # 0 = continuous


# Trend-following gene schema
TREND_GENES: list[GeneDef] = [
    GeneDef("fast_ma_period",   2,   50,  step=1),
    GeneDef("slow_ma_period",   10,  200, step=1),
    GeneDef("rsi_buy_threshold",  20, 50, step=1),
    GeneDef("rsi_sell_threshold", 50, 80, step=1),
    GeneDef("volatility_filter",  0.01, 0.10),
    GeneDef("position_size_pct", 0.05, 1.0),
    GeneDef("stop_loss_pct",     0.01, 0.10),
    GeneDef("take_profit_pct",   0.02, 0.20),
    GeneDef("regime_bull_alpha",  0.0, 1.0),
    GeneDef("regime_bear_alpha",  0.0, 1.0),
]


# ─── Chromosome ─────────────────────────────────────────────────────────────

@dataclass
class Chromosome:
    """A single strategy encoded as a list of gene values."""

    genes: list[float]
    age: int = 0  # generations survived

    @classmethod
    def random(cls) -> Chromosome:
        """Create a random chromosome by sampling each gene uniformly."""
        genes = [defn.min_val + random.random() * (defn.max_val - defn.min_val)
                 for defn in TREND_GENES]
        return cls(genes=genes)

    def copy(self) -> Chromosome:
        return Chromosome(genes=list(self.genes), age=self.age)

    def crossover(self, other: Chromosome) -> tuple[Chromosome, Chromosome]:
        """Two-point crossover between self and other."""
        if len(self.genes) != len(other.genes):
            raise ValueError("Chromosomes must have same gene count")

        size = len(self.genes)
        pt1 = random.randint(1, size - 2)
        pt2 = random.randint(pt1 + 1, size - 1)

        def _mix(a: list[float], b: list[float]) -> list[float]:
            return a[:pt1] + b[pt1:pt2] + a[pt2:]

        c1 = Chromosome(genes=_mix(self.genes, other.genes))
        c2 = Chromosome(genes=_mix(other.genes, self.genes))
        return c1, c2

    def mutate(self, rate: float = 0.1, sigma: float = 0.05) -> None:
        """Mutate each gene with probability `rate` using Gaussian perturbation."""
        for i, defn in enumerate(TREND_GENES):
            if random.random() < rate:
                delta = random.gauss(0, sigma * (defn.max_val - defn.min_val))
                self.genes[i] = float(max(defn.min_val, min(defn.max_val,
                                                         self.genes[i] + delta)))

    def gene_named(self, name: str) -> float:
        idx = next(i for i, g in enumerate(TREND_GENES) if g.name == name)
        return self.genes[idx]

    def __repr__(self) -> str:
        pairs = [f"{g.name}={v:.4f}" for g, v in zip(TREND_GENES, self.genes)]
        return f"Chromosome({', '.join(pairs)})"

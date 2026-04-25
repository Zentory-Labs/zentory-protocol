"""GP evolution loop — runs one epoch of population evaluation and breeding."""
from __future__ import annotations

import asyncio
import json
import time
import structlog
from dataclasses import dataclass

import numpy as np

from genetic_programming.chromosome import Chromosome
from genetic_programming.population import Population
from genetic_programming import fitness as fit_mod
from genetic_programming.chromosome import TREND_GENES
from strategy.regime_detector import Regime, detect
from execution.hyperliquid_executor import HyperliquidExecutor, ExecutorConfig

logger = structlog.get_logger(__name__)


@dataclass
class GPEngineConfig:
    population_size: int = 100
    elite_size: int = 5
    tournament_size: int = 5
    n_generations: int = 100
    epoch_interval_seconds: int = 900   # 15 minutes between epochs
    # Price history: list of recent prices (most recent last)
    price_history: list[float] | None = None


class GPEngine:
    """
    Runs the genetic programming evolution loop for trend-following strategy generation.

    Each epoch:
    1. Evaluate all chromosomes on price history
    2. Evolve population (selection + crossover + mutation)
    3. Report elite chromosome
    4. Optionally submit signal to StrategyExecutor
    """

    def __init__(self, config: GPEngineConfig) -> None:
        self.config = config
        self.population = Population(
            population_size=config.population_size,
            elite_size=config.elite_size,
        )
        self.population.seed()
        self.generation = 0
        self._fitness_history: list[float] = []
        self._executor: HyperliquidExecutor | None = None

    def set_executor(self, executor: HyperliquidExecutor) -> None:
        self._executor = executor

    # ─── Core loop ────────────────────────────────────────────────────────

    async def run_epoch(self, prices: list[float]) -> dict:
        """
        Run one evolutionary epoch.
        Must be called with a price history (most recent price last).
        """
        if len(prices) < 50:
            raise ValueError("Need at least 50 price points")

        self.config.price_history = prices
        prices_arr = np.array(prices, dtype=np.float64)

        # ── 1. Evaluate all members ──────────────────────────────────────
        self.population.fitness = [
            fit_mod.evaluate(chrom, prices_arr)
            for chrom in self.population.members
        ]

        elite, elite_fitness = self.population.best()
        self._fitness_history.append(elite_fitness)
        self.generation += 1

        logger.info(
            "epoch.evaluated",
            generation=self.generation,
            elite_fitness=elite_fitness,
            diversity=self.population.diversity(),
        )

        # ── 2. Evolve population ───────────────────────────────────────
        self.population.evolve()

        # ── 3. Generate trade signal from elite ─────────────────────────
        regime = detect(prices_arr)
        signal = self._build_signal(elite, prices, regime)

        # ── 4. Submit to chain if executor configured ───────────────────
        tx_hash = None
        if self._executor is not None and signal is not None:
            nonce = await self._fetch_nonce()
            result = await self._executor.run_epoch(
                prices=prices,
                nonce=nonce,
                elite_chrom=elite,
            )
            tx_hash = result.get("tx_hash")

        return {
            "generation": self.generation,
            "elite_fitness": elite_fitness,
            "elite_chromosome": elite,
            "signal": signal,
            "regime": regime.value,
            "diversity": self.population.diversity(),
            "tx_hash": tx_hash,
        }

    async def run_loop(self, price_source) -> None:
        """
        Run the evolution loop continuously.

        Parameters
        ----------
        price_source : async iterable[list[float]]
            Yields price histories every epoch_interval_seconds.
        """
        async for prices in price_source:
            result = await self.run_epoch(prices)
            logger.info(
                "epoch.complete",
                generation=result["generation"],
                fitness=result["elite_fitness"],
                regime=result["regime"],
                signal=result["signal"],
            )
            await asyncio.sleep(self.config.epoch_interval_seconds)

    # ─── Signal generation ─────────────────────────────────────────────────

    def _build_signal(
        self, chrom: Chromosome, prices: list[float], regime: Regime
    ) -> dict | None:
        """Build a signal dict from elite chromosome. Returns None if no trade warranted."""
        from strategy.signal_generator import build_signal, signal_to_payload

        if self._executor is None:
            return None

        try:
            nonce = 0  # Will be fetched on-chain in production
            sig = build_signal(
                chrom=chrom,
                prices=prices,
                vault_address=self._executor.config.vault_address,
                nonce=nonce,
                expiry_seconds=300,
                priv_key=self._executor.config.private_key,
            )
            return signal_to_payload(sig)
        except Exception as exc:
            logger.warning("signal.build_failed", error=str(exc))
            return None

    async def _fetch_nonce(self) -> int:
        if self._executor is None:
            return 0
        # In production: read from StrategyExecutor.nonces(vault)
        return 0

    # ─── Persistence ────────────────────────────────────────────────────

    def save_elite(self, path: str) -> None:
        """Persist the current best chromosome to JSON."""
        elite, _ = self.population.best()
        data = {
            "generation": self.generation,
            "fitness": float(self._fitness_history[-1]),
            "genes": {g.name: v for g, v in zip(TREND_GENES, elite.genes)},
            "age": elite.age,
        }
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        logger.info("elite_saved", path=path, generation=self.generation)

    @classmethod
    def load(cls, config: GPEngineConfig, path: str) -> GPEngine:
        """Restore engine state from a saved elite JSON."""
        with open(path) as f:
            data = json.load(f)

        engine = cls(config)
        engine.generation = data["generation"]
        # Rebuild elite chromosome
        gene_map = data["genes"]
        genes = [gene_map[g.name] for g in TREND_GENES]
        elite = Chromosome(genes=genes, age=data["age"])
        engine.population.members[0] = elite
        engine.population.fitness[0] = data["fitness"]
        logger.info("elite_loaded", generation=engine.generation, path=path)
        return engine


# ─── Convenience runner ────────────────────────────────────────────────────────

async def main() -> None:
    import os
    from dotenv import load_dotenv

    load_dotenv()

    config = GPEngineConfig(
        population_size=100,
        n_generations=1000,
        epoch_interval_seconds=900,
    )
    engine = GPEngine(config)

    executor_cfg = ExecutorConfig(
        rpc_url=os.environ["HYPERLIQUID_RPC"],
        private_key=os.environ["KEEPER_PRIVATE_KEY"],
        strategy_executor=os.environ["STRATEGY_EXECUTOR"],
        vault_address=os.environ["VAULT_ADDRESS"],
        hyperliquid_oracle=os.environ["ORACLE_ADDRESS"],
    )
    executor = HyperliquidExecutor(executor_cfg)
    engine.set_executor(executor)

    logger.info("engine.starting", population=config.population_size)
    await engine.run_loop(iter([]))  # price_source would be a real async iterator


if __name__ == "__main__":
    asyncio.run(main())

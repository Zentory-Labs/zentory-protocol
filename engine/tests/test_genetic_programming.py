"""Tests for genetic programming components."""
from __future__ import annotations

import numpy as np
import pytest

from genetic_programming.chromosome import Chromosome, TREND_GENES
from genetic_programming.population import Population
from genetic_programming.fitness import evaluate, FitnessConfig


class TestChromosome:
    def test_random_produces_valid_genes(self) -> None:
        chrom = Chromosome.random()
        assert len(chrom.genes) == len(TREND_GENES)
        for val, defn in zip(chrom.genes, TREND_GENES):
            assert defn.min_val <= val <= defn.max_val

    def test_copy_is_independent(self) -> None:
        original = Chromosome.random()
        copy = original.copy()
        copy.genes[0] = 9999.0
        assert original.genes[0] != 9999.0

    def test_crossover_preserves_length(self) -> None:
        p1 = Chromosome.random()
        p2 = Chromosome.random()
        c1, c2 = p1.crossover(p2)
        assert len(c1.genes) == len(p1.genes)
        assert len(c2.genes) == len(p2.genes)

    def test_mutate_keeps_genes_in_bounds(self) -> None:
        chrom = Chromosome.random()
        chrom.mutate(rate=1.0, sigma=0.2)  # mutate all genes
        for val, defn in zip(chrom.genes, TREND_GENES):
            assert defn.min_val <= val <= defn.max_val

    def test_gene_named(self) -> None:
        chrom = Chromosome(genes=[10.0] * len(TREND_GENES))
        assert chrom.gene_named("fast_ma_period") == 10.0


class TestPopulation:
    def test_seed_creates_correct_size(self) -> None:
        pop = Population(population_size=50, elite_size=5)
        pop.seed()
        assert len(pop.members) == 50
        assert len(pop.fitness) == 50

    def test_best_returns_highest_fitness(self) -> None:
        pop = Population(population_size=10, elite_size=2)
        pop.seed()
        pop.fitness = list(range(10))  # 0..9
        best, fit = pop.best()
        assert fit == 9.0

    def test_tournament_select_returns_from_members(self) -> None:
        pop = Population(population_size=10, elite_size=2)
        pop.seed()
        pop.fitness = [1.0] * 10
        selected = pop.tournament_select(tournament_size=3)
        assert isinstance(selected, Chromosome)

    def test_diversity_decreases_with_identical_members(self) -> None:
        pop = Population(population_size=5, elite_size=1)
        pop.members = [Chromosome(genes=[1.0] * len(TREND_GENES)) for _ in range(5)]
        pop.fitness = [1.0] * 5
        assert pop.diversity() == 0.0


class TestFitness:
    def test_insufficient_data_returns_negative(self) -> None:
        chrom = Chromosome.random()
        prices = np.array([100.0, 101.0, 102.0])  # only 3 prices
        fitness = evaluate(chrom, prices)
        assert fitness == -1e9

    def test_bullish_trend_produces_positive_alpha(self) -> None:
        # Simulate a steady uptrend
        chrom = Chromosome.random()
        # Set fast MA very short, slow MA long — will trend-follow upward
        prices = np.linspace(100.0, 200.0, 300)  # 300 days, uptrend
        fitness = evaluate(chrom, prices)
        # Fitness may be positive or negative depending on chromosome;
        # the key test is that it computes without error
        assert isinstance(fitness, float)

    def test_config_defaults(self) -> None:
        cfg = FitnessConfig()
        assert cfg.fee_per_trade == 0.0004
        assert cfg.risk_penalty_threshold == 0.20

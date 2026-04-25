"""GP Population management — tournament selection, breeding, diversity maintenance."""
from __future__ import annotations

import bisect
import random
from dataclasses import dataclass, field

from .chromosome import Chromosome


@dataclass
class Population:
    """A fixed-size population of chromosomes with fitness scores."""

    members: list[Chromosome] = field(default_factory=list)
    fitness: list[float] = field(default_factory=list)
    population_size: int = 100
    elite_size: int = 5  # top N survive unchanged

    # ─── Initialisation ───────────────────────────────────────────────────────

    def seed(self) -> None:
        """Fill population with random chromosomes."""
        self.members = [Chromosome.random() for _ in range(self.population_size)]
        self.fitness = [0.0] * self.population_size

    # ─── Accessors ──────────────────────────────────────────────────────────

    def best(self) -> tuple[Chromosome, float]:
        """Return the highest-fitness chromosome."""
        idx = self.fitness.index(max(self.fitness))
        return self.members[idx], self.fitness[idx]

    def sorted(self) -> list[tuple[Chromosome, float]]:
        """Return members sorted by fitness descending."""
        pairs = sorted(zip(self.members, self.fitness), key=lambda p: p[1], reverse=True)
        return pairs

    def diversity(self) -> float:
        """Mean pairwise Euclidean distance in gene space (higher = more diverse)."""
        if len(self.members) < 2:
            return 0.0
        total = 0.0
        count = 0
        for i in range(len(self.members)):
            for j in range(i + 1, len(self.members)):
                diffs = [a - b for a, b in zip(self.members[i].genes, self.members[j].genes)]
                total += sum(d * d for d in diffs) ** 0.5
                count += 1
        return total / count

    # ─── Selection ──────────────────────────────────────────────────────────

    def tournament_select(self, tournament_size: int = 5) -> Chromosome:
        """Tournament selection: pick `tournament_size` random members, return fittest."""
        indices = random.sample(range(len(self.members)), tournament_size)
        best_idx = max(indices, key=lambda i: self.fitness[i])
        return self.members[best_idx]

    # ─── Evolutionary operators ─────────────────────────────────────────────

    def evolve(self) -> None:
        """One generation: selection → crossover → mutation + elitism."""
        new_members: list[Chromosome] = []
        new_fitness: list[float] = []

        # ── Elitism: carry best N unchanged ────────────────────────────────
        for chrom, fit in self.sorted()[:self.elite_size]:
            new_members.append(chrom.copy())
            new_fitness.append(fit)

        # ── Breeding loop ──────────────────────────────────────────────────
        while len(new_members) < self.population_size:
            p1 = self.tournament_select()
            p2 = self.tournament_select()
            c1, c2 = p1.crossover(p2)

            if random.random() < 0.1:  # 10% chance per gene (applied per chromosome below)
                c1.mutate(rate=0.1)
                c2.mutate(rate=0.1)
            else:
                c1.mutate(rate=0.05)
                c2.mutate(rate=0.05)

            new_members.extend([c1, c2])
            new_fitness.extend([0.0, 0.0])

        # ── Trim to population size ─────────────────────────────────────────
        self.members = new_members[:self.population_size]
        self.fitness = new_fitness[:self.population_size]

        # Age survivors
        for chrom in self.members:
            chrom.age += 1

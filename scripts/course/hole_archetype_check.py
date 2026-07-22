#!/usr/bin/env python3
"""Mirrors HoleGenerator.archetype_weight / anti-repeat — fails if diversity rules drift."""
from __future__ import annotations

import random
import sys

PAR4 = [
    "short_sharp",
    "classic_dogleg",
    "long_bear",
    "risk_reward",
    "target_green",
]


# Mirrors HoleGenerator island_green.min_t / peninsula gate.
ISLAND_MIN_T = 0.22
ARCH_MIN_T = {"island_green": ISLAND_MIN_T}


def archetype_weight(
    aid: str, par: int, history: list[dict], t: float = 1.0, min_t: float = 0.0
) -> float:
    if t < min_t:
        return 0.0
    w = 1.0
    start = max(0, len(history) - 3)
    for i in range(start, len(history)):
        h = history[i]
        if int(h.get("par", 0)) != par or str(h.get("id", "")) != aid:
            continue
        if i == len(history) - 1:
            return 0.0
        w *= 0.08 if par == 4 else 0.18
    for h2 in history:
        if int(h2.get("par", 0)) == par and str(h2.get("id", "")) == aid:
            w *= 0.55
            break
    return w


def pick_weighted(rng: random.Random, items: list, weights: list):
    total = sum(max(float(w), 0.0) for w in weights)
    if total <= 0.0:
        return rng.choice(items)
    roll = rng.random() * total
    acc = 0.0
    for item, w in zip(items, weights):
        acc += max(float(w), 0.0)
        if roll <= acc:
            return item
    return items[-1]


def pick_archetype(
    rng: random.Random, par: int, history: list[dict], ids: list[str], t: float = 1.0
) -> str:
    weights = [archetype_weight(i, par, history, t, ARCH_MIN_T.get(i, 0.0)) for i in ids]
    return pick_weighted(rng, ids, weights)


def difficulty_t(hole_number: int, total_holes: int = 18) -> float:
    u = (hole_number - 1) / max(total_holes - 1, 1)
    return u * u


def main() -> int:
    # Immediate previous same-par id is excluded.
    hist = [{"par": 4, "id": "short_sharp"}]
    assert archetype_weight("short_sharp", 4, hist) == 0.0
    assert archetype_weight("long_bear", 4, hist) == 1.0

    # Same id two holes ago (inside 3-hole span) is crushed, not zero.
    hist2 = [
        {"par": 4, "id": "short_sharp"},
        {"par": 3, "id": "long_iron"},
    ]
    w = archetype_weight("short_sharp", 4, hist2)
    assert 0.0 < w < 0.1, w

    # Island green locked until mid-round (opening par-3 bias must not roll it).
    assert archetype_weight("island_green", 3, [], 0.0, ISLAND_MIN_T) == 0.0
    assert difficulty_t(1) < ISLAND_MIN_T
    assert difficulty_t(2) < ISLAND_MIN_T
    assert difficulty_t(8) < ISLAND_MIN_T
    assert difficulty_t(9) >= ISLAND_MIN_T
    assert archetype_weight("island_green", 3, [], difficulty_t(9), ISLAND_MIN_T) == 1.0

    # Simulate a par-4-heavy stretch: no back-to-back repeats, ≥4 distinct over 10.
    rng = random.Random(42)
    history: list[dict] = []
    picked: list[str] = []
    # Fake hole stream: mostly par 4s with a couple of other pars mixed in.
    pars = [4, 4, 3, 4, 4, 4, 5, 4, 4, 4, 4, 4]
    for i, par in enumerate(pars):
        t = difficulty_t(i + 1)
        ids = PAR4 if par == 4 else ["long_iron", "short_pitch", "island_green"]
        if par == 5:
            ids = ["reachable", "three_shotter", "hazard_gauntlet"]
        aid = pick_archetype(rng, par, history, ids, t)
        if history and history[-1]["par"] == par:
            assert aid != history[-1]["id"], f"back-to-back repeat: {aid}"
        if par == 3 and t < ISLAND_MIN_T:
            assert aid != "island_green", f"island too early at hole {i + 1}"
        history.append({"par": par, "id": aid})
        if par == 4:
            picked.append(aid)

    assert len(picked) >= 8
    assert len(set(picked)) >= 4, f"par4 diversity too low: {picked}"
    print("hole_archetype_check: ok", f"par4={picked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

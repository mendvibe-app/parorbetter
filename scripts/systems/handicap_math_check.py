#!/usr/bin/env python3
"""Contract check for HandicapMath — slope, stroke index, differentials."""
from __future__ import annotations

from pathlib import Path

SRC = Path(__file__).with_name("handicap_math.gd").read_text(encoding="utf-8")
GS = Path(__file__).resolve().parents[1].joinpath("autoload/game_state.gd").read_text(encoding="utf-8")

SLOPE_MIN = 55.0
SLOPE_MAX = 155.0
SLOPE_REF = 113.0
COMPLEXITY_AT_REF = 0.58


def course_slope(complexities: list[float]) -> float:
    if not complexities:
        return SLOPE_REF
    mean = sum(max(0.0, min(1.0, c)) for c in complexities) / len(complexities)
    if mean <= COMPLEXITY_AT_REF:
        t = max(0.0, min(1.0, mean / COMPLEXITY_AT_REF))
        slope = SLOPE_MIN + (SLOPE_REF - SLOPE_MIN) * t
    else:
        u = max(0.0, min(1.0, (mean - COMPLEXITY_AT_REF) / (1.0 - COMPLEXITY_AT_REF)))
        slope = SLOPE_REF + (SLOPE_MAX - SLOPE_REF) * u
    return max(SLOPE_MIN, min(SLOPE_MAX, slope))


def stroke_index_ranks(complexities: list[float]) -> list[int]:
    n = len(complexities)
    order = list(range(n))
    order.sort(key=lambda i: (-complexities[i], i))
    out = [0] * n
    for rank, i in enumerate(order):
        out[i] = rank + 1
    return out


def score_differential(score_to_par: int, slope: float) -> float:
    slope = max(SLOPE_MIN, min(SLOPE_MAX, slope))
    return float(score_to_par) * (SLOPE_REF / slope)


def handicap_index(diffs: list[float], min_rounds: int = 3) -> float | None:
    if len(diffs) < min_rounds:
        return None
    vals = sorted(diffs)
    k = min(8, len(vals))
    return sum(vals[:k]) / k


def main() -> None:
    assert "class_name HandicapMath" in SRC
    assert "static func course_slope" in SRC
    assert "static func stroke_index_ranks" in SRC
    assert "static func score_differential" in SRC
    assert "static func handicap_index" in SRC
    assert "stroke_play_mode" in GS
    assert "best_stroke_score_to_par" in GS
    assert "HandicapMath.course_slope" in GS

    easy = course_slope([0.1] * 18)
    mid = course_slope([0.58] * 18)
    hard = course_slope([0.95] * 18)
    assert SLOPE_MIN <= easy < mid < hard <= SLOPE_MAX, (easy, mid, hard)
    assert abs(mid - SLOPE_REF) < 1.0, mid

    comps = [0.2, 0.9, 0.2, 0.5, 0.9]
    ranks = stroke_index_ranks(comps)
    assert sorted(ranks) == list(range(1, len(comps) + 1)), ranks
    # Hole 1 (0.9) and hole 4 (0.9): lower index harder → hole 1 gets SI 1
    assert ranks[1] == 1 and ranks[4] == 2, ranks

    d_hard = score_differential(10, 140.0)
    d_easy = score_differential(10, 80.0)
    assert d_hard < d_easy  # same over-par hurts less on harder slope

    assert handicap_index([5.0, 4.0]) is None
    hi = handicap_index([12.0, 10.0, 8.0, 6.0])
    assert hi is not None and abs(hi - (6 + 8 + 10 + 12) / 4) < 1e-6

    print("handicap_math_check: ok")


if __name__ == "__main__":
    main()

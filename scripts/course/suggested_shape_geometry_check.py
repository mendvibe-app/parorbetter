#!/usr/bin/env python3
"""Suggested shape tracks dogleg geometry only — never hazard side on straight holes."""
from __future__ import annotations

import random
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")
DATA = DIR.joinpath("hole_data.gd").read_text(encoding="utf-8")

STRAIGHT, DRAW, FADE = 0, 1, 2
NONE, LEFT, RIGHT = 0, 1, 2
STANDARD, DOGLEG_LEFT, DOGLEG_RIGHT, ISLAND, CHUTE, BI_TIER = range(6)

NON_DOGLEG = (STANDARD, ISLAND, CHUTE, BI_TIER)
DOGLEG = (DOGLEG_LEFT, DOGLEG_RIGHT)


def suggested_shape(layout: int, bias: int, rng: random.Random) -> int:
    """Mirror HoleGenerator._suggested_shape (bias/rng unused for non-dogleg)."""
    if layout == DOGLEG_RIGHT:
        return FADE
    if layout == DOGLEG_LEFT:
        return DRAW
    return STRAIGHT


def _extract_suggested_shape_body() -> str:
    m = re.search(
        r"static func _suggested_shape\([\s\S]*?\) -> HoleData\.SuggestedShape:\n([\s\S]*?)\n\nstatic func",
        GEN,
    )
    assert m, "_suggested_shape not found"
    return m.group(1)


def main() -> int:
    assert "enum SuggestedShape { STRAIGHT, DRAW, FADE }" in DATA
    assert "enum LayoutStyle { STANDARD, DOGLEG_LEFT, DOGLEG_RIGHT, ISLAND, CHUTE, BI_TIER }" in DATA
    assert "enum HazardBias { NONE, LEFT, RIGHT }" in DATA

    body = _extract_suggested_shape_body()
    assert "0.65" not in body, "hazard-bias probabilistic shape must be gone"
    assert "HazardBias.RIGHT" not in body
    assert "HazardBias.LEFT" not in body
    assert "return HoleData.SuggestedShape.STRAIGHT" in body
    assert "DOGLEG_RIGHT" in body and "FADE" in body
    assert "DOGLEG_LEFT" in body and "DRAW" in body
    # Unused params kept for call-site stability
    assert "bias: HoleData.HazardBias" in GEN
    assert "rng: RandomNumberGenerator" in GEN

    # Harness: many seeds × every layout × every hazard bias.
    # Non-dogleg must always be STRAIGHT even when bias is LEFT/RIGHT (old bug path).
    n_straight_with_side_hazard = 0
    for seed in range(400):
        rng = random.Random(seed)
        for layout in range(6):
            for bias in (NONE, LEFT, RIGHT):
                shape = suggested_shape(layout, bias, rng)
                if layout in NON_DOGLEG:
                    assert shape == STRAIGHT, (
                        f"seed={seed} layout={layout} bias={bias} → {shape}, want STRAIGHT"
                    )
                    if bias in (LEFT, RIGHT):
                        n_straight_with_side_hazard += 1
                elif layout == DOGLEG_LEFT:
                    assert shape == DRAW
                elif layout == DOGLEG_RIGHT:
                    assert shape == FADE

    assert n_straight_with_side_hazard == 400 * len(NON_DOGLEG) * 2
    print(
        f"ok: suggested_shape geometry — "
        f"{400 * 6 * 3} cases; {n_straight_with_side_hazard} non-dogleg+side-hazard → STRAIGHT"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

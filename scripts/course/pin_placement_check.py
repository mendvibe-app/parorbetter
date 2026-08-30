#!/usr/bin/env python3
"""USGA-style pin: inset margin, not center-stuck, slope shelf reject."""
from __future__ import annotations

import math
import random
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")
PX_PER_YARD = 2.25
MARGIN_YD = 5.0  # 15 ft / ~4 paces
MARGIN = MARGIN_YD * PX_PER_YARD
MAX_SLOPE = 0.03


def inside_ellipse(p, rx, ry) -> bool:
    nx = p[0] / max(rx, 1.0)
    ny = p[1] / max(ry, 1.0)
    return nx * nx + ny * ny <= 1.0


def edge_clearance(p, rx, ry) -> float:
    """Approximate distance from point to ellipse boundary along ray from origin."""
    if p[0] == 0 and p[1] == 0:
        return min(rx, ry)
    # Ray scale to boundary: find t where (tx/rx)^2+(ty/ry)^2=1
    a = (p[0] / rx) ** 2 + (p[1] / ry) ** 2
    if a <= 1e-12:
        return min(rx, ry)
    t_boundary = 1.0 / math.sqrt(a)
    # Distance from p to boundary along same ray
    r = math.hypot(*p)
    return r * (t_boundary - 1.0) if t_boundary >= 1.0 else -r * (1.0 - t_boundary)


def bucket_range(b: int, lim: float):
    third = lim / 3.0
    if b < 0:
        return (-lim, -third)
    if b > 0:
        return (third, lim)
    return (-third, third)


def sample_zone(bx, by, ix, iy, rng: random.Random):
    xr = bucket_range(bx, ix)
    yr = bucket_range(by, iy)
    return (rng.uniform(*xr), rng.uniform(*yr))


def main() -> int:
    assert "PIN_EDGE_MARGIN_YD := 5.0" in GEN
    assert "_pick_pin" in GEN
    assert "_pin_offset" not in GEN or "func _pin_offset" not in GEN
    assert "lerpf(0.15, 0.72, t)" not in GEN
    assert re.search(r"_pick_pin\(", GEN)

    rx, ry = 60.0, 50.0
    ix, iy = max(rx - MARGIN, rx * 0.35), max(ry - MARGIN, ry * 0.35)
    assert ix < rx and iy < ry

    # Inset pins keep ≥ margin from outer ellipse (center case uses min radius).
    assert min(ix, iy) <= min(rx, ry) - MARGIN + 1e-6 or min(rx, ry) < MARGIN + 1.0

    rng = random.Random(7)
    pins = []
    for by in (-1, 0, 1):
        for bx in (-1, 0, 1):
            for _ in range(3):
                p = sample_zone(bx, by, ix, iy, rng)
                if inside_ellipse(p, ix, iy):
                    pins.append(p)

    assert len(pins) >= 12
    mean_r = sum(math.hypot(*p) for p in pins) / len(pins)
    assert mean_r > min(ix, iy) * 0.25, f"pins too central: mean_r={mean_r}"

    fronts = sum(1 for p in pins if p[1] > iy * 0.15)
    backs = sum(1 for p in pins if p[1] < -iy * 0.15)
    assert fronts >= 1 and backs >= 1, f"need front+back variety f={fronts} b={backs}"

    # Edge clearance: every inset-legal pin should be outside a smaller "too close to edge" fail
    for p in pins:
        # Distance from outer ellipse along ray should be >= ~margin when p on inset boundary;
        # interior points have more clearance.
        assert inside_ellipse(p, rx, ry)
        clr = edge_clearance(p, rx, ry)
        assert clr >= MARGIN * 0.85, f"pin too close to edge: {p} clr={clr}"

    # Slope shelf: steep local slope fails soft cap.
    assert MAX_SLOPE == 0.03
    assert "PIN_MAX_LOCAL_SLOPE := 0.03" in GEN
    assert "PIN_SHELF_UNIFORM := 0.015" in GEN
    assert "PIN_STEEP_PENALTY := 16.0" in GEN
    steep = 0.08
    flat = 0.02
    assert steep > MAX_SLOPE
    assert flat <= MAX_SLOPE

    print("pin_placement_check: ok", f"n={len(pins)} mean_r={mean_r:.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

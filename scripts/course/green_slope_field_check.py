#!/usr/bin/env python3
"""Mirrors HoleData green slope profiles — fails if field logic drifts."""
from __future__ import annotations

import math
import sys
from pathlib import Path

DIR = Path(__file__).parent
DATA = DIR.joinpath("hole_data.gd").read_text(encoding="utf-8")
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")


def influences_side_slope(slope, rx, ry, pin):
    base_len = math.hypot(slope[0], slope[1])
    if base_len < 0.02:
        return []
    rx, ry = max(rx, 20.0), max(ry, 20.0)
    rmin = min(rx, ry)
    down = (slope[0] / base_len, slope[1] / base_len)
    across = (-down[1], down[0])
    out = []
    sigma_crown = rmin * 0.48
    pin_across = max(-rx * 0.4, min(rx * 0.4, pin[0] * across[0] + pin[1] * across[1]))
    out.append(
        {
            "pos": (
                -down[0] * ry * 0.32 + across[0] * pin_across * 0.2,
                -down[1] * ry * 0.32 + across[1] * pin_across * 0.2,
            ),
            "amp": base_len * sigma_crown * 0.7,
            "sigma": sigma_crown,
        }
    )
    sigma_pin = rmin * 0.36
    out.append(
        {
            "pos": (pin[0] * 0.85, pin[1] * 0.85),
            "amp": -base_len * sigma_pin * 0.55,
            "sigma": sigma_pin,
        }
    )
    side_amt = max(-rx * 0.55, min(rx * 0.55, pin[0] * across[0] + pin[1] * across[1]))
    side = (across[0] * side_amt, across[1] * side_amt)
    if math.hypot(*side) > 6.0:
        sigma_side = rmin * 0.42
        out.append(
            {
                "pos": (side[0] * 0.75 - down[0] * ry * 0.08, side[1] * 0.75 - down[1] * ry * 0.08),
                "amp": base_len * sigma_side * 0.45,
                "sigma": sigma_side,
            }
        )
    return out


def influences_bowl(slope, rx, ry, pin):
    base_len = math.hypot(*slope)
    rmin = min(max(rx, 20.0), max(ry, 20.0))
    return [{"pos": (pin[0] * 0.35, pin[1] * 0.35), "amp": -base_len * rmin * 0.85, "sigma": rmin * 0.55}]


def influences_false_front(slope, rx, ry, pin):
    base_len = math.hypot(*slope)
    rmin = min(max(rx, 20.0), max(ry, 20.0))
    return [
        {
            "pos": (0.0, ry * 0.42),
            "amp": base_len * rmin * 0.8,
            "sigma": rmin * 0.38,
        },
        {
            "pos": (pin[0] * 0.9, pin[1] * 0.9 - ry * 0.08),
            "amp": -base_len * rmin * 0.4,
            "sigma": rmin * 0.32,
        },
    ]


def height_at(local, slope, infs):
    h = -(slope[0] * local[0] + slope[1] * local[1]) * 0.42
    for inf in infs:
        dx = local[0] - inf["pos"][0]
        dy = local[1] - inf["pos"][1]
        s2 = inf["sigma"] ** 2
        h += inf["amp"] * 1.0 * math.exp(-(dx * dx + dy * dy) / (2.0 * s2))
    return h


def slope_at(local, slope, infs):
    sx, sy = slope[0] * 0.42, slope[1] * 0.42
    for inf in infs:
        dx = local[0] - inf["pos"][0]
        dy = local[1] - inf["pos"][1]
        s2 = inf["sigma"] ** 2
        fall = math.exp(-(dx * dx + dy * dy) / (2.0 * s2))
        k = (inf["amp"] * 1.0 / s2) * fall
        sx += dx * k
        sy += dy * k
    return (sx, sy)


def main() -> int:
    assert "ContourProfile" in DATA
    assert "_pick_contour" in GEN
    assert "lerpf(0.04, 0.42, t)" not in GEN
    assert "lerpf(0.04, 0.42, rng.randf())" not in GEN
    assert "lerpf(0.10, 0.48, rng.randf())" not in GEN
    assert "lerpf(0.08, 0.30, rng.randf())" not in GEN
    assert "lerpf(0.024, 0.08, rng.randf())" in GEN
    assert "lerpf(0.12, 0.03, t)" in GEN  # early FLAT weight cut
    assert "GREEN_CONTOUR_AMP_SCALE := 1.0" in DATA
    assert "PIN_MAX_LOCAL_SLOPE := 0.03" in GEN
    assert "ContourProfile.FLAT" in DATA.split("func green_slope_at")[1].split("func ")[0]

    slope = (0.3, 0.1)
    rx, ry = 50.0, 40.0
    pin = (20.0, -10.0)
    infs = influences_side_slope(slope, rx, ry, pin)
    assert len(infs) >= 2

    a = slope_at((-20.0, 10.0), slope, infs)
    b = slope_at((20.0, -10.0), slope, infs)
    assert math.hypot(a[0] - b[0], a[1] - b[1]) > 0.02

    eps = 0.5
    p = (8.0, -6.0)
    h_dx = (height_at((p[0] + eps, p[1]), slope, infs) - height_at((p[0] - eps, p[1]), slope, infs)) / (
        2.0 * eps
    )
    h_dy = (height_at((p[0], p[1] + eps), slope, infs) - height_at((p[0], p[1] - eps), slope, infs)) / (
        2.0 * eps
    )
    num = (-h_dx, -h_dy)
    ana = slope_at(p, slope, infs)
    err = math.hypot(num[0] - ana[0], num[1] - ana[1])
    assert err < 0.02, f"slope must be -∇height, err={err}"

    assert influences_side_slope((0.0, 0.0), rx, ry, pin) == []

    # Bowl: depression at center (amp negative) vs rim — plane held flat for the probe.
    bowl = influences_bowl((0.3, 0.0), rx, ry, (0.0, 0.0))
    flat = (0.0, 0.0)
    h_c = height_at((0.0, 0.0), flat, bowl)
    h_r = height_at((28.0, 0.0), flat, bowl)
    assert h_c < h_r, f"bowl center should be low, {h_c} vs {h_r}"

    # False front: high face short of pin (positive Y).
    ff = influences_false_front((0.3, 0.0), rx, ry, pin)
    h_front = height_at((0.0, ry * 0.42), flat, ff)
    h_back = height_at((0.0, -ry * 0.2), flat, ff)
    assert h_front > h_back, f"false front face should be high, {h_front} vs {h_back}"

    # Honest field: 2% plane, SIDE_SLOPE span is feet not ski-slope.
    ft_per_px = 3.0 / 2.25
    mid = (0.048, 0.0)  # practice-green mag → 2.0% plane
    assert abs(math.hypot(*slope_at((0.0, 0.0), mid, [])) * 100 - 2.016) < 0.05
    mid_infs = influences_side_slope(mid, 28.0, 34.0, (8.0, -6.0))
    hs = []
    for iy in range(16):
        for ix in range(16):
            x = (ix / 15.0 - 0.5) * 2.0 * 28.0
            y = (iy / 15.0 - 0.5) * 2.0 * 34.0
            if (x / 28.0) ** 2 + (y / 34.0) ** 2 > 1.0:
                continue
            hs.append(height_at((x, y), mid, mid_infs))
    span_ft = (max(hs) - min(hs)) * ft_per_px
    assert span_ft < 3.5, f"SIDE_SLOPE 2% span too tall: {span_ft:.2f} ft"

    print("green_slope_field_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Mirrors HoleData.green_height_at / green_slope_at — fails if field logic drifts."""
from __future__ import annotations

import math
import sys


def influences(slope, rx, ry, pin):
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


def height_at(local, slope, infs):
    h = -(slope[0] * local[0] + slope[1] * local[1])
    for inf in infs:
        dx = local[0] - inf["pos"][0]
        dy = local[1] - inf["pos"][1]
        s2 = inf["sigma"] ** 2
        h += inf["amp"] * math.exp(-(dx * dx + dy * dy) / (2.0 * s2))
    return h


def slope_at(local, slope, infs):
    sx, sy = slope
    for inf in infs:
        dx = local[0] - inf["pos"][0]
        dy = local[1] - inf["pos"][1]
        s2 = inf["sigma"] ** 2
        fall = math.exp(-(dx * dx + dy * dy) / (2.0 * s2))
        k = (inf["amp"] / s2) * fall
        sx += dx * k
        sy += dy * k
    return (sx, sy)


def main() -> int:
    from pathlib import Path

    gen = Path(__file__).parent.joinpath("hole_generator.gd").read_text(encoding="utf-8")
    # Slope must not ramp with round-progression t — per-hole roll instead.
    assert "lerpf(0.04, 0.42, t)" not in gen
    assert "lerpf(0.04, 0.42, rng.randf())" in gen

    slope = (0.3, 0.1)
    rx, ry = 50.0, 40.0
    pin = (20.0, -10.0)
    infs = influences(slope, rx, ry, pin)
    assert len(infs) >= 2, "expected crown + pin influences"

    a = slope_at((-20.0, 10.0), slope, infs)
    b = slope_at((20.0, -10.0), slope, infs)
    dist = math.hypot(a[0] - b[0], a[1] - b[1])
    assert dist > 0.02, f"slope must vary by position, got {dist}"

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

    flat_infs = influences((0.0, 0.0), rx, ry, pin)
    assert flat_infs == []
    assert slope_at((10.0, 10.0), (0.0, 0.0), flat_infs) == (0.0, 0.0)

    print("green_slope_field_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

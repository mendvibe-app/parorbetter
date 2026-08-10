#!/usr/bin/env python3
"""Short pitch + mild path must not lose most of planned distance (LW playtest)."""
from __future__ import annotations

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts" / "ball" / "ball.gd").read_text(encoding="utf-8")

PX = 2.25


def short_shot_line_scale(total_yards: float) -> float:
    return max(0.10, min(1.0, total_yards / 55.0))


def short_shot_hang_scale(total_yards: float) -> float:
    if total_yards >= 40.0:
        return 1.0
    return max(0.42, min(1.0, 0.42 + (1.0 - 0.42) * (total_yards / 40.0)))


def sim_flight_along_yd(
    total_yd: float,
    power: float,
    loft_mul: float,
    shape: float,
    *,
    preserve_speed: bool,
) -> float:
    """Crude flight along-yards at land (launch = -Y). Mirrors ball._process_flight spin."""
    total_px = total_yd * PX
    loft = 0.9 * loft_mul
    air_time = (0.55 + (1.15 - 0.55) * power) * loft
    air_time *= short_shot_hang_scale(total_yd)
    air_frac = 0.82  # pitch band
    air_px = total_px * air_frac
    base_speed = air_px / max(air_time, 0.05)
    stab = 0.94
    spin = shape * 0.95 * stab * 0.35 * 1.22  # PERFECT × LW grip
    spin *= short_shot_line_scale(total_yd)

    vx, vy = 0.0, -base_speed
    launch = (0.0, -1.0)
    dt = 1.0 / 60.0
    t = 0.0
    x = y = 0.0
    while t < air_time - 1e-9:
        spd = math.hypot(vx, vy)
        along_spd = max(vx * launch[0] + vy * launch[1], 0.0)
        ss = max(0.08, min(1.0, along_spd / 180.0))
        fr = (1.0, 0.0)
        if spd > 0.01 and abs(spin) > 1e-6:
            vx += fr[0] * spin * 28.0 * dt * ss
            vy += fr[1] * spin * 28.0 * dt * ss
            if preserve_speed:
                n = math.hypot(vx, vy)
                if n > 1e-6:
                    vx = vx / n * spd
                    vy = vy / n * spd
        along_after = vx * launch[0] + vy * launch[1]
        if along_after < along_spd * 0.15:
            lat = vx * fr[0] + vy * fr[1]
            along_spd2 = max(along_spd * 0.35, 12.0)
            vx = launch[0] * along_spd2 + fr[0] * lat * 0.55
            vy = launch[1] * along_spd2 + fr[1] * lat * 0.55
        x += vx * dt
        y += vy * dt
        t += dt
        along = max(x * launch[0] + y * launch[1], 0.0)
        path_len = math.hypot(x, y)
        if along >= air_px or path_len >= air_px:
            break
    along = max(x * launch[0] + y * launch[1], 0.0)
    return along / PX


def main() -> int:
    assert "short_shot_hang_scale" in PHYS
    assert "normalized() * spd" in BALL
    assert "path_len" in BALL

    # Hang scale cuts soft LW hang (playtest apex was ~41 on 13 yd).
    assert short_shot_hang_scale(13.0) < 0.75
    assert short_shot_hang_scale(50.0) == 1.0

    # Mild path short pitch: carry along should stay near planned air share.
    planned_air = 13.0 * 0.82
    along = sim_flight_along_yd(13.0, 0.20, 1.62, -0.22, preserve_speed=True)
    assert along >= planned_air * 0.85, f"short pitch carry too low: {along:.2f} yd (want ≥ {planned_air*0.85:.2f})"

    # Stronger path still shouldn't collapse to ~half total before roll.
    along_hard = sim_flight_along_yd(13.0, 0.20, 1.62, -0.55, preserve_speed=True)
    assert along_hard >= planned_air * 0.70, f"shaped pitch carry too low: {along_hard:.2f}"

    print(
        f"short_pitch_distance_check: ok along13={along:.2f}yd "
        f"hang13={short_shot_hang_scale(13.0):.2f} line13={short_shot_line_scale(13.0):.2f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

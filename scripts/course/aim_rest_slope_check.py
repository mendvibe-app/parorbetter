#!/usr/bin/env python3
"""Aim rest circle follows on-green slope; flat remainder stays on the aim line."""
from __future__ import annotations

import math
import sys
from pathlib import Path

DIR = Path(__file__).parent
PHYS = DIR.joinpath("../ball/ball_physics.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("hole_controller.gd").read_text(encoding="utf-8")

PX_PER_YARD = 2.25
FT_TO_PX = PX_PER_YARD / 3.0
ROLL_DURATION_FRAC = 0.40
PUTT_PACE_SCALE = 0.35
GREEN_FRICTION_FT = 1.8
GREEN_GRAVITY_FT = 32.174
GREEN_GRAVITY_SCALE = 0.45
SETTLE = 0.525
DT = 1.0 / 30.0


def putt_decel() -> float:
    return GREEN_FRICTION_FT * FT_TO_PX / (ROLL_DURATION_FRAC**2) * PUTT_PACE_SCALE**2


def g_px() -> float:
    return (
        GREEN_GRAVITY_FT
        * GREEN_GRAVITY_SCALE
        * FT_TO_PX
        / (ROLL_DURATION_FRAC**2)
        * PUTT_PACE_SCALE**2
    )


def preview(land, direction, roll_px, grade):
    """Mirrors BallPhysics.preview_green_roll with a constant grade."""
    if roll_px < 2.0:
        return land
    decel = putt_decel()
    ln = math.hypot(*direction)
    vel = [direction[0] / ln * math.sqrt(2.0 * decel * roll_px), direction[1] / ln * math.sqrt(2.0 * decel * roll_px)]
    pos = [land[0], land[1]]
    for _ in range(240):
        spd = math.hypot(*vel)
        if spd < SETTLE:
            break
        vel[0] += grade[0] * g_px() * DT
        vel[1] += grade[1] * g_px() * DT
        spd = math.hypot(*vel)
        if spd > 1e-9:
            ns = max(spd - decel * DT, 0.0)
            vel[0] *= ns / spd
            vel[1] *= ns / spd
        else:
            vel[0] = vel[1] = 0.0
        pos[0] += vel[0] * DT
        pos[1] += vel[1] * DT
    return pos


def main() -> int:
    assert "static func preview_green_roll" in PHYS
    assert "preview_green_roll(land, bearing.normalized(), roll_px, _preview_green_slope)" in CTRL
    assert "func _preview_green_slope" in CTRL
    assert "_on_painted_green(pos)" in CTRL.split("func _preview_green_slope")[1].split("func ")[0]

    land = (0.0, 0.0)
    direction = (0.0, -1.0)
    roll = 20.0 * FT_TO_PX  # 20 ft chip remainder on green

    flat = preview(land, direction, roll, (0.0, 0.0))
    along_flat = -flat[1]
    assert abs(along_flat - roll) < roll * 0.08, f"flat rest {along_flat:.1f} vs {roll:.1f}"
    assert abs(flat[0]) < 0.5, f"flat should stay on line {flat[0]:.2f}"

    down = preview(land, direction, roll, (0.0, -0.02))
    up = preview(land, direction, roll, (0.0, 0.02))
    side = preview(land, direction, roll, (0.02, 0.0))
    assert -down[1] > along_flat + 1.0 * FT_TO_PX, f"downhill should run on { -down[1]:.1f} vs {along_flat:.1f}"
    assert -up[1] < along_flat - 1.0 * FT_TO_PX, f"uphill should die short { -up[1]:.1f} vs {along_flat:.1f}"
    assert abs(side[0]) > 0.8 * FT_TO_PX, f"sidehill should break {side[0]:.2f}px"

    print(
        "aim_rest_slope_check: ok  "
        f"flat={along_flat / FT_TO_PX:.1f}ft  "
        f"down={(-down[1] - along_flat) / FT_TO_PX:+.1f}ft  "
        f"up={(-up[1] - along_flat) / FT_TO_PX:+.1f}ft  "
        f"break={side[0] / FT_TO_PX * 12:.1f}in"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

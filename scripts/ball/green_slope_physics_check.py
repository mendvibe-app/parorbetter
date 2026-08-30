#!/usr/bin/env python3
"""Putt + on-green roll share g·sinθ; 2% 20-ft break sits in the Pelz band."""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
PHYS = DIR.joinpath("ball_physics.gd").read_text(encoding="utf-8")
BALL = DIR.joinpath("ball.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")
DATA = DIR.joinpath("../course/hole_data.gd").read_text(encoding="utf-8")
GEN = DIR.joinpath("../course/hole_generator.gd").read_text(encoding="utf-8")
GS = DIR.joinpath("../autoload/game_state.gd").read_text(encoding="utf-8")

PX_PER_YARD = 2.25
FT_TO_PX = PX_PER_YARD / 3.0
ROLL_DURATION_FRAC = 0.40
PUTT_PACE_SCALE = 0.35
GREEN_FRICTION_FT = 1.8
GREEN_GRAVITY_FT = 32.174
GREEN_GRAVITY_SCALE = 0.45
SETTLE = 0.525
PLANE_W = 0.42


def _f(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def putt_decel() -> float:
    return GREEN_FRICTION_FT * FT_TO_PX / (ROLL_DURATION_FRAC**2) * PUTT_PACE_SCALE**2


def green_gravity_px() -> float:
    return (
        GREEN_GRAVITY_FT
        * GREEN_GRAVITY_SCALE
        * FT_TO_PX
        / (ROLL_DURATION_FRAC**2)
        * PUTT_PACE_SCALE**2
    )


def sim(grade_lat: float, grade_along: float, dist_ft: float = 20.0, extra: float = 1.0):
    """Dying launch toward -Y. Returns (break_in, leftover_ft)."""
    dist = dist_ft * FT_TO_PX
    decel = putt_decel()
    g = green_gravity_px()
    v0 = math.sqrt(2.0 * decel * dist) * extra
    vx, vy = 0.0, -v0
    x, y = 0.0, dist
    t = 0.0
    dt = 1.0 / 60.0
    while t < 20.0:
        spd = math.hypot(vx, vy)
        if spd < SETTLE:
            break
        vx += grade_lat * g * dt
        vy += grade_along * g * dt
        spd = math.hypot(vx, vy)
        if spd > 1e-9:
            ns = max(spd - decel * dt, 0.0)
            vx *= ns / spd
            vy *= ns / spd
        x += vx * dt
        y += vy * dt
        t += dt
    return x / FT_TO_PX * 12.0, -y / FT_TO_PX


def main() -> int:
    assert _f(PHYS, "GREEN_GRAVITY_FT") == GREEN_GRAVITY_FT
    assert _f(PHYS, "GREEN_GRAVITY_SCALE") == GREEN_GRAVITY_SCALE
    assert "static func green_slope_accel" in PHYS
    assert "static func green_gravity_px" in PHYS
    assert "PUTT_BREAK_LATERAL" not in BALL
    assert "PUTT_BREAK_ALONG" not in BALL
    assert "PUTT_BREAK_CAL_DECEL" not in PHYS
    assert "slope * 16" not in BALL
    assert "green_slope_accel(slope)" in BALL
    # Putt and on-green chip/pitch/flop/full share the same line.
    roll = BALL.split("func _process_roll")[1].split("func ")[0]
    assert "_is_putt or _lie == \"Green\"" in roll or "_is_putt or _lie == 'Green'" in roll
    assert "green_slope_accel" in roll
    assert "_lie != \"Green\"" in roll  # anti-backup + plan clamp skip on green
    assert "ContourProfile.FLAT" in DATA.split("func green_slope_at")[1].split("func ")[0]
    assert "lerpf(0.024, 0.048, t)" in GEN
    assert "lerpf(0.048, mag_ceil, t)" in GEN
    assert "PIN_MAX_LOCAL_SLOPE / HoleData.GREEN_PLANE_WEIGHT" in GEN
    assert "PIN_MAX_LOCAL_SLOPE := 0.03" in GEN
    assert "GREEN_CONTOUR_AMP_SCALE := 1.0" in DATA
    assert "tap_in_break: float = 0.01" in GS
    assert "Vector2(0.048, 0.0)" in CTRL  # practice green 2% plane
    make_sg = CTRL.split("func _make_short_game_hole")[1].split("func ")[0]
    assert "green_slope = Vector2.ZERO" in make_sg

    # Plane: stored mag 0.048 → 2.016%.
    assert abs(0.048 * PLANE_W - 0.02016) < 1e-6

    break_in, leftover = sim(0.02, 0.0, 20.0)
    pelz = 2.0 * 20.0 / 2.0  # grade% × feet / 2
    assert 15.0 <= abs(break_in) <= 25.0, f"2% 20ft break {break_in:.1f}in (Pelz {pelz:.0f})"
    assert abs(abs(break_in) - pelz) < 6.0, f"break {break_in:.1f} vs Pelz {pelz:.0f}"

    _, down = sim(0.0, -0.02, 20.0)
    _, up = sim(0.0, 0.02, 20.0)
    assert down > 1.5, f"downhill 2% should run on, leftover={down:.2f}ft"
    assert up < -1.5, f"uphill 2% should die short, leftover={up:.2f}ft"

    print(
        f"green_slope_physics_check: ok  2%20ft={break_in:.1f}in  "
        f"down={down:+.1f}ft up={up:+.1f}ft  g_scale={GREEN_GRAVITY_SCALE}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

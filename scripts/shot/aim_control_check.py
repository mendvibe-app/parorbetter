#!/usr/bin/env python3
"""Cone tip on axis + touch aim offset; Feedback must not stack glance with panel."""

from __future__ import annotations

import math
import sys
from pathlib import Path

DIR = Path(__file__).parent
AIM = DIR.joinpath("aim_control.gd").read_text(encoding="utf-8")
HOLE = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")


def cone_tip_lateral(
    origin: tuple[float, float],
    target: tuple[float, float],
    tip_frac: float = 0.88,
) -> float:
    """Lateral offset of tip from from→to. Mirrors AimControl.make_aim_cone tip."""
    ax, ay = target[0] - origin[0], target[1] - origin[1]
    length = math.hypot(ax, ay)
    if length < 0.001:
        ax, ay, length = 0.0, -1.0, 8.0
    elif length < 8.0:
        ax, ay = ax * (8.0 / length), ay * (8.0 / length)
        length = 8.0
    dx, dy = ax / length, ay / length
    tip = (origin[0] + dx * length * tip_frac, origin[1] + dy * length * tip_frac)
    right = (-dy, dx)
    return (tip[0] - origin[0]) * right[0] + (tip[1] - origin[1]) * right[1]


def cone_dir(
    origin: tuple[float, float],
    target: tuple[float, float],
) -> tuple[float, float]:
    """Unit direction after short-length pad — must keep aim bearing."""
    ax, ay = target[0] - origin[0], target[1] - origin[1]
    length = math.hypot(ax, ay)
    if length < 0.001:
        return (0.0, -1.0)
    if length < 8.0:
        ax, ay = ax * (8.0 / length), ay * (8.0 / length)
        length = 8.0
    return (ax / length, ay / length)


def touch_aim_screen(x: float, y: float, ox: float = 0.0, oy: float = -72.0) -> tuple[float, float]:
    return (x + ox, y + oy)


def main() -> int:
    origin = (540.0, 860.0)
    target = (620.0, -80.0)
    assert abs(cone_tip_lateral(origin, target)) < 1e-6
    assert abs(cone_tip_lateral(origin, (540.0, -80.0))) < 1e-6

    # ~5 ft putt (~3.75 px): pad length but keep bearing toward cup (not straight up).
    ball = (540.0, -80.0)
    cup = (544.0, -83.5)  # slightly up-right of ball
    dx, dy = cone_dir(ball, cup)
    assert dx > 0.0 and dy < 0.0  # still toward cup
    assert abs(dx - 0.0) > 0.1  # must NOT collapse to Vector2(0, -1)
    assert "length < 0.001" in AIM  # only zero-length may fall back to up

    assert "TOUCH_AIM_OFFSET_PX" in AIM
    assert "func touch_aim_screen" in AIM
    assert "touch_aim_screen" in HOLE
    # Mouse path stays raw — offset is touch-only
    assert "_world_mouse()" in HOLE
    sx, sy = touch_aim_screen(540.0, 900.0)
    assert sx == 540.0 and sy == 828.0

    # Duplicate glance: Feedback must not reprint summary/glance when panel shows
    assert "feedback.text = _last_report.summary_line()" not in HOLE
    assert "glance_text().replace" not in HOLE

    # Shape-aware Green lie (painted silhouette alpha)
    assert "_on_painted_green" in HOLE and "_green_img" in HOLE

    # Putt aim: white fading line, no iron cone / dispersion circle
    refresh = HOLE.split("func _refresh_aim_visuals")[1].split("func ")[0]
    assert 'ball.get_lie() == "Green"' in refresh
    assert "len_px * 0.88" in refresh
    assert "_aim_cone.visible = on and not is_putt" in HOLE
    assert "_aim_circle.visible = on and not is_putt" in HOLE
    assert "Gradient.new()" in HOLE
    assert "_pin_ref_line.gradient = null" in refresh

    # Cone is tight at the ball and its flanks run tangent to the dispersion circle
    # (real-golf reasoning: takeoff direction reads easily by eye, landing footprint
    # is the genuinely uncertain part) — a flat cap at a fixed fraction of the shot
    # length would either poke past the circle's edge or collapse to a gap short of
    # it depending on shot length, so the flank must be solved geometrically instead.
    assert "10.0 * inv_z, radius_px, _power_previewing" in refresh
    assert "func _tangent_point" in AIM
    assert "far_w := far_half_w" not in AIM
    assert "far_half_w * (0.7 if power_preview else 1.0)" not in AIM

    # The two flanks end tangent to the circle at different points — the outline
    # must stroke them as separate open polylines, never a straight segment
    # connecting one tangent point to the other, or that segment redraws the old
    # seam across the circle's face.
    assert "_aim_cone_edge_r" in HOLE
    assert "edge_l.append(pts[n - 1])" in HOLE
    assert "edge_r.append(pts[3])" in HOLE

    print("aim_control_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

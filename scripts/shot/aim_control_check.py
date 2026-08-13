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

    # Greenside aim: recommend-aware solve — Full floor must not snap pitch/chip corridor.
    assert "recommend_shot_type" in AIM
    assert "shot_type_uses_full_pocket" in AIM
    assert "solve_committed_power(" in AIM
    # Overclub snap only when recommended type uses full pocket.
    assert "shot_type_uses_full_pocket(rec)" in AIM or "shot_type_uses_full_pocket" in AIM
    phys = DIR.joinpath("../ball/ball_physics.gd").read_text(encoding="utf-8")
    assert "func shot_type_uses_full_pocket" in phys
    assert "func _shot_type_uses_full_pocket" not in phys

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

    # Pitch/flop preview snap: amplitude floors at POWER_POCKET_LO; circle must
    # match a tick-hit, not the unfloored pin solve. Full/punch/chip/putt unchanged.
    planned = HOLE.split("func _aim_planned_total_yd")[1].split("func ")[0]
    apply_prev = HOLE.split("func _apply_committed_preview")[1].split("func ")[0]
    tree = HOLE.split("func _aim_tree_clearance")[1].split("func ")[0]
    assert 'shot_type == "pitch" or shot_type == "flop"' in planned
    assert "maxf(power, BallPhysics.POWER_POCKET_LO)" in planned
    assert 'st == "pitch" or st == "flop"' in apply_prev
    assert "maxf(power, BallPhysics.POWER_POCKET_LO)" in apply_prev
    # Confirm Aim flop cap: 5-arg estimate only on the pitch/flop branch.
    assert "ball.get_lie_severity(), st" in apply_prev
    assert "estimate_carry_yards(power, club_max, lie, ball.get_lie_severity())" in apply_prev
    # Tree tint / pin-lock / force-preview stay on unfloored solve.
    assert "POWER_POCKET_LO" not in tree
    force_prev = HOLE.split("func _aim_force_preview")[1].split("func ")[0]
    assert "POWER_POCKET_LO" not in force_prev
    refit = HOLE.split("func _refit_aim_along_bearing")[1].split("func ")[0]
    assert "POWER_POCKET_LO" not in refit

    POWER_POCKET_LO = 0.60
    POWER_POCKET_HI = 0.92
    FLOP_MAX_YD = 30.0

    def solved_power(pin_yd: float, club_max: float) -> float:
        need = max(pin_yd, 2.0)
        return min(max(need / club_max, 0.05), POWER_POCKET_HI)

    def preview_yd(pin_yd: float, club_max: float, shot_type: str, floor: bool) -> float:
        power = solved_power(pin_yd, club_max)
        if floor and shot_type in ("pitch", "flop"):
            power = max(power, POWER_POCKET_LO)
        if shot_type == "flop":
            power = min(power, FLOP_MAX_YD / max(club_max, 1.0))
        total = club_max * power
        if shot_type == "flop":
            total = min(total, FLOP_MAX_YD)
        return total

    cases = (
        ("pitch", 110.0, 46.0),
        ("pitch", 80.0, 33.0),
        ("pitch", 65.0, 27.0),
    )
    after = (66.0, 48.0, 39.0)
    for (st, club, pin), want in zip(cases, after):
        assert abs(preview_yd(pin, club, st, False) - pin) < 1e-9
        assert abs(preview_yd(pin, club, st, True) - want) < 1e-9
        assert abs(want - club * POWER_POCKET_LO) < 1e-9  # tick-hit
    # Flop at a sub-30 pin: floor would overshoot, FLOP_MAX_YD still wins.
    assert abs(preview_yd(20.0, 65.0, "flop", False) - 20.0) < 1e-9
    assert abs(preview_yd(20.0, 65.0, "flop", True) - FLOP_MAX_YD) < 1e-9
    # Other types: floor flag must not change the number.
    for st, club, pin in (
        ("full", 160.0, 140.0),
        ("punch", 160.0, 140.0),
        ("chip", 65.0, 15.0),
        ("putt", 25.0, 10.0),
    ):
        assert abs(preview_yd(pin, club, st, False) - preview_yd(pin, club, st, True)) < 1e-9

    print("aim_control_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

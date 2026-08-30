#!/usr/bin/env python3
"""Contract check: putt pace is real (fixed max) and MISS doesn't triple-stack distance."""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
PHYS = DIR.joinpath("ball_physics.gd").read_text(encoding="utf-8")
GRADE = DIR.joinpath("../shot/tempo_grade.gd").read_text(encoding="utf-8")
HOLE = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")

PUTTER_MAX_YD = 25.0
POWER_FLOOR = 0.0267
MARKER_MIN = 0.26
MARKER_MAX = 0.88
BEND = 1.0


def recommended_power(remaining_yd: float, club_max: float) -> float:
    # Putt path's own floor: 2 ft (0.667 yd), not the full-shot 2 yd / 0.05 floor.
    need = max(remaining_yd, 0.667)
    return min(max(need / club_max, POWER_FLOOR), 1.0)


def power_to_u(committed_power: float) -> float:
    p = min(max(committed_power, POWER_FLOOR), 1.0)
    u = math.log(p / POWER_FLOOR) / math.log(1.0 / POWER_FLOOR)
    return min(max(u, 0.0), 1.0) ** BEND


def u_to_power(u: float) -> float:
    lin = min(max(u, 0.0), 1.0) ** (1.0 / BEND)
    return POWER_FLOOR * (1.0 / POWER_FLOOR) ** lin


def marker_frac(committed_power: float) -> float:
    u = power_to_u(committed_power)
    return MARKER_MIN + (MARKER_MAX - MARKER_MIN) * u


def power_from_frac(frac: float) -> float:
    span = MARKER_MAX - MARKER_MIN
    t = min(max((frac - MARKER_MIN) / max(span, 0.001), 0.0), 1.0)
    return u_to_power(t)


def frac_for_ft(ft: float, club_max_yd: float = PUTTER_MAX_YD) -> float:
    yd = ft / 3.0
    power = min(max(yd / max(club_max_yd, 1.0), POWER_FLOOR), 1.0)
    return marker_frac(power)


def old_linear_frac_for_ft(ft: float, club_max_yd: float = 40.0) -> float:
    """Pre-change mapping, for the gap-widening comparison below."""
    old_floor = 0.05
    old_min = 0.22
    old_max = 0.88
    yd = ft / 3.0
    power = min(max(yd / max(club_max_yd, 1.0), old_floor), 1.0)
    u = min(max((power - old_floor) / max(1.0 - old_floor, 0.001), 0.0), 1.0)
    return old_min + (old_max - old_min) * u


PUTT_CONTACT_MUL = {
    "PERFECT": 1.0,
    "GOOD": 1.0,
    "THIN": 1.06,
    "FAT": 0.90,
    "MISS": 0.78,
}


def putt_roll_yards(committed_power: float, tempo_power_mul: float, contact: str) -> float:
    """Mirror resolve_distance putt yards — amplitude first, mild Green contact extra."""
    result_power = committed_power * tempo_power_mul
    return PUTTER_MAX_YD * result_power * PUTT_CONTACT_MUL[contact]


def main() -> int:
    assert "PUTTER_MAX_YD := 25.0" in PHYS
    assert "remaining_yd * 1.6" not in PHYS
    assert "max_yards\": PUTTER_MAX_YD" in PHYS or "PUTTER_MAX_YD" in PHYS

    # Fixed max → short vs long putts commit different %
    p3 = recommended_power(3.0, PUTTER_MAX_YD)
    p20 = recommended_power(20.0, PUTTER_MAX_YD)
    assert abs(p3 - 3.0 / PUTTER_MAX_YD) < 1e-6 or abs(p3 - max(3.0, 0.667) / PUTTER_MAX_YD) < 1e-6
    assert p20 > p3 + 0.2, (p3, p20)
    assert abs(p20 - 20.0 / PUTTER_MAX_YD) < 1e-6

    # Old self-cancel bug: remaining/(remaining*1.6) was always 0.625
    assert abs(p3 - 0.625) > 0.2
    assert abs(p20 - 0.625) > 0.01

    # Source: resolve_distance always multiplies contact (putt uses Green curve).
    assert "power_mul *= contact_multiplier(contact, lie)" in PHYS
    assert "static func resolve_distance" in PHYS
    assert "static func contact_multiplier" in PHYS
    assert 'if lie == "Green":' in PHYS.split("static func contact_multiplier")[1].split("static func")[0]
    assert "return 0.90" in PHYS
    assert "return 0.78" in PHYS
    # MISS dist_err removed (no 0.65 branch)
    assert "dist_err = 0.65" not in PHYS
    putt_launch = PHYS.split("if is_putt:")[1].split("return {")[0]
    assert "dist_err = 1.12" not in putt_launch
    assert "dist_err = 0.78" not in putt_launch

    # Mild Green curve at same amplitude: FAT dies, THIN runs, PERFECT == GOOD.
    committed = recommended_power(14.0, PUTTER_MAX_YD)
    intended = PUTTER_MAX_YD * committed
    good_roll = putt_roll_yards(committed, 0.80, "GOOD")
    fat_roll = putt_roll_yards(committed, 0.80, "FAT")
    thin_roll = putt_roll_yards(committed, 0.80, "THIN")
    perf_roll = putt_roll_yards(committed, 0.80, "PERFECT")
    assert fat_roll < good_roll, (fat_roll, good_roll)
    assert thin_roll > good_roll, (thin_roll, good_roll)
    assert abs(perf_roll - good_roll) < 1e-9, (perf_roll, good_roll)
    assert fat_roll / good_roll >= 0.85, fat_roll / good_roll  # no 0.68 cliff
    smash_roll = putt_roll_yards(committed, 1.55, "THIN")
    assert smash_roll >= intended * 1.5, smash_roll
    old_stack = intended * 0.50 * 0.4 * 0.65
    assert smash_roll > old_stack * 4.0, (smash_roll, old_stack)

    # No putt MISS distance floor — stroke length owns pace
    PUTT = DIR.joinpath("../shot/putt_stroke.gd").read_text(encoding="utf-8")
    assert "power_mul = minf(power_mul, 0.50)" not in PUTT
    assert "min(power_mul, 0.50)" not in PUTT
    assert "PUTT_CONTACT_LINE_FLOOR := 0.08" in PUTT
    assert "PUTT_CONTACT_LINE_MISS := 0.14" in PUTT
    assert "contact_multiplier(contact, lie)" in PUTT
    assert "static func putt_line_miss" in PHYS
    assert "PUTT_LINE_MISS_SCALE := 0.84" in PHYS
    # 6 ft THIN floor mishit → ~5 in at the cup (was ~1 in at 0.14).
    path, scale, cscale, stance_term = 0.08, 0.84, 1.15, 1.25 - 0.5 * 0.7
    flat_in = path * scale * cscale * stance_term * (6.0 / 3.0) * 36.0
    assert 4.0 <= flat_in <= 6.0, flat_in
    assert "_fill_putt_debug" in HOLE
    assert "PuttStroke" in DIR.joinpath("../shot/shot_routine.gd").read_text(encoding="utf-8")

    # Pace UI: aim stays blind of live pace/pin numbers — line only, stroke owns power.
    assert "_refresh_putt_line_feedback" in HOLE
    assert "_putt_line_soft_snap" in HOLE
    assert "PUTT_LINE_SNAP_DEG := 3.0" in HOLE
    assert "PUTT_LINE_SNAP_MAX_FT := 8.0" in HOLE
    assert "_refresh_putt_pace_feedback" not in HOLE
    assert "Putt — set line & pace" not in HOLE
    assert "debug_putt_line_aim" not in HOLE
    GS = DIR.joinpath("../autoload/game_state.gd").read_text(encoding="utf-8")
    DBG = DIR.joinpath("../debug/debug_controls.gd").read_text(encoding="utf-8")
    assert "debug_putt_line_aim" not in GS
    assert "PuttLineAim" not in DBG
    assert "_setup_putt_line_aim_toggle" not in DBG
    assert "putt_debug" in DBG
    apply_aim = HOLE.split("func _apply_aim_world")[1].split("func ")[0]
    assert "retarget_bearing" in apply_aim
    assert "clamp_aim(world)" not in apply_aim
    assert "Pin %d yd" not in HOLE
    assert "pace %d yd" not in HOLE
    assert 'feedback.text = "Putter"' not in HOLE
    # Internal pace still computed for grading (aim distance → committed_power)
    assert "aim_yd" in HOLE or "distance_to(_aim_target)" in HOLE

    # Long lag reachable: putter max is 75 ft (25 yd) with headroom past the hole;
    # putts beyond 75 ft clamp to full pad (acceptable/realistic — was 120 ft ceiling).
    assert PUTTER_MAX_YD * 3.0 >= 75.0
    p60 = recommended_power(60.0 / 3.0, PUTTER_MAX_YD)
    assert p60 < 0.95, p60  # headroom past the hole for a realistic long lag
    p95 = recommended_power(95.0 / 3.0, PUTTER_MAX_YD)
    assert p95 == 1.0, p95  # beyond 75 ft clamps to full pad
    assert "SCALE_LABELED_FT := [3, 6, 12, 25, 50]" in PUTT
    assert "SCALE_TICK_FT := [8, 18, 70]" in PUTT
    assert "MARKER_ON_PACE_FRAC" not in PUTT
    assert "power_from_frac" in PUTT
    assert "frac_for_ft" in PUTT
    GESTURE = Path(DIR.parent / "shot/tempo_gesture.gd").read_text(encoding="utf-8")
    assert "putt_aim_ft" not in GESTURE
    assert "SCALE_LABELED_FT" in GESTURE

    # Distance-driven green sizing; contours still vary slope for break.
    GEN = DIR.joinpath("../course/hole_generator.gd").read_text(encoding="utf-8")
    assert "GREEN_AREA_FLOOR_SQFT" in GEN
    assert "_green_target_radii_px" in GEN
    assert "rng.randf_range(0.28, 0.48)" in GEN
    assert "lerpf(0.12, 0.03, t)" in GEN  # less early FLAT
    # Putt camera Phase 2 — true-scale readable framing (see putt_camera_zoom_check).
    assert "PUTT_VIEW_FRAC" in HOLE
    assert "func _putt_frame_zoom" in HOLE
    assert "PUTT_ZOOM_CAP" in HOLE
    assert "CUP_RADIUS := 0.198" in HOLE
    assert "CUP_CAPTURE_RADIUS" in HOLE
    BALL = Path(DIR.parent / "ball/ball.gd").read_text(encoding="utf-8")
    assert "const BALL_R_PUTT" in BALL
    # Visual ball is always true-scale (legacy BALL_R 3.5 retired).
    assert "BALL_R := 3.5" not in BALL
    # Visible hole∶ball ≈ real 4.25/1.68. Spans = sprite fill (remeasure if PNG padding changes).
    BALL_OPAQUE = 33.0  # assets/ball/ball.png opaque bbox
    CUP_DARK = 43.0  # cup.png void+rim (luma≤60); matches see=catch
    m_putt = re.search(r"const BALL_R_PUTT\s*:=\s*([0-9.]+)", BALL)
    m_cup_r = re.search(r"const CUP_RADIUS\s*:=\s*([0-9.]+)", HOLE)
    assert m_putt and m_cup_r
    vis_ball = (BALL_OPAQUE / 64.0) * (float(m_putt.group(1)) * 2.0)
    vis_cup = (CUP_DARK / 64.0) * (float(m_cup_r.group(1)) * 2.0)
    ball_cup_ratio = vis_cup / vis_ball
    assert abs(ball_cup_ratio - 2.53) < 0.06, (ball_cup_ratio, vis_cup, vis_ball)
    assert "PUTT_BREAK_LATERAL" not in BALL
    assert "PUTT_BREAK_ALONG" not in BALL
    # Gravity accel uses the same FRAC²·k² as putt_decel so FRAC changes don't nuclear-bend.
    assert "green_gravity_px" in PHYS
    assert "GREEN_GRAVITY_SCALE" in PHYS
    assert "green_slope_accel" in BALL
    assert "PUTT_SETTLE_SPEED" in PHYS
    assert "PUTT_PACE_SCALE" in PHYS
    assert "putt_decel_px" in PHYS
    assert "PUTT_SETTLE_SPEED" in BALL
    # Cup capture: speed gate + dark-hole radius (not full collar sprite).
    assert "CUP_CAPTURE_MAX_SPEED := 11.2" in BALL
    assert "CUP_CAPTURE_RADIUS" in BALL
    assert "_try_cup_capture" in BALL
    assert "CUP_CAPTURE_MAX_SPEED" in BALL.split("func _try_cup_capture")[1].split("func ")[0]
    assert "putt_decel_px" in BALL
    # Capture ≈ visible dark disc in cup.png (43/64 of sprite span) — see = catch.
    m_vis = re.search(r"const CUP_RADIUS\s*:=\s*([0-9.]+)", HOLE)
    m_cap = re.search(r"const CUP_CAPTURE_RADIUS\s*:=\s*([0-9.]+)", HOLE)
    assert m_vis and m_cap
    vis = float(m_vis.group(1))
    cap = float(m_cap.group(1))
    DARK_FRAC = 43.0 / 64.0
    assert abs(cap / vis - DARK_FRAC) < 0.05, (cap, vis, cap / vis, DARK_FRAC)
    assert "CUP_CAPTURE_RADIUS" in HOLE.split("_add_circle(course_root, _cup_pos")[1].split("\n")[0]
    # Settle-in make uses the same disc (not full CUP_RADIUS shelf).
    assert "distance_to(_cup_pos) < CUP_CAPTURE_RADIUS" in HOLE
    # Break/pace-on-slope: scripts/ball/green_slope_physics_check.py (Pelz band).
    # Short putts must launch above putt settle (old 10 px/s floor killed 3–8 ft).
    px_per_yd = 2.25
    ft_to_px = px_per_yd / 3.0
    m_frac = re.search(r"const FLIGHT_DURATION_FRAC\s*:=\s*([0-9.]+)", PHYS)
    assert m_frac, "FLIGHT_DURATION_FRAC missing"
    roll_frac = float(m_frac.group(1))
    a_green = 1.8 * ft_to_px / (roll_frac * roll_frac)
    settle = 1.5
    for ft in (3.0, 6.0, 8.0):
        s = (ft / 3.0) * px_per_yd
        v = (2.0 * a_green * s) ** 0.5
        assert v > settle, (ft, v, settle, a_green)
    assert "_sync_pin_flag_visible" in HOLE
    assert "PIN_FLAG_SCREEN_PX" in HOLE
    assert "course_pin_flag.gd" in HOLE or "CoursePinFlagScr" in HOLE
    assert "get_lie() == \"Green\"" in HOLE or 'get_lie() == "Green"' in HOLE
    # Pin out on green only — not _is_putt_context (28 yd yank).
    sync = HOLE.split("func _sync_pin_flag_visible")[1].split("func ")[0]
    assert "_is_putt_context" not in sync
    assert "_update_pin_flag_wind" in HOLE
    assert "set_wind" in HOLE
    assert "stream_rotation" not in HOLE
    # Fairway must not run through putting surface (rectangular texture patch)
    fairway_fn = HOLE.split("func _add_bent_fairway")[1].split("func ")[0]
    assert "top_y := GREEN_Y + maxf(hole.green_radius_y" in fairway_fn
    assert "GREEN_Y - 20.0)" not in fairway_fn  # old tip punched through green
    # Practice green sized to match; start stays on surface
    assert "d.green_radius_x = 38.0" in HOLE
    assert "yards_to_pixels(12.0)" in HOLE

    # Log map round-trips exactly (u <-> power are inverse for any BEND)
    for p in (POWER_FLOOR, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0):
        back = u_to_power(power_to_u(p))
        assert abs(back - p) < 1e-6, (p, back)

    # 6 ft vs 8 ft pad gap is now thumb-resolvable — at least 3x the old linear gap
    new_gap = frac_for_ft(8.0) - frac_for_ft(6.0)
    old_gap = old_linear_frac_for_ft(8.0) - old_linear_frac_for_ft(6.0)
    assert new_gap >= old_gap * 3.0, (new_gap, old_gap)

    # Log invariant: a fixed pad-space nudge is a fixed % distance change,
    # whether the putt is short, mid, or long.
    delta = 0.03
    ratios = []
    for ft in (6.0, 20.0, 60.0):
        target = frac_for_ft(ft)
        p_target = power_from_frac(target)
        p_nudged = power_from_frac(target + delta)
        ratios.append(p_nudged / p_target)
    assert max(ratios) - min(ratios) < 1e-6, ratios

    print("putt_pace_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

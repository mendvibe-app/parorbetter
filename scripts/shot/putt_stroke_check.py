#!/usr/bin/env python3
"""Contract check for putt stroke — absolute linear pad, soft ticks, amplitude tiers."""
from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
PUTT = DIR.joinpath("putt_stroke.gd").read_text(encoding="utf-8")
GESTURE = DIR.joinpath("tempo_gesture.gd").read_text(encoding="utf-8")
ROUTINE = DIR.joinpath("shot_routine.gd").read_text(encoding="utf-8")
REPORT = DIR.joinpath("../systems/shot_report.gd").read_text(encoding="utf-8")
METER = DIR.joinpath("meter_display.gd").read_text(encoding="utf-8")
HOLE = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")

MARKER_MIN = 0.22
MARKER_MAX = 0.88
POWER_FLOOR = 0.05
BAND_HALF = 0.06
BAND_PERFECT = 0.50
BAND_GOOD = 1.15
ARC_FLOOR = 0.10
ARC_SCALE = 0.16
CLUB_MAX_YD = 40.0


def power_to_u(committed_power: float) -> float:
    return min(max((committed_power - POWER_FLOOR) / max(1.0 - POWER_FLOOR, 0.001), 0.0), 1.0)


def u_to_power(u: float) -> float:
    return POWER_FLOOR + (1.0 - POWER_FLOOR) * min(max(u, 0.0), 1.0)


def marker_frac(committed_power: float) -> float:
    u = power_to_u(committed_power)
    return MARKER_MIN + (MARKER_MAX - MARKER_MIN) * u


def power_from_frac(frac: float) -> float:
    span = MARKER_MAX - MARKER_MIN
    t = min(max((frac - MARKER_MIN) / max(span, 0.001), 0.0), 1.0)
    return u_to_power(t)


def frac_for_ft(ft: float, club_max_yd: float = CLUB_MAX_YD) -> float:
    yd = ft / 3.0
    power = min(max(yd / max(club_max_yd, 1.0), POWER_FLOOR), 1.0)
    return marker_frac(power)


def arc_allowance(stroke_frac: float) -> float:
    s = min(max(stroke_frac, 0.0), 1.0)
    return ARC_FLOOR + ARC_SCALE * s * s


def contact_tier(abs_n: float, frac_err: float, incomplete: bool = False) -> str:
    if incomplete and abs_n > BAND_GOOD:
        return "MISS"
    if incomplete:
        return "FAT" if frac_err < 0.0 else "THIN"
    if abs_n <= BAND_PERFECT:
        return "PERFECT"
    if abs_n <= BAND_GOOD:
        return "GOOD"
    # Pace error only — never auto-MISS from amplitude on a complete stroke
    return "FAT" if frac_err < 0.0 else "THIN"


def main() -> int:
    assert "MARKER_MIN_FRAC := 0.22" in PUTT
    assert "MARKER_MAX_FRAC := 0.88" in PUTT
    assert "MARKER_ON_PACE_FRAC" not in PUTT
    assert "SCALE_MULS" not in PUTT
    assert "power_mul_from_frac" not in PUTT
    assert "frac_for_relative_ft" not in PUTT
    assert "relative_scale_ticks" not in PUTT
    assert "SCALE_LABELED_FT := [3, 6, 10, 15, 30]" in PUTT
    assert "SCALE_TICK_FT := [45, 60, 90]" in PUTT
    assert "func power_from_frac" in PUTT
    assert "func frac_for_ft" in PUTT
    assert "BAND_HALF := 0.06" in PUTT
    assert "PuttStroke.grade" in ROUTINE
    assert 'shot_type == "putt"' in ROUTINE
    assert "putt_target_frac" in GESTURE
    assert "putt_aim_ft" not in GESTURE
    assert "putt_aim_ft" not in ROUTINE
    assert "backswing_frac" in GESTURE
    assert "max_lateral" in GESTURE
    assert "_draw_putt" in GESTURE
    assert "_draw_putt_amplitude" in METER
    assert 'p_lie == "Green"' in REPORT or "lie == \"Green\"" in REPORT
    assert "_is_tap_in" in HOLE
    assert "tap_in_yd" in HOLE or "GameState.tap_in_yd" in HOLE

    assert "putt_show_marker" in GESTURE
    assert "putt_show_marker = practice_mode" in ROUTINE
    assert "_draw_putt_practice_marker" in GESTURE
    assert "if putt_show_marker:" in GESTURE
    assert "func _draw_putt_follow_cue" in GESTURE
    assert "func _draw_putt_soft_scale" in GESTURE
    assert "SCALE_LABELED_FT" in GESTURE
    assert "SCALE_TICK_FT" in GESTURE
    assert "frac_for_ft" in GESTURE
    soft_scale = GESTURE.split("func _draw_putt_soft_scale")[1].split("func ")[0]
    assert "aim_i" not in soft_scale and "putt_aim_ft" not in soft_scale
    tick_draw = GESTURE.split("func _draw_putt_scale_tick")[1].split("func ")[0]
    assert "arc_allowance(frac)" in tick_draw
    assert "draw_line(mark, edge" in tick_draw
    assert "_putt_follow_cap_frac" in GESTURE
    assert "follow_cap_frac" in GESTURE
    assert "follow_cap_frac" in PUTT
    assert "match_target" in PUTT

    assert "FT_PER_YD := 3.0" in PUTT
    assert "func yd_to_ft" in PUTT
    assert "Target %d ft → %d" in PUTT
    assert "didn't finish through the ball" in PUTT
    assert 'visible = p_type != "putt"' in METER or "visible = p_type != \"putt\"" in METER
    assert "Address · feel your pace · through the ball." in ROUTINE

    # Absolute map: 10 ft and 100 ft sit at different pad marks
    p10 = (10.0 / 3.0) / CLUB_MAX_YD
    p100 = (100.0 / 3.0) / CLUB_MAX_YD
    f10 = marker_frac(p10)
    f100 = marker_frac(p100)
    assert f100 > f10 + 0.15, (f10, f100)
    assert f10 > MARKER_MIN
    assert f100 < MARKER_MAX

    # Round-trip power ↔ frac
    for p in (0.05, 0.25, 0.5, 0.75, 1.0):
        f = marker_frac(p)
        back = power_from_frac(f)
        assert abs(back - p) < 1e-5, (p, f, back)

    # Soft scale landmarks land on the same map
    assert abs(frac_for_ft(30.0) - marker_frac((30.0 / 3.0) / CLUB_MAX_YD)) < 1e-6
    assert frac_for_ft(15.0) < frac_for_ft(45.0) < frac_for_ft(90.0)

    # Smash past short commit → power_mul > 1
    commit = p10
    smash = power_from_frac(MARKER_MAX) / max(commit, POWER_FLOOR)
    assert smash > 1.5, smash

    order = {"PERFECT": 0, "GOOD": 1, "FAT": 2, "THIN": 2, "MISS": 3}
    prev = -1
    for delta in (0.0, 0.02, 0.05, 0.10, 0.20):
        abs_n = abs(delta) / BAND_HALF
        tier = contact_tier(abs_n, delta)
        assert order[tier] >= prev, (delta, tier, prev)
        prev = order[tier]
    assert contact_tier(1.5, -0.1) == "FAT"
    assert contact_tier(1.5, 0.1) == "THIN"
    assert contact_tier(0.2, 0.0) == "PERFECT"
    assert contact_tier(3.0, -0.2) == "FAT"
    assert contact_tier(3.0, 0.2) == "THIN"
    assert contact_tier(3.0, 0.2, incomplete=True) == "MISS"

    assert arc_allowance(0.8) > arc_allowance(0.2)
    assert arc_allowance(0.0) == ARC_FLOOR
    assert "ARC_FLOOR := 0.10" in PUTT
    assert "ARC_SCALE := 0.16" in PUTT
    assert "0.22 if _is_putt()" in GESTURE or "y := 0.22 if _is_putt()" in GESTURE
    assert "0.92 if _is_putt()" in GESTURE or "y := 0.92 if _is_putt()" in GESTURE
    assert "56.0 / maxf(tex_size.x" in GESTURE

    assert "MATCH_TOL" in PUTT
    assert "power_mul = minf(power_mul, 0.50)" not in PUTT
    assert "min(power_mul, 0.50)" not in PUTT
    grade_body = PUTT.split("static func grade(")[1].split("static func ")[0]
    assert grade_body.count("ContactQuality.MISS") == 1  # incomplete only
    assert "BAND_SHORT_LONG" not in PUTT
    assert "power_from_frac(actual)" in grade_body

    print("putt_stroke_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

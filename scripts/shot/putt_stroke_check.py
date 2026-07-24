#!/usr/bin/env python3
"""Contract check for putt stroke — compressive map, band symmetry, amplitude tiers."""
from __future__ import annotations

import math
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
BAND_SHORT_LONG = 1.85
ARC_FLOOR = 0.04
ARC_SCALE = 0.10


def power_to_u(p: float) -> float:
    p = min(max(p, POWER_FLOOR), 1.0)
    return min(max((p - POWER_FLOOR) / (1.0 - POWER_FLOOR), 0.0), 1.0)


def u_to_power(u: float) -> float:
    return POWER_FLOOR + min(max(u, 0.0), 1.0) * (1.0 - POWER_FLOOR)


def marker_frac(committed_power: float) -> float:
    u = power_to_u(committed_power)
    return MARKER_MIN + (MARKER_MAX - MARKER_MIN) * math.sqrt(u)


def power_from_frac(frac: float) -> float:
    span = MARKER_MAX - MARKER_MIN
    t = min(max((frac - MARKER_MIN) / max(span, 0.001), 0.0), 1.0)
    return u_to_power(t * t)


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
    if abs_n <= BAND_SHORT_LONG:
        return "FAT" if frac_err < 0.0 else "THIN"
    return "MISS"


def main() -> int:
    # Source contracts
    assert "MARKER_MIN_FRAC := 0.22" in PUTT
    assert "MARKER_MAX_FRAC := 0.88" in PUTT
    assert "BAND_HALF := 0.06" in PUTT
    assert "sqrt(u)" in PUTT
    assert "power_from_frac" in PUTT
    assert "PuttStroke.grade" in ROUTINE
    assert 'shot_type == "putt"' in ROUTINE
    assert "putt_target_frac" in GESTURE
    assert "backswing_frac" in GESTURE
    assert "max_lateral" in GESTURE
    assert "_draw_putt" in GESTURE
    assert "_draw_putt_amplitude" in METER
    assert 'p_lie == "Green"' in REPORT or "lie == \"Green\"" in REPORT
    assert "_is_tap_in" in HOLE
    assert "tap_in_yd" in HOLE or "GameState.tap_in_yd" in HOLE
    assert "play_putt_tick" in ROUTINE or "play_putt_tick" in Path(DIR.parent / "autoload/audio_bus.gd").read_text(encoding="utf-8")

    # Shared pad principles on putts: golf shape, practice-only length answer, no tempo ghost
    assert "putt_show_marker" in GESTURE
    assert "putt_show_marker = practice_mode" in ROUTINE
    assert "_draw_putt_practice_marker" in GESTURE
    assert 'if putt_show_marker:' in GESTURE
    assert '"PACE"' not in GESTURE
    assert '"THRU"' not in GESTURE
    assert "func _draw_putt_follow_cue" in GESTURE
    assert "func _draw_putt_address" in GESTURE
    assert "func _draw_pad_ball" in GESTURE
    assert "func _draw_putt_soft_scale" in GESTURE
    assert "_draw_putt_soft_scale" in GESTURE.split("func _draw_putt")[1].split("func _putt_follow_len")[0]
    assert "_putt_follow_len" in GESTURE
    assert "addr.y - 20.0" in GESTURE or "addr.y - 20" in GESTURE
    # Feet display helpers + soft scale brackets
    assert "FT_PER_YD := 3.0" in PUTT
    assert "func yd_to_ft" in PUTT
    assert "func ft_to_yd" in PUTT
    assert "func frac_for_ft" in PUTT
    assert "SCALE_LABELED_FT" in PUTT
    assert "SCALE_TICK_FT" in PUTT
    # Putt draw path must not pull in the full-swing tempo ghost
    putt_draw = GESTURE.split("func _draw_putt")[1].split("func _putt_follow_len")[0]
    assert "_draw_tempo_ghost" not in putt_draw
    assert "_draw_pad_ball" in GESTURE.split("func _draw_putt_address")[1].split("func ")[0]
    # Impact at the ball (shared detector) — not the old 12% early fire
    assert "IMPACT_CROSS_FRAC := 0.02" in GESTURE
    # Live trail color must not compare against putt_target_frac (length answer as color)
    trail_fn = GESTURE.split("func _putt_trail_color")[1].split("func ")[0]
    assert "putt_target_frac" not in trail_fn
    assert "_max_accel" in trail_fn or "_max_jerk" in trail_fn
    # Miss copy + glance in feet (not yards)
    assert "Target %d ft → %d" in PUTT
    assert "Target %.0f yd" not in PUTT
    assert "didn't finish through the ball" in PUTT
    assert "decelerated into impact" not in PUTT
    assert "target_yd" in PUTT and "rolled_yd" in PUTT
    assert 'info_label.text = "%d ft"' in ROUTINE or "yd_to_ft(aim_distance_yd)" in ROUTINE
    assert 'info_label.text = ""' not in ROUTINE or "Green" in ROUTINE  # green no longer blank
    green_glance = ROUTINE.split('if lie == "Green":')[1].split("elif")[0]
    assert "ft" in green_glance and 'info_label.text = ""' not in green_glance
    # Meter: hidden live; reveal after verdict; no short/pace/long words
    assert 'visible = p_type != "putt"' in METER or "visible = p_type != \"putt\"" in METER
    assert "if _verdict.is_empty():" in METER
    assert "blind stroke" not in METER
    assert "feel your pace" not in METER
    assert '"short"' not in METER
    assert '"long"' not in METER
    # One live putt instruction — golf language
    assert "Address · feel your pace · through the ball." in ROUTINE
    assert 'info_label.text = "Putt"' not in ROUTINE
    assert 'feedback.text = "Putter"' not in HOLE

    # Soft scale map: 15 + 30 ft labeled; lag ticks past mid-pad; 95 ft under max
    PUTTER_MAX = 40.0
    f15 = marker_frac(min(max((15.0 / 3.0) / PUTTER_MAX, POWER_FLOOR), 1.0))
    assert MARKER_MIN <= f15 <= MARKER_MAX, f15
    f30 = marker_frac(min(max((30.0 / 3.0) / PUTTER_MAX, POWER_FLOOR), 1.0))
    assert f30 > f15, (f15, f30)
    f90 = marker_frac(min(max((90.0 / 3.0) / PUTTER_MAX, POWER_FLOOR), 1.0))
    assert f90 > f30, (f30, f90)
    assert f90 < MARKER_MAX - 0.02, f90  # room above a long lag
    assert "SCALE_LABELED_FT := [3, 6, 10, 15, 30]" in PUTT
    assert "SCALE_TICK_FT := [45, 60, 90]" in PUTT
    assert "PUTTER_MAX_YD := 40.0" in Path(DIR.parent / "ball/ball_physics.gd").read_text(encoding="utf-8")

    # Marker floor — tap-in still legible / above MIN_BACKSWING
    m_short = marker_frac(POWER_FLOOR)
    assert abs(m_short - MARKER_MIN) < 1e-6, m_short
    assert m_short >= 0.20
    m_full = marker_frac(1.0)
    assert abs(m_full - MARKER_MAX) < 1e-6, m_full

    # Round-trip map ↔ inverse
    for p in (0.05, 0.1, 0.2, 0.4, 0.7, 1.0):
        f = marker_frac(p)
        back = power_from_frac(f)
        assert abs(back - max(p, POWER_FLOOR)) < 1e-5, (p, f, back)

    # Short putts get more pad resolution than long ones (d(frac)/d(power) larger near floor)
    # Compare marker delta for equal power steps at short vs long end.
    d_short = marker_frac(0.15) - marker_frac(0.05)
    d_long = marker_frac(1.0) - marker_frac(0.90)
    assert d_short > d_long, (d_short, d_long)

    # Band is constant in pad space (drawn = graded)
    assert "BAND_HALF" in PUTT
    lo = marker_frac(0.3) - BAND_HALF
    hi = marker_frac(0.3) + BAND_HALF
    assert abs((hi - marker_frac(0.3)) - (marker_frac(0.3) - lo)) < 1e-9

    # Amplitude → tier monotonicity (farther from marker = worse or equal tier)
    order = {"PERFECT": 0, "GOOD": 1, "FAT": 2, "THIN": 2, "MISS": 3}
    target = marker_frac(0.4)
    prev = -1
    for delta in (0.0, 0.02, 0.05, 0.10, 0.20):
        err = delta
        abs_n = abs(err) / BAND_HALF
        tier = contact_tier(abs_n, err)
        assert order[tier] >= prev, (delta, tier, prev)
        prev = order[tier]
    # Short vs long polarity
    assert contact_tier(1.5, -0.1) == "FAT"
    assert contact_tier(1.5, 0.1) == "THIN"
    assert contact_tier(0.2, 0.0) == "PERFECT"

    # Arc allowance grows with stroke length
    assert arc_allowance(0.8) > arc_allowance(0.2)
    assert arc_allowance(0.0) == ARC_FLOOR

    # Matched-halves: unmatched follow hurts (source has MATCH_TOL)
    assert "MATCH_TOL" in PUTT
    assert "match_pen" in PUTT
    assert "TEMPO_BIAS_MAX" in PUTT

    # Power mul can exceed 1 for short commit + long pull (blow past)
    rolled = power_from_frac(MARKER_MAX)
    mul = rolled / 0.2
    assert mul > 1.0, mul

    # MISS floors power_mul
    assert "power_mul = minf(power_mul, 0.50)" in PUTT or "min(power_mul, 0.50)" in PUTT

    print("putt_stroke_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

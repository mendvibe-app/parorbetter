#!/usr/bin/env python3
"""Contract check for putt stroke — absolute log pad, soft ticks, amplitude tiers."""
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

MARKER_MIN = 0.26
MARKER_MAX = 0.88
POWER_FLOOR = 0.0267
BAND_HALF = 0.06
BAND_PERFECT = 0.50
BAND_GOOD = 1.15
ARC_FLOOR = 0.10
ARC_SCALE = 0.16
CLUB_MAX_YD = 25.0
BEND = 1.0


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
    assert "MARKER_MIN_FRAC := 0.26" in PUTT
    assert "MARKER_MAX_FRAC := 0.88" in PUTT
    assert "MARKER_ON_PACE_FRAC" not in PUTT
    assert "SCALE_MULS" not in PUTT
    assert "power_mul_from_frac" not in PUTT
    assert "frac_for_relative_ft" not in PUTT
    assert "relative_scale_ticks" not in PUTT
    assert "SCALE_LABELED_FT := [3, 6, 12, 25, 50]" in PUTT
    assert "SCALE_TICK_FT := [8, 18, 70]" in PUTT
    assert "func power_from_frac" in PUTT
    assert "func frac_for_ft" in PUTT
    assert "BAND_HALF := 0.06" in PUTT
    assert "PuttStroke.grade" in ROUTINE
    assert 'shot_type == "putt"' in ROUTINE
    # Phase 3: coaching yards match launch/report product (lie + contact).
    assert "BallPhysics.lie_multiplier" in PUTT
    assert "BallPhysics.contact_multiplier" in PUTT
    assert "contact_multiplier(contact, lie)" in PUTT
    assert "PUTT_CONTACT_LINE_FLOOR := 0.08" in PUTT
    assert "PUTT_CONTACT_LINE_MISS := 0.14" in PUTT
    assert "current_lie" in ROUTINE
    assert "swing_shape" in ROUTINE
    assert "putt_target_frac" in GESTURE
    assert "putt_aim_ft" not in GESTURE
    assert "putt_aim_ft" not in ROUTINE
    assert "backswing_frac" in GESTURE
    assert "max_lateral" in GESTURE
    assert "_draw_putt" in GESTURE
    assert "_draw_putt_amplitude" in METER
    assert 'p_lie == "Green"' in REPORT or "lie == \"Green\"" in REPORT
    assert "_is_tap_in" in HOLE
    assert "_putt_path_break_mag" in HOLE
    assert "tap_in_yd" in HOLE or "GameState.tap_in_yd" in HOLE

    assert "putt_show_marker" in GESTURE
    assert "putt_show_marker" in ROUTINE
    assert "practice_mode" in ROUTINE
    # Chip scored strokes show pace tick (Phase 2); putt stays practice-blind on length.
    assert "shot_type == \"chip\"" in ROUTINE or "putt_show_marker = practice_mode" in ROUTINE
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
    assert "mark.x - half" in tick_draw, "ft labels sit left of the lane, not over the fill"
    assert "draw_line(mark, edge" in tick_draw
    assert "frac <= PuttStroke.MARKER_MIN_FRAC" in tick_draw, "skip floor-collapsed labels"
    assert "LABEL_PX := 28" in tick_draw
    # Labeled marks stay readable on the log pad
    assert frac_for_ft(20.0) - frac_for_ft(10.0) > 0.05
    assert frac_for_ft(40.0) - frac_for_ft(20.0) > 0.10
    assert "_putt_follow_cap_frac" in GESTURE
    assert "follow_cap_frac" in GESTURE
    assert "follow_cap_frac" in PUTT
    assert "match_target" in PUTT

    assert "FT_PER_YD := 3.0" in PUTT
    assert "func yd_to_ft" in PUTT
    assert "Target %d ft → %d" in PUTT
    assert "didn't finish through the ball" in PUTT
    # Unified diagnosis — no steady/shaky/lurch on putt notes
    assert "bal_word" not in PUTT
    assert '"lurch"' not in PUTT and "'lurch'" not in PUTT
    assert "diagnose_swing" in PUTT
    assert "balance_detail" in PUTT
    assert 'p_type != "putt"' in METER
    assert "Address · feel your pace · through the ball." in ROUTINE

    # Absolute map: 10 ft and 70 ft (near the new 75 ft ceiling) sit at different pad marks
    p10 = (10.0 / 3.0) / CLUB_MAX_YD
    p70 = (70.0 / 3.0) / CLUB_MAX_YD
    f10 = marker_frac(p10)
    f70 = marker_frac(p70)
    assert f70 > f10 + 0.15, (f10, f70)
    assert f10 > MARKER_MIN
    assert f70 < MARKER_MAX

    # Round-trip power ↔ frac
    for p in (POWER_FLOOR, 0.05, 0.25, 0.5, 0.75, 1.0):
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
    assert "y = 0.22" in GESTURE and "_is_putt()" in GESTURE
    assert "0.92" in GESTURE and "_is_putt()" in GESTURE
    assert "72.0 / maxf(tex_size.x" in GESTURE

    assert "MATCH_TOL" in PUTT
    assert "power_mul = minf(power_mul, 0.50)" not in PUTT
    assert "min(power_mul, 0.50)" not in PUTT
    grade_body = PUTT.split("static func grade(")[1].split("static func ")[0]
    assert grade_body.count("contact = ShotResult.ContactQuality.MISS") == 1  # incomplete only
    assert "BAND_SHORT_LONG" not in PUTT
    assert "power_from_frac(actual)" in grade_body
    # Phase 4: chip overpull keeps THIN label but drops distance tax (no GOOD→THIN cliff).
    assert "frac_err > 0.0 and contact_mul < 1.0" in grade_body
    assert "_draw_mishit_risk_marks" in GESTURE
    assert "BAND_GOOD" in GESTURE.split("func _draw_mishit_risk_marks")[1].split("func ")[0]
    assert "mishit risk" in ROUTINE

    # Chip Fairway: overpull past BAND_GOOD must not land shorter than GOOD edge.
    CM = {"PERFECT": 1.06, "GOOD": 1.0, "THIN": 0.82, "FAT": 0.68}

    def chip_rolled_yd(actual: float, commit: float, club: float = 80.0) -> tuple[str, float]:
        target = marker_frac(commit)
        frac_err = actual - target
        abs_n = abs(frac_err) / BAND_HALF
        contact = contact_tier(abs_n, frac_err)
        rolled = power_from_frac(actual)
        c_mul = CM[contact]
        # Mirror Phase 4: no distance tax on overpull THIN.
        if frac_err > 0.0 and c_mul < 1.0:
            c_mul = 1.0
        yd = max(0.05, min(1.0, rolled)) * club * c_mul
        return contact, yd

    for rem in (8.0, 12.0, 18.0):
        commit = rem / 80.0
        tgt = marker_frac(commit)
        edge = tgt + BAND_GOOD * BAND_HALF
        _c_g, yd_good = chip_rolled_yd(edge, commit)
        c_t, yd_thin = chip_rolled_yd(edge + 1e-5, commit)
        assert c_t == "THIN", (rem, c_t)
        assert yd_thin + 1e-6 >= yd_good, (
            f"chip {rem:.0f}yd cliff: GOOD-edge {yd_good:.3f} → THIN {yd_thin:.3f}"
        )
        # Still smash-long for big overpull vs on-target.
        _c_big, yd_big = chip_rolled_yd(min(tgt + 0.20, MARKER_MAX), commit)
        _c_on, yd_on = chip_rolled_yd(tgt, commit)
        assert yd_big > yd_on

    print("putt_stroke_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

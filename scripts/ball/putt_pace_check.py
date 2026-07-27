#!/usr/bin/env python3
"""Contract check: putt pace is real (fixed max) and MISS doesn't triple-stack distance."""
from __future__ import annotations

import math
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


def putt_roll_yards(committed_power: float, tempo_power_mul: float, contact: str) -> float:
    """Mirror launch_velocity putt distance — amplitude owns pace; no contact dist_err."""
    # Tempo already applied into result.power = committed * tempo_power_mul
    result_power = committed_power * tempo_power_mul
    # No contact_multiplier and no FAT/THIN dist_err on putt distance
    power_mul = result_power * 1.0
    total = PUTTER_MAX_YD * power_mul
    _ = contact  # line only; distance unchanged
    return total


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

    # Source: putt path skips contact_multiplier on distance
    assert "if not is_putt:" in PHYS
    assert "contact_multiplier(result.contact_quality)" in PHYS
    # MISS dist_err removed (no 0.65 branch)
    assert "ShotResult.ContactQuality.MISS:" not in PHYS.split("if is_putt:")[1].split("return {")[0] or \
        "dist_err = 0.65" not in PHYS
    assert "dist_err = 0.65" not in PHYS
    # Amplitude owns pace — no FAT/THIN distance stack on putts
    putt_branch = PHYS.split("if is_putt:")[1].split("return {")[0]
    assert "dist_err = 1.12" not in putt_branch
    assert "dist_err = 0.78" not in putt_branch
    assert "no FAT/THIN distance stack" in putt_branch or "Amplitude owns pace" in putt_branch

    # Amplitude owns pace — contact label does not change yards
    committed = recommended_power(14.0, PUTTER_MAX_YD)
    intended = PUTTER_MAX_YD * committed
    smash_roll = putt_roll_yards(committed, 1.55, "THIN")
    assert smash_roll >= intended * 1.5, smash_roll
    old_stack = intended * 0.50 * 0.4 * 0.65
    assert smash_roll > old_stack * 4.0, (smash_roll, old_stack)
    # FAT leave = amplitude only (same yards as GOOD at same power_mul)
    fat_roll = putt_roll_yards(committed, 0.80, "FAT")
    good_roll = putt_roll_yards(committed, 0.80, "GOOD")
    assert abs(fat_roll - good_roll) < 1e-9, (fat_roll, good_roll)

    # No putt MISS distance floor — stroke length owns pace
    PUTT = DIR.joinpath("../shot/putt_stroke.gd").read_text(encoding="utf-8")
    assert "power_mul = minf(power_mul, 0.50)" not in PUTT
    assert "min(power_mul, 0.50)" not in PUTT
    assert "PuttStroke" in DIR.joinpath("../shot/shot_routine.gd").read_text(encoding="utf-8")

    # Pace UI: aim/stroke stay blind — no live pace/pin numbers on screen
    assert "_refresh_putt_pace_feedback" in HOLE
    assert "Putt — set line & pace" in HOLE
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

    # Greens ~60–130 ft diameter (real-ish); long lags can span most of a medium green
    GEN = DIR.joinpath("../course/hole_generator.gd").read_text(encoding="utf-8")
    assert "lerpf(22.0, 48.0, green_size)" in GEN
    assert "lerpf(0.10, 0.48, rng.randf())" in GEN
    assert "lerpf(0.12, 0.03, t)" in GEN  # less early FLAT
    # Putt camera zooms out on lags so distance reads
    assert "view_min * 0.52" in HOLE
    assert "dist * 0.90" in HOLE
    assert "CUP_RADIUS := 2.4" in HOLE
    BALL = Path(DIR.parent / "ball/ball.gd").read_text(encoding="utf-8")
    assert "BALL_R := 3.5" in BALL
    assert "BALL_R_PUTT := 1.0" in BALL
    assert "PUTT_BREAK_LATERAL := 90.0" in BALL
    assert "PUTT_BREAK_ALONG := 55.0" in BALL
    # Mid-slope 40 ft must bend ~2 ball-widths (was sub-pixel at K=22)
    px_per_yd = 2.25
    travel_px = (40.0 / 3.0) * px_per_yd
    friction = 108.0
    t_roll = (2.0 * friction * travel_px) ** 0.5 / friction
    bend = 0.5 * (0.22 * 90.0) * t_roll * t_roll
    assert bend >= 4.0, bend
    assert bend / (1.0 * 2.0) >= 1.8, bend  # ≥ ~1.8 ball diameters
    assert "_sync_pin_flag_visible" in HOLE
    assert "12.0 / fh" in HOLE or "12.0 / float" in HOLE
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

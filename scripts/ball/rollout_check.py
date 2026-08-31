#!/usr/bin/env python3
"""Club/shot-type rollout: carry ramp, check mul, green identity, PURE spin-back."""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
PHYS = (DIR / "ball_physics.gd").read_text(encoding="utf-8")
BALL = (DIR / "ball.gd").read_text(encoding="utf-8")
DEBUG = (DIR / "../debug/debug_controls.gd").read_text(encoding="utf-8")


def _f(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    assert m, f"missing: {pattern}"
    return float(m.group(1))


PX_PER_YARD = _f(PHYS, r"const PX_PER_YARD\s*:=\s*([0-9.]+)")
FT_TO_PX = PX_PER_YARD / 3.0
FLIGHT_DURATION_FRAC = _f(PHYS, r"const FLIGHT_DURATION_FRAC\s*:=\s*([0-9.]+)")
ROLL_DURATION_FRAC = FLIGHT_DURATION_FRAC
PUTT_PACE_SCALE = _f(PHYS, r"const PUTT_PACE_SCALE\s*:=\s*([0-9.]+)")
CHIP_PACE_SCALE = _f(PHYS, r"const CHIP_PACE_SCALE\s*:=\s*([0-9.]+)")
CARRY_FRAC_LONG = _f(PHYS, r"const CARRY_FRAC_LONG\s*:=\s*([0-9.]+)")
CARRY_FRAC_SHORT = _f(PHYS, r"const CARRY_FRAC_SHORT\s*:=\s*([0-9.]+)")
CARRY_FRAC_EASE = _f(PHYS, r"const CARRY_FRAC_EASE\s*:=\s*([0-9.]+)")
CHECK_MUL_LONG = _f(PHYS, r"const CHECK_MUL_LONG\s*:=\s*([0-9.]+)")
CHECK_MUL_SHORT = _f(PHYS, r"const CHECK_MUL_SHORT\s*:=\s*([0-9.]+)")
WEDGE_FAMILY_MAX_YD = _f(PHYS, r"const WEDGE_FAMILY_MAX_YD\s*:=\s*([0-9.]+)")
SPINBACK_FT = _f(PHYS, r"const SPINBACK_FT\s*:=\s*([0-9.]+)")


def air_fraction_full(club_max: float) -> float:
    t = max(0.0, min(1.0, (club_max - 65.0) / (260.0 - 65.0)))
    t = t ** CARRY_FRAC_EASE
    return CARRY_FRAC_SHORT + (CARRY_FRAC_LONG - CARRY_FRAC_SHORT) * t


def roll_friction_for(lie: str) -> float:
    if lie == "Green":
        return 1.8
    if lie in ("Fairway", "Tee"):
        return 10.0
    if lie == "Rough":
        return 18.0
    if lie == "Sand":
        return 28.0
    return 12.0


def roll_decel_px(lie: str) -> float:
    f = ROLL_DURATION_FRAC
    return roll_friction_for(lie) * FT_TO_PX / max(f * f, 0.01)


def putt_decel_px() -> float:
    k = PUTT_PACE_SCALE
    return roll_decel_px("Green") * k * k


def roll_check_mul(club_max: float, shot_type: str, contact: str = "GOOD") -> float:
    t = max(0.0, min(1.0, (club_max - 65.0) / (260.0 - 65.0)))
    full = CHECK_MUL_SHORT + (CHECK_MUL_LONG - CHECK_MUL_SHORT) * t
    mul = full
    if shot_type == "pitch":
        mul = full * 1.25
    elif shot_type == "flop":
        mul = full * 1.4
    elif shot_type == "punch":
        mul = full * 0.85
    elif shot_type in ("chip", "putt"):
        mul = 1.0
    if contact == "THIN":
        mul *= 0.92
    return mul


def is_checking_club(club_max: float, shot_type: str) -> bool:
    if shot_type in ("pitch", "flop"):
        return True
    return shot_type == "full" and club_max <= WEDGE_FAMILY_MAX_YD + 0.5


def landing_roll_decel_px(
    lie: str, shot_type: str = "full", club_max: float = 160.0, contact: str = "GOOD"
) -> float:
    if shot_type == "putt" or (shot_type == "chip" and lie == "Green"):
        return putt_decel_px()
    check = roll_check_mul(club_max, shot_type, contact)
    a = roll_decel_px("Fairway") if lie == "Green" else roll_decel_px(lie)
    if lie != "Green" and shot_type in ("chip", "pitch", "flop"):
        a *= CHIP_PACE_SCALE * CHIP_PACE_SCALE
    return a * check


def main() -> None:
    assert "static func roll_check_mul" in PHYS
    assert "static func is_checking_club" in PHYS
    assert "static func landing_roll_decel_px" in PHYS
    assert "SPINBACK_FT" in PHYS
    assert "_club_max_yards" in BALL
    assert "_contact" in BALL
    begin = BALL.split("func _begin_roll")[1].split("func ")[0]
    assert "_sync_ground_lie()" in begin
    assert "sqrt(2.0 * a * remain)" in begin
    assert "is_checking_club" in begin
    assert "-_launch_dir" in begin
    roll = BALL.split("func _process_roll")[1].split("func ")[0]
    assert "green_slope_accel" in roll
    assert '_shot_type != "chip"' in roll
    assert "velocity.dot(_launch_dir) >= 0.0" in roll
    clamp = roll[roll.find("along >= _planned_distance_px") : roll.find("_finish_settle")]
    assert "_lie != \"Green\"" not in clamp
    assert "roll %+.0f yd (plan %.0f)" in DEBUG

    assert 0.78 <= CARRY_FRAC_LONG <= 0.82, CARRY_FRAC_LONG
    assert abs(CARRY_FRAC_SHORT - 0.98) < 1e-9
    assert abs(CARRY_FRAC_EASE - 1.5) < 1e-9
    assert 2.0 <= SPINBACK_FT <= 6.0, SPINBACK_FT
    assert abs(CHECK_MUL_LONG - 0.9) < 1e-9
    assert abs(CHECK_MUL_SHORT - 1.5) < 1e-9

    dr_roll = 1.0 - air_fraction_full(260.0)
    pw_roll = 1.0 - air_fraction_full(110.0)
    i7_roll = 1.0 - air_fraction_full(160.0)
    assert 0.18 <= dr_roll <= 0.22, dr_roll
    assert 0.02 <= pw_roll <= 0.06, pw_roll
    assert dr_roll > pw_roll
    assert i7_roll < dr_roll * 0.55, (i7_roll, dr_roll)  # 7i must not inherit wood release

    assert abs(roll_check_mul(260.0, "full") - 0.9) < 1e-9
    assert abs(roll_check_mul(65.0, "full") - 1.5) < 1e-9
    assert roll_check_mul(110.0, "full", "THIN") < roll_check_mul(110.0, "full", "GOOD")
    assert abs(roll_check_mul(80.0, "chip") - 1.0) < 1e-9
    assert is_checking_club(110.0, "full") and is_checking_club(80.0, "pitch")
    assert is_checking_club(65.0, "flop")
    assert not is_checking_club(160.0, "full")
    assert not is_checking_club(80.0, "chip")

    # Chip on Green still uses putt stimp.
    assert abs(landing_roll_decel_px("Green", "chip", 80.0) - putt_decel_px()) < 1e-9
    assert abs(landing_roll_decel_px("Green", "putt", 25.0) - putt_decel_px()) < 1e-9
    # Approach on Green is fairway-class × check, not putt friction.
    pw_green = landing_roll_decel_px("Green", "full", 110.0)
    assert pw_green > putt_decel_px() * 8.0, (pw_green, putt_decel_px())
    assert abs(pw_green - roll_decel_px("Fairway") * roll_check_mul(110.0, "full")) < 1e-9

    # Bounce speed from current lie matches remaining plan (flat).
    remain_px = pw_roll * 99.0 * PX_PER_YARD
    v = math.sqrt(2.0 * pw_green * remain_px)
    rest = v * v / (2.0 * pw_green)
    assert abs(rest - remain_px) < 1e-6, (rest, remain_px)

    # Old skate: fairway-hot speed + putt decel overshoots remain by a lot.
    v_hot = math.sqrt(2.0 * roll_decel_px("Fairway") * remain_px)
    skate = v_hot * v_hot / (2.0 * putt_decel_px())
    assert skate > remain_px * 3.0, (skate, remain_px)

    print(
        "rollout_check: ok "
        f"driver_roll={dr_roll:.3f} pw_roll={pw_roll:.3f} 7i_roll={i7_roll:.3f} "
        f"spinback={SPINBACK_FT:.0f}ft skate={skate / PX_PER_YARD:.1f}yd vs remain={remain_px / PX_PER_YARD:.1f}yd"
    )


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Club identity: per-category air fraction + spin grip + short-game rollout."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")


def _f(pattern: str) -> float:
    m = re.search(pattern, PHYS)
    assert m, f"missing: {pattern}"
    return float(m.group(1))


CARRY_FRAC_LONG = _f(r"const CARRY_FRAC_LONG\s*:=\s*([0-9.]+)")
CARRY_FRAC_SHORT = _f(r"const CARRY_FRAC_SHORT\s*:=\s*([0-9.]+)")
PUNCH_AIR_FRAC_SCALE = _f(r"const PUNCH_AIR_FRAC_SCALE\s*:=\s*([0-9.]+)")
_pitch_m = re.search(r'shot_type == "pitch":[\s\S]*?return ([0-9.]+)', PHYS)
assert _pitch_m, "pitch absolute air frac not found"
PITCH_AIR_FRAC = float(_pitch_m.group(1))
_punch_clamp_m = re.search(
    r'shot_type == "punch":[\s\S]*?clampf\(full \* PUNCH_AIR_FRAC_SCALE,\s*([0-9.]+),\s*([0-9.]+)\)',
    PHYS,
)
assert _punch_clamp_m, "punch clamp not found"
PUNCH_CLAMP_LO, PUNCH_CLAMP_HI = float(_punch_clamp_m.group(1)), float(_punch_clamp_m.group(2))


def air_distance_fraction(club_max_yards: float, shot_type: str = "full") -> float:
    full = _air_fraction_full(club_max_yards)
    if shot_type == "chip":
        t = max(0.0, min(1.0, (club_max_yards - 85.0) / 50.0))
        return max(0.20, min(0.33, 0.28 + (0.22 - 0.28) * t))
    if shot_type == "pitch":
        return PITCH_AIR_FRAC
    if shot_type == "flop":
        return max(0.92, min(0.98, 0.94 + (0.97 - 0.94) * max(0.0, min(1.0, (110.0 - club_max_yards) / 40.0))))
    if shot_type == "punch":
        return max(PUNCH_CLAMP_LO, min(PUNCH_CLAMP_HI, full * PUNCH_AIR_FRAC_SCALE))
    return full


def _air_fraction_full(club_max_yards: float) -> float:
    t = max(0.0, min(1.0, (club_max_yards - 65.0) / (260.0 - 65.0)))
    return CARRY_FRAC_SHORT + (CARRY_FRAC_LONG - CARRY_FRAC_SHORT) * t


def spin_grip_mul(club_max_yards: float) -> float:
    if club_max_yards >= 245.0:
        return 0.78
    if club_max_yards >= 180.0:
        return 0.88
    if club_max_yards >= 150.0:
        return 1.0
    if club_max_yards >= 120.0:
        return 1.10
    if club_max_yards >= 95.0:
        return 1.15
    if club_max_yards >= 75.0:
        return 1.18
    return 1.22


def main() -> None:
    assert "static func air_distance_fraction" in PHYS
    assert "static func spin_grip_mul" in PHYS
    assert "static func solve_committed_power" in PHYS
    assert "air_distance_fraction(club_max_yards" in PHYS
    assert "spin_grip_mul(club_max_yards)" in PHYS
    assert 'shot_type: String = "full"' in PHYS or "shot_type: String = \"full\"" in PHYS
    # Distance owner also declares is_putt — join from first split so launch body is included.
    _is_putt = 'var is_putt := lie == "Green"'
    full = _is_putt.join(PHYS.split(_is_putt)[1:])
    assert "air_distance_fraction(club_max_yards, shot_type)" in full
    assert "resolve_distance(" in PHYS
    assert "CARRY_FRAC_LONG" in PHYS and "CARRY_FRAC_SHORT" in PHYS
    assert "AIR_DISTANCE_FRACTION" not in PHYS

    samples = [260, 235, 210, 190, 175, 160, 145, 130, 110, 85]
    airs = [air_distance_fraction(y) for y in samples]
    grips = [spin_grip_mul(y) for y in samples]
    for a, b in zip(airs, airs[1:]):
        assert a <= b + 1e-9, (a, b)
    # Mild identity: driver freer than mid; not 2× wedge vs driver.
    assert spin_grip_mul(260) == 0.78
    assert spin_grip_mul(85) >= spin_grip_mul(160) >= spin_grip_mul(260)
    assert spin_grip_mul(85) / spin_grip_mul(260) < 1.6

    assert abs(air_distance_fraction(260) - CARRY_FRAC_LONG) < 1e-9
    assert abs(air_distance_fraction(65) - CARRY_FRAC_SHORT) < 1e-9
    mid = air_distance_fraction(160)
    assert CARRY_FRAC_LONG < mid < CARRY_FRAC_SHORT

    # Chip: mostly roll (~20–33% air); pitch more carry; flop near-zero roll.
    assert air_distance_fraction(80, "chip") < air_distance_fraction(80, "pitch")
    assert air_distance_fraction(80, "pitch") < air_distance_fraction(80, "full")
    assert 0.20 <= air_distance_fraction(80, "chip") <= 0.33
    assert air_distance_fraction(65, "flop") >= 0.92
    assert air_distance_fraction(65, "flop") > air_distance_fraction(65, "pitch")
    assert "chip" in PHYS and "pitch" in PHYS
    assert "flop" in PHYS
    assert "FLOP_MAX_YD" in PHYS
    assert "Lob Wedge" in PHYS
    # Short-shot line damp + hang cap (LW pitch plan 13 / actual 6 playtest).
    assert "static func short_shot_line_scale" in PHYS
    assert "short_shot_line_scale(total_yards)" in PHYS
    assert "short_shot_hang_scale" in PHYS
    assert "total_yards / 55.0" in PHYS or "/ 55.0" in PHYS
    BALL = (ROOT / "scripts" / "ball" / "ball.gd").read_text(encoding="utf-8")
    assert "spin_scale" in BALL and "along_spd" in BALL
    # Speed-preserving curve — spin must not bleed airspeed on soft pitches.
    assert "normalized() * spd" in BALL
    assert "path_len" in BALL

    samples_w = [260, 235, 210, 190, 175, 160, 145, 130, 110, 95, 80, 65]
    airs = [air_distance_fraction(y) for y in samples_w]
    grips = [spin_grip_mul(y) for y in samples_w]
    print(
        "club_identity_check: ok "
        f"driver_air={airs[0]:.3f} mid_air={air_distance_fraction(160):.3f} wedge_air={airs[-1]:.3f} "
        f"wedge_chip={air_distance_fraction(80, 'chip'):.2f} "
        f"wedge_grip={grips[-1]} grip_ratio={grips[-1] / grips[0]:.2f}"
    )


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

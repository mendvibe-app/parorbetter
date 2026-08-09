#!/usr/bin/env python3
"""Club identity: per-category air fraction + spin grip + short-game rollout."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")


def air_distance_fraction(club_max_yards: float, shot_type: str = "full") -> float:
    full = _air_fraction_full(club_max_yards)
    if shot_type == "chip":
        t = max(0.0, min(1.0, (club_max_yards - 85.0) / 50.0))
        return max(0.20, min(0.33, 0.28 + (0.22 - 0.28) * t))
    if shot_type == "pitch":
        v = full + (0.72 - full) * 0.55
        return max(0.68, min(0.82, v))
    if shot_type == "flop":
        return max(0.92, min(0.98, 0.94 + (0.97 - 0.94) * max(0.0, min(1.0, (110.0 - club_max_yards) / 40.0))))
    return full


def _air_fraction_full(club_max_yards: float) -> float:
    if club_max_yards >= 245.0:
        return 0.68
    if club_max_yards >= 180.0:
        return 0.72
    if club_max_yards >= 150.0:
        return 0.78
    if club_max_yards >= 120.0:
        return 0.84
    if club_max_yards >= 95.0:
        return 0.90
    return 0.94


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
    return 1.20


def main() -> None:
    assert "static func air_distance_fraction" in PHYS
    assert "static func spin_grip_mul" in PHYS
    assert "static func solve_committed_power" in PHYS
    assert "air_distance_fraction(club_max_yards" in PHYS
    assert "spin_grip_mul(club_max_yards)" in PHYS
    assert 'shot_type: String = "full"' in PHYS or "shot_type: String = \"full\"" in PHYS
    full = PHYS.split('var is_putt := lie == "Green"')[1]
    assert "air_distance_fraction(club_max_yards, shot_type)" in full

    samples = [260, 235, 210, 190, 175, 160, 145, 130, 110, 85]
    airs = [air_distance_fraction(y) for y in samples]
    grips = [spin_grip_mul(y) for y in samples]
    for a, b in zip(airs, airs[1:]):
        assert a <= b + 1e-9, (a, b)
    # Mild identity: driver freer than mid; not 2× wedge vs driver.
    assert spin_grip_mul(260) == 0.78
    assert spin_grip_mul(85) >= spin_grip_mul(160) >= spin_grip_mul(260)
    assert spin_grip_mul(85) / spin_grip_mul(260) < 1.6

    assert air_distance_fraction(260) == 0.68
    assert air_distance_fraction(160) == 0.78
    assert air_distance_fraction(85) == 0.94

    # Chip: mostly roll (~20–33% air); pitch more carry; flop near-zero roll.
    assert air_distance_fraction(85, "chip") < air_distance_fraction(85, "pitch")
    assert air_distance_fraction(85, "pitch") < air_distance_fraction(85, "full")
    assert 0.20 <= air_distance_fraction(85, "chip") <= 0.33
    assert air_distance_fraction(85, "flop") >= 0.92
    assert air_distance_fraction(85, "flop") > air_distance_fraction(85, "pitch")
    assert "chip" in PHYS and "pitch" in PHYS
    assert "flop" in PHYS
    assert "FLOP_MAX_YD" in PHYS
    # Short-shot line damp — greenside path+1 must not reverse a 3 yd pitch.
    assert "static func short_shot_line_scale" in PHYS
    assert "short_shot_line_scale(total_yards)" in PHYS
    assert "clampf(total_yards / 40.0, 0.12, 1.0)" in PHYS or "total_yards / 40.0" in PHYS
    BALL = (ROOT / "scripts" / "ball" / "ball.gd").read_text(encoding="utf-8")
    assert "spin_scale" in BALL and "along_spd" in BALL

    print(
        "club_identity_check: ok "
        f"driver_air={airs[0]} mid_air={air_distance_fraction(160)} wedge_air={airs[-1]} "
        f"wedge_chip={air_distance_fraction(85, 'chip'):.2f} "
        f"wedge_grip={grips[-1]} grip_ratio={grips[-1] / grips[0]:.2f}"
    )


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

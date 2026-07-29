#!/usr/bin/env python3
"""Club identity: per-category air fraction + spin grip (Phase 1)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")


def air_distance_fraction(club_max_yards: float) -> float:
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
        return 0.75
    if club_max_yards >= 180.0:
        return 0.85
    if club_max_yards >= 150.0:
        return 1.0
    if club_max_yards >= 120.0:
        return 1.15
    if club_max_yards >= 95.0:
        return 1.35
    return 1.5


def main() -> None:
    assert "static func air_distance_fraction" in PHYS
    assert "static func spin_grip_mul" in PHYS
    assert "static func solve_committed_power" in PHYS
    assert "air_distance_fraction(club_max_yards)" in PHYS
    assert "spin_grip_mul(club_max_yards)" in PHYS
    # Full-shot path must not use bare global constant alone.
    launch = PHYS.split("static func launch_velocity")[1].split("return {")[1]
    # After putt early-return, full path uses helper
    full = PHYS.split('var is_putt := lie == "Green"')[1]
    assert "air_distance_fraction(club_max_yards)" in full
    assert re.search(r"var air_frac := AIR_DISTANCE_FRACTION\n", full) is None

    # Same buckets as lateral_spread (245/180/150/120/95).
    samples = [260, 235, 210, 190, 175, 160, 145, 130, 110, 85]
    airs = [air_distance_fraction(y) for y in samples]
    grips = [spin_grip_mul(y) for y in samples]
    # Longer club → more roll (lower air) — monotonic non-increasing along bag order.
    for a, b in zip(airs, airs[1:]):
        assert a <= b + 1e-9, (a, b)
    # Wedge grips more than mid than driver.
    assert spin_grip_mul(85) > spin_grip_mul(160) > spin_grip_mul(260)

    assert air_distance_fraction(260) == 0.68
    assert air_distance_fraction(160) == 0.78
    assert air_distance_fraction(85) == 0.94

    print(
        "club_identity_check: ok "
        f"driver_air={airs[0]} mid_air={air_distance_fraction(160)} wedge_air={airs[-1]} "
        f"wedge_grip={grips[-1]}"
    )


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

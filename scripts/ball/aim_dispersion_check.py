#!/usr/bin/env python3
"""Landing-area dispersion scales with club, not a fixed circle for every shot."""

from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
BP = DIR.joinpath("ball_physics.gd").read_text(encoding="utf-8")
GS = DIR.parent.joinpath("autoload/game_state.gd").read_text(encoding="utf-8")
HOLE = DIR.parent.joinpath("course/hole_controller.gd").read_text(encoding="utf-8")


def lateral_spread_range_yards(club_max_yards: float) -> tuple[float, float]:
    """Mirrors BallPhysics.lateral_spread_range_yards."""
    if club_max_yards >= 245.0:
        return (40.0, 60.0)
    if club_max_yards >= 180.0:
        return (25.0, 45.0)
    if club_max_yards >= 150.0:
        return (18.0, 35.0)
    if club_max_yards >= 120.0:
        return (12.0, 25.0)
    if club_max_yards >= 95.0:
        return (10.0, 18.0)
    return (8.0, 18.0)


def main() -> int:
    assert "static func lateral_spread_range_yards(club_max_yards: float) -> Vector2:" in BP
    assert "Vector2(40.0, 60.0)" in BP  # Driver
    assert "Vector2(25.0, 45.0)" in BP  # 3-Wood / Hybrid / long irons
    assert "Vector2(18.0, 35.0)" in BP  # Mid irons
    assert "Vector2(12.0, 25.0)" in BP  # Short irons
    assert "Vector2(10.0, 18.0)" in BP  # Pitching Wedge
    assert "Vector2(8.0, 18.0)" in BP  # Gap / Sand / Lob wedges

    # Every bag club must land in the category real-world data puts it in — parse the
    # actual BAG so this stays correct if club distances are retuned later.
    bag = [(m.group(1), float(m.group(2)))
           for m in re.finditer(r'"name":\s*"([^"]+)",\s*"max_yards":\s*([\d.]+)', BP)]
    assert len(bag) == 10, f"expected 10 bag clubs, found {len(bag)}"
    expected = {
        "Driver": (40.0, 60.0),
        "3-Wood": (25.0, 45.0),
        "Hybrid": (25.0, 45.0),
        "5-Iron": (25.0, 45.0),
        "6-Iron": (18.0, 35.0),
        "7-Iron": (18.0, 35.0),
        "8-Iron": (12.0, 25.0),
        "9-Iron": (12.0, 25.0),
        "Pitching Wedge": (10.0, 18.0),
        "Gap/Sand Wedge": (8.0, 18.0),
    }
    for name, max_yards in bag:
        got = lateral_spread_range_yards(max_yards)
        assert got == expected[name], f"{name} ({max_yards} yd): got {got}, want {expected[name]}"

    # Monotonic: dispersion never widens as clubs get shorter.
    spreads = [lateral_spread_range_yards(y) for _, y in bag]
    for i in range(len(spreads) - 1):
        assert spreads[i][1] >= spreads[i + 1][1], "high end must not widen for a shorter club"

    # get_aim_radius_yards now derives non-putt radius from the club, not a fixed constant.
    assert "AIM_RADIUS_WEAK_YD" not in GS
    assert "AIM_RADIUS_MID_YD" not in GS
    assert "AIM_RADIUS_PRO_YD" not in GS
    assert "func get_aim_radius_yards(on_green: bool = false, club_max_yards: float = 0.0) -> float:" in GS
    assert "BallPhysics.lateral_spread_range_yards(club_max_yards)" in GS
    # Putting is a separate mechanic (green-read, not carry dispersion) — untouched.
    assert "PUTT_RADIUS_WEAK_YD" in GS and "PUTT_RADIUS_PRO_YD" in GS

    # Both non-putt call sites must thread the chosen club's max_yards through.
    assert "get_aim_radius_yards(false, club_max)" in HOLE
    assert 'get_aim_radius_yards(lie == "Green", club_max)' in HOLE

    print("aim_dispersion_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

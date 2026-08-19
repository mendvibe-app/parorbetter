#!/usr/bin/env python3
"""Landing-area dispersion: full swing by club; short game by rest yards × shot type."""

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


def short_game_aim_radius_yards(planned_rest_yd: float, shot_type: str) -> float:
    """Mirrors BallPhysics.short_game_aim_radius_yards (base, pre-form)."""
    d_near, d_far, r_near, r_far = 5.0, 20.0, 0.67, 1.33
    if shot_type == "pitch":
        d_near, d_far, r_near, r_far = 20.0, 50.0, 1.67, 3.33
    elif shot_type == "flop":
        d_near, d_far, r_near, r_far = 10.0, 30.0, 2.0, 4.0
    t = 0.0
    if d_far > d_near:
        t = max(0.0, min(1.0, (planned_rest_yd - d_near) / (d_far - d_near)))
    return r_near + (r_far - r_near) * t


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
    assert len(bag) == 12, f"expected 12 bag clubs, found {len(bag)}"
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
        "Gap Wedge": (10.0, 18.0),
        "Sand Wedge": (8.0, 18.0),
        "Lob Wedge": (8.0, 18.0),
    }
    for name, max_yards in bag:
        got = lateral_spread_range_yards(max_yards)
        assert got == expected[name], f"{name} ({max_yards} yd): got {got}, want {expected[name]}"

    # Monotonic: dispersion never widens as clubs get shorter.
    spreads = [lateral_spread_range_yards(y) for _, y in bag]
    for i in range(len(spreads) - 1):
        assert spreads[i][1] >= spreads[i + 1][1], "high end must not widen for a shorter club"

    # get_aim_radius_yards: full path from club; short path from rest + shot type.
    assert "AIM_RADIUS_WEAK_YD" not in GS
    assert "AIM_RADIUS_MID_YD" not in GS
    assert "AIM_RADIUS_PRO_YD" not in GS
    assert "func get_aim_radius_yards(" in GS
    assert "club_max_yards" in GS
    assert "BallPhysics.lateral_spread_range_yards(club_max_yards)" in GS
    assert "short_game_aim_radius_yards" in BP
    assert "short_game_aim_radius_yards" in GS
    assert "planned_rest_yd" in GS
    assert 'shot_type == "chip"' in GS or "shot_type == \"chip\"" in GS
    # Putting is a separate mechanic (green-read, not carry dispersion) — untouched.
    assert "PUTT_RADIUS_WEAK_YD" in GS and "PUTT_RADIUS_PRO_YD" in GS

    # Aim radius threads club max + rest/shot type; force widens forced clubs.
    assert "club_max" in HOLE and "get_aim_radius_yards" in HOLE
    assert "_aim_radius_for_club" in HOLE
    assert "rest_yd" in HOLE.split("func _refresh_aim_visuals")[1].split("func ")[0]
    assert "radius_px * 0.92" in HOLE  # land ring capped under yellow

    # Short-game bands: chip ≪ wedge floor; flop > pitch > chip; grows with rest.
    chip_short = short_game_aim_radius_yards(7.0, "chip")  # ~21 ft rest
    chip_long = short_game_aim_radius_yards(18.0, "chip")
    pitch_20 = short_game_aim_radius_yards(20.0, "pitch")
    pitch_40 = short_game_aim_radius_yards(40.0, "pitch")
    flop_20 = short_game_aim_radius_yards(20.0, "flop")
    assert 0.6 <= chip_short <= 1.5, chip_short  # ~2–4.5 ft
    assert chip_long > chip_short
    assert pitch_40 > pitch_20
    assert flop_20 > pitch_20 > short_game_aim_radius_yards(20.0, "chip")
    # Must not inherit LW full-swing half-width floor (4 yd).
    assert chip_short < 2.0, chip_short
    wedge_pro_radius = lateral_spread_range_yards(65.0)[0] * 0.5
    assert chip_short < wedge_pro_radius * 0.5, (chip_short, wedge_pro_radius)

    print("aim_dispersion_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

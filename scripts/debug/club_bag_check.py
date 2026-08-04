#!/usr/bin/env python3
"""Runnable check for bag overlap, suggestion, and force-factor. No Godot required."""

BAG = [
    ("Driver", 260.0),
    ("3-Wood", 235.0),
    ("Hybrid", 210.0),
    ("5-Iron", 190.0),
    ("6-Iron", 175.0),
    ("7-Iron", 160.0),
    ("8-Iron", 145.0),
    ("9-Iron", 130.0),
    ("Pitching Wedge", 110.0),
    ("Gap/Sand Wedge", 85.0),
]

POWER_POCKET_LO = 0.60
POWER_POCKET_HI = 0.92


def shot_need(remaining: float, lie: str) -> float:
    return remaining * (1.2 if lie == "Rough" else 1.08)


def clubs_for_lie(lie: str):
    if lie == "Green":
        return []
    if lie == "Sand":
        return [c for c in BAG if "Wedge" in c[0]]
    if lie != "Tee":
        return [c for c in BAG if c[0] != "Driver"]
    return list(BAG)


PUTTER_MAX_YD = 40.0


def pick_club(remaining: float, lie: str):
    if lie == "Green":
        return ("Putter", PUTTER_MAX_YD)
    need = shot_need(remaining, lie)
    available = clubs_for_lie(lie)
    for name, mx in reversed(available):
        if need <= mx:
            return (name, mx)
    return available[0]


def suggest_clubs(remaining: float, lie: str, count: int = 3):
    available = clubs_for_lie(lie)
    if not available or count <= 0:
        return []
    picked = pick_club(remaining, lie)
    idx = next(i for i, c in enumerate(available) if c[0] == picked[0])
    window = min(count, len(available))
    half = window >> 1
    start = max(0, min(idx - half, len(available) - window))
    return available[start : start + window]


def force_factor(power: float, club_max: float = 0.0, lie: str = "") -> float:
    p = max(0.0, min(1.0, power))
    if p > POWER_POCKET_HI:
        return min(1.0, (p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI))
    if p < POWER_POCKET_LO:
        if club_max > 0.0 and lie:
            available = clubs_for_lie(lie)
            if available and club_max <= available[-1][1] + 0.5:
                return 0.0
        return min(1.0, (POWER_POCKET_LO - p) / POWER_POCKET_LO)
    return 0.0


def main() -> None:
    for (a, ma), (b, mb) in zip(BAG, BAG[1:]):
        gap = ma - mb
        assert 15.0 <= gap <= 30.0, f"{a}/{b} gap {gap} — want ~15–25 yd neighbor steps"

    assert all(BAG[i][1] > BAG[i + 1][1] for i in range(len(BAG) - 1))

    assert pick_club(10, "Green") == ("Putter", PUTTER_MAX_YD)
    assert pick_club(3, "Green") == ("Putter", PUTTER_MAX_YD)
    assert pick_club(40, "Green") == ("Putter", PUTTER_MAX_YD)
    assert all("Wedge" in n for n, _ in clubs_for_lie("Sand"))
    assert clubs_for_lie("Tee")[0][0] == "Driver"
    assert all(n != "Driver" for n, _ in clubs_for_lie("Fairway"))
    assert all(n != "Driver" for n, _ in clubs_for_lie("Rough"))

    # 150 yd fairway → need 162 → 6-Iron (175)
    assert pick_club(150, "Fairway") == ("6-Iron", 175.0)
    # 140 yd → need 151.2 → 7-Iron
    assert pick_club(140, "Fairway") == ("7-Iron", 160.0)
    # 190 yd → need 205.2 → Hybrid (210); 200 yd need 216 → 3-Wood
    assert pick_club(190, "Fairway") == ("Hybrid", 210.0)
    assert pick_club(200, "Fairway") == ("3-Wood", 235.0)
    assert pick_club(40, "Sand") == ("Gap/Sand Wedge", 85.0)

    # Compact trio: neighbors of pick, clamped at ends. Fairway has no Driver.
    assert [n for n, _ in suggest_clubs(150, "Fairway")] == ["5-Iron", "6-Iron", "7-Iron"]
    assert [n for n, _ in suggest_clubs(200, "Fairway")] == ["3-Wood", "Hybrid", "5-Iron"]
    assert [n for n, _ in suggest_clubs(200, "Tee")] == ["Driver", "3-Wood", "Hybrid"]
    assert [n for n, _ in suggest_clubs(40, "Sand")] == ["Pitching Wedge", "Gap/Sand Wedge"]
    assert suggest_clubs(10, "Green") == []

    assert force_factor(0.75) == 0.0
    assert force_factor(0.92) == 0.0
    assert force_factor(1.0) == 1.0
    assert force_factor(0.0) == 1.0
    assert 0.4 < force_factor(0.3) < 0.6
    # Gap is shortest — partial swing is correct short-game, not baby tax
    assert force_factor(0.40, 85.0, "Fairway") == 0.0
    assert force_factor(0.40, 85.0, "Sand") == 0.0
    # PW partial still taxed (should have used Gap)
    assert force_factor(0.40, 110.0, "Fairway") > 0.3
    # Mash on Gap still taxed
    assert force_factor(1.0, 85.0, "Fairway") == 1.0

    # Display order + short labels (coach / tight UI)
    from pathlib import Path

    root = Path(__file__).resolve().parents[1]
    phys = (root / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
    coach = (root / "ui" / "coach_screen.gd").read_text(encoding="utf-8")
    ball = (root / "ball" / "ball.gd").read_text(encoding="utf-8")
    hc = (root / "course" / "hole_controller.gd").read_text(encoding="utf-8")
    assert "func club_short_name" in phys
    assert "func sort_club_names_by_bag" in phys
    assert 'return "3W"' in phys or 'replace("-Wood", "W")' in phys
    assert 'replace("-Iron", "I")' in phys
    assert "sort_club_names_by_bag" in coach
    assert "club_short_name" in coach
    assert "names.sort()" not in coach  # alpha scramble (5-Iron before Driver)
    # Tree apex carry: per-club loft_mul + canopy height-aware collision
    assert "loft_mul" in phys
    assert "func club_loft_mul" in phys
    assert "club_loft_mul(club_max_yards)" in phys
    assert "_height_peak" in ball
    assert 'get_meta("canopy_h"' in ball or 'get_meta("canopy_h",' in ball
    assert "TREE_CANOPY_H" in hc
    assert 'set_meta("canopy_h"' in hc
    # Aim clearance prediction (clean-strike cone tint)
    assert "func estimate_height_peak" in phys
    assert "func estimate_height_at_along" in phys
    assert "func segment_hits_disk" in phys
    assert "_aim_tree_clearance" in hc
    assert "canopy_h" in hc
    assert "_tint_cone_colors" in hc
    # Apex/canopy rebalance: wedges loft higher; tall still hardest canopy.
    assert '"loft_mul": 1.42' in phys or "1.42" in phys  # PW
    assert '"loft_mul": 1.52' in phys or "1.52" in phys  # Gap
    assert "TREE_CANOPY_H" in hc and "42.0" in hc  # tall wall
    # Club-fit: force shortens distance; aim radius can scale with force
    assert "true_power" in (root / "shot" / "shot_result.gd").read_text(encoding="utf-8")
    assert "dist_mul" in phys or "0.88" in phys
    assert "_preserve_aim_line" in hc
    assert "_refit_aim_along_bearing" in hc
    gs = (root / "autoload" / "game_state.gd").read_text(encoding="utf-8")
    assert "force: float" in gs or "force =" in gs.split("func get_aim_radius_yards")[1][:400]
    # Punch-out: low flight under trees
    assert "PUNCH_LOFT_SCALE" in phys
    assert 'shot_type == "punch"' in phys
    assert "_punch_mode" in hc
    assert "_setup_punch_btn" in hc
    sr = (root / "shot" / "shot_routine.gd").read_text(encoding="utf-8")
    assert "punch_mode" in sr
    assert "func flight_shot_type" in sr
    ball_gd = (root / "ball" / "ball.gd").read_text(encoding="utf-8")
    assert "_punch_flight" in ball_gd
    assert "PUNCH_UNDER_CANOPY_FRAC" in ball_gd or "PUNCH_UNDER_CANOPY_FRAC" in phys
    # Shot shape from swing path
    assert "_shape_authority" in sr
    assert "swing_shape" in sr
    assert "max_lateral" in sr
    assert "intended_shape * 0.40" in phys or "intended_shape * 0.4" in phys

    print("club_bag_check: ok")


if __name__ == "__main__":
    main()

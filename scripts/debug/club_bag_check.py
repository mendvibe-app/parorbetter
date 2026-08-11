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
    ("Gap Wedge", 95.0),
    ("Sand Wedge", 80.0),
    ("Lob Wedge", 65.0),
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


def force_factor(
    power: float, club_max: float = 0.0, lie: str = "", shot_type: str = "full"
) -> float:
    p = max(0.0, min(1.0, power))
    if p > POWER_POCKET_HI:
        return min(1.0, (p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI))
    if p < POWER_POCKET_LO:
        # Shortest-club exemption only for pitch/chip/flop — full still taxes.
        uses_full_pocket = shot_type in ("full", "punch", "")
        if club_max > 0.0 and lie and not uses_full_pocket:
            available = clubs_for_lie(lie)
            if available and club_max <= available[-1][1] + 0.5:
                return 0.0
        return min(1.0, (POWER_POCKET_LO - p) / POWER_POCKET_LO)
    return 0.0


def solve_committed_power(
    remaining: float,
    club_max: float,
    lie: str = "Fairway",
    shot_type: str = "full",
) -> dict:
    """Mirror BallPhysics.solve_committed_power pocket floor (no wind)."""
    true_pct = max(0.05, min(1.0, remaining / max(club_max, 1.0)))
    power = true_pct
    overclub = False
    uses_full_pocket = shot_type in ("full", "punch", "")
    if lie != "Green" and true_pct < POWER_POCKET_LO and uses_full_pocket:
        power = POWER_POCKET_LO
        overclub = True
    return {"power": power, "true_pct": true_pct, "overclub": overclub}


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
    assert pick_club(40, "Sand") == ("Lob Wedge", 65.0)

    # Compact trio: neighbors of pick, clamped at ends. Fairway has no Driver.
    assert [n for n, _ in suggest_clubs(150, "Fairway")] == ["5-Iron", "6-Iron", "7-Iron"]
    assert [n for n, _ in suggest_clubs(200, "Fairway")] == ["3-Wood", "Hybrid", "5-Iron"]
    assert [n for n, _ in suggest_clubs(200, "Tee")] == ["Driver", "3-Wood", "Hybrid"]
    assert [n for n, _ in suggest_clubs(40, "Sand")] == ["Gap Wedge", "Sand Wedge", "Lob Wedge"]
    assert suggest_clubs(10, "Green") == []

    assert force_factor(0.75) == 0.0
    assert force_factor(0.92) == 0.0
    assert force_factor(1.0) == 1.0
    assert force_factor(0.0) == 1.0
    assert 0.4 < force_factor(0.3) < 0.6
    # Lob shortest: pitch/chip partials skip baby tax; Full still taxes
    assert force_factor(0.40, 65.0, "Fairway", "pitch") == 0.0
    assert force_factor(0.40, 65.0, "Sand", "chip") == 0.0
    assert force_factor(0.40, 65.0, "Fairway", "full") > 0.3
    # PW partial still taxed (should have used a shorter wedge)
    assert force_factor(0.40, 110.0, "Fairway") > 0.3
    # Mash on Lob still taxed
    assert force_factor(1.0, 65.0, "Fairway") == 1.0

    # Full floors pocket even on shortest club; pitch keeps baby dial
    full_lw = solve_committed_power(25.0, 65.0, "Fairway", "full")
    assert full_lw["overclub"] is True
    assert abs(full_lw["power"] - POWER_POCKET_LO) < 1e-9
    assert full_lw["true_pct"] < POWER_POCKET_LO
    pitch_lw = solve_committed_power(25.0, 65.0, "Fairway", "pitch")
    assert pitch_lw["overclub"] is False
    assert abs(pitch_lw["power"] - pitch_lw["true_pct"]) < 1e-9
    # Driver under-pocket still floors (existing club-fit)
    drv = solve_committed_power(100.0, 260.0, "Tee", "full")
    assert drv["overclub"] is True
    assert abs(drv["power"] - POWER_POCKET_LO) < 1e-9

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
    assert '"loft_mul": 1.62' in phys or "1.62" in phys  # LW highest
    assert "Lob Wedge" in phys and "Sand Wedge" in phys and "Gap Wedge" in phys
    # BAG entries must not keep the merged club (legacy short-name alias may remain).
    assert '{"name": "Gap/Sand Wedge"' not in phys
    assert "TREE_CANOPY_H" in hc and "42.0" in hc  # tall wall
    # Club-fit: force shortens distance; aim radius can scale with force
    assert "true_power" in (root / "shot" / "shot_result.gd").read_text(encoding="utf-8")
    assert "dist_mul" in phys or "0.88" in phys
    assert "_preserve_aim_line" in hc
    assert "_refit_aim_along_bearing" in hc
    # Full owns stock pocket — no shortest-club baby full (shot types dial short)
    assert "shot_type: String = \"full\"" in phys or 'shot_type: String = "full"' in phys
    assert "func shot_type_uses_full_pocket" in phys
    assert "_aim_planned_total_yd" in hc and "_aim_rest_point" in hc
    sr = (root / "shot" / "shot_routine.gd").read_text(encoding="utf-8")
    assert "solve_committed_power(" in sr
    # configure resolves shot_type before power solve
    cfg = sr.split("func configure")[1].split("func ")[0] if "func configure" in sr else sr
    assert cfg.find("shot_type =") < cfg.find("solve_committed_power")
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
    # Swipe-led unified shape (path_error == intended_shape for full family).
    assert "intended_shape * 0.85" in phys
    assert "force * 0.18" not in phys
    assert "transition_pull" in sr

    print("club_bag_check: ok")


if __name__ == "__main__":
    main()

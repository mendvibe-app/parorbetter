#!/usr/bin/env python3
"""Contract checks for Rough lie severity (ball_physics + assets)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts" / "ball" / "ball.gd").read_text(encoding="utf-8")
GS = (ROOT / "scripts" / "autoload" / "game_state.gd").read_text(encoding="utf-8")
UI = ROOT / "assets" / "ui"


def const_float(name: str, src: str = PHYS) -> float:
    m = re.search(rf"const {name}\s*:?=\s*([0-9.]+)", src)
    assert m, f"missing const {name}"
    return float(m.group(1))


def main() -> None:
    assert "rough_severity_enabled" in GS
    assert "var rough_severity_enabled: bool = true" in GS
    assert "_add_rough_severity_row" not in (
        ROOT / "scripts" / "debug" / "debug_controls.gd"
    ).read_text(encoding="utf-8")

    assert const_float("ROUGH_SEV_P_BURIED") == 0.35
    assert const_float("ROUGH_SEV_P_AVERAGE") == 0.80
    assert const_float("ROUGH_MUL_BURIED") == 0.68
    assert const_float("ROUGH_MUL_AVERAGE") == 0.82
    assert const_float("ROUGH_MUL_SITTING") == 0.94
    assert const_float("ROUGH_TIMING_BURIED") == 0.70
    assert const_float("ROUGH_TIMING_AVERAGE") == 0.82
    assert const_float("ROUGH_TIMING_SITTING") == 0.94

    assert "func roll_rough_severity" in PHYS
    assert "severity: String = \"\"" in PHYS
    assert "func lie_multiplier(lie: String, severity: String = \"\")" in PHYS
    assert "func lie_timing_scale(lie: String, severity: String = \"\")" in PHYS
    assert "func recommended_power(" in PHYS
    rp = PHYS.split("func recommended_power")[1][:800]
    assert "severity: String = \"\"" in rp
    assert "launch_dir: Vector2 = Vector2.UP" in rp
    assert "wind.dot(dir)" in rp
    assert "dir.orthogonal()" in rp
    # Range swing passes real bearing; club_percent_today / solve_committed stay on default.
    hole = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")
    assert "bearing.normalized()" in hole
    assert "recommended_power(" in hole

    # Wind yards: dir=UP must match legacy -wy*0.35 + abs(wx)*0.08 exactly.
    def wind_yards(wx: float, wy: float, dx: float, dy: float) -> float:
        ln = (dx * dx + dy * dy) ** 0.5
        dx, dy = dx / ln, dy / ln
        # Godot Vector2.orthogonal() → (-y, x)
        ox, oy = -dy, dx
        head = wx * dx + wy * dy
        cross = abs(wx * ox + wy * oy)
        return head * 0.35 + cross * 0.08

    for wx, wy in ((0.0, -1.0), (1.0, 0.0), (0.6, -0.8), (-0.4, 0.5)):
        legacy = -wy * 0.35 + abs(wx) * 0.08
        assert abs(wind_yards(wx, wy, 0.0, -1.0) - legacy) < 1e-12, (wx, wy, legacy)
    # dir=RIGHT + world -Y wind → pure cross (0.08), zero head (0.35) contribution.
    assert abs(wind_yards(0.0, -1.0, 1.0, 0.0) - 0.08) < 1e-12
    assert abs(wind_yards(0.0, -1.0, 1.0, 0.0) - 0.0 * 0.35 - 1.0 * 0.08) < 1e-12

    # Buried needs more club than average for same remaining (shot_need bump).
    assert "ROUGH_MUL_AVERAGE / ROUGH_MUL_BURIED" in PHYS

    assert "_lie_severity" in BALL
    assert "func get_lie_severity" in BALL
    assert "func _apply_lie_string" in BALL
    assert "roll_rough_severity" in BALL

    # Toggle-off path still names Average constants (no magic 0.82 alone for Rough tiers).
    assert "ROUGH_MUL_AVERAGE" in PHYS

    # Widget art present.
    for name in (
        "lie_widget_fairway.png",
        "lie_widget_rough.png",
        "lie_widget_sand.png",
        "lie_widget_green.png",
        "lie_widget_tee.png",
        "lie_widget_ball.png",
        "lie_widget_tee_peg.png",
    ):
        p = UI / name
        assert p.is_file(), f"missing {p}"

    # Preview lives on the swing pad (top-right), not GlanceRow.
    gesture = (ROOT / "scripts" / "shot" / "tempo_gesture.gd").read_text(encoding="utf-8")
    assert "set_lie_preview" in gesture
    assert "lie_preview" in gesture
    shot = (ROOT / "scripts" / "shot" / "shot_routine.gd").read_text(encoding="utf-8")
    assert "set_lie_preview" in shot
    assert "current_severity" in shot
    assert "_setup_lie_preview" not in shot
    report = (ROOT / "scripts" / "systems" / "shot_report.gd").read_text(encoding="utf-8")
    assert "p_severity" in report
    assert "sitting up" in report

    # recommended_power ordering: lower mul → higher swing % for same yards.
    # Pure math check independent of Godot.
    rem, club = 120.0, 160.0
    for mul_a, mul_b in ((0.68, 0.82), (0.82, 0.94)):
        pa = rem / (club * mul_a)
        pb = rem / (club * mul_b)
        assert pa > pb, f"buried/average power order failed {pa} vs {pb}"

    print("lie_severity_check: OK")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

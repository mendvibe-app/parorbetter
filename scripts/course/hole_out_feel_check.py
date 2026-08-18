#!/usr/bin/env python3
"""Contract: hole-out has ball cup-drop + no in/out zoom punch (TV feel PR1)."""
from __future__ import annotations

from pathlib import Path

HOLE = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")
BALL = Path(__file__).resolve().parents[1].joinpath("ball/ball.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "func play_cup_drop" in BALL
    assert "self_modulate" in BALL.split("func play_cup_drop")[1].split("func ")[0]
    assert "play_cup_drop()" in HOLE
    # Phase 1 lip-in: stash survives reset_at; position cleared on reset.
    assert "_cup_entry_offset" in BALL
    assert "LIP_ORBIT_MAX" in BALL
    assert "visual.position = Vector2.ZERO" in BALL.split("func reset_at")[1].split("func ")[0]
    # Capture geometry frozen — Phase 1 presentation only.
    assert "CUP_CAPTURE_RADIUS := 1.9" in BALL or "CUP_CAPTURE_RADIUS:=1.9" in BALL

    holed = HOLE.split("func _on_holed_out")[1].split("func ")[0]
    # No zoom-punch variables / zoom tweens on the make sequence.
    assert "var close_z" not in holed and "var hold_z" not in holed
    assert 'tween_property(camera, "zoom"' not in holed
    assert "play_putt_drop" in holed
    assert "play_cup_drop" in holed
    assert "global_position" in holed  # still pans to cup
    assert "_show_hole_result_banner" in holed
    # Banner after curl budget (drop_hold), not mid-lip.
    assert "drop_hold" in holed

    assert "func _show_hole_result_banner" in HOLE
    # Practice green: drop, no zoom punch
    prac = HOLE.split("func _on_practice_green_holed")[1].split("func ")[0]
    assert "play_cup_drop" in prac
    assert "Vector2(4.5, 4.5)" not in prac
    assert "cup_drop_total_duration" in prac
    short = HOLE.split("func _on_short_game_holed")[1].split("func ")[0]
    assert "play_cup_drop" in short
    assert "cup_drop_total_duration" in short

    print("hole_out_feel_check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

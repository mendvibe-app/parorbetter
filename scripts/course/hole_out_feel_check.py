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

    holed = HOLE.split("func _on_holed_out")[1].split("func ")[0]
    # No zoom-punch variables / zoom tweens on the make sequence.
    assert "var close_z" not in holed and "var hold_z" not in holed
    assert 'tween_property(camera, "zoom"' not in holed
    assert "play_putt_drop" in holed
    assert "play_cup_drop" in holed
    assert "global_position" in holed  # still pans to cup
    assert "_show_hole_result_banner" in holed

    assert "func _show_hole_result_banner" in HOLE
    # Practice green: drop, no zoom punch
    prac = HOLE.split("func _on_practice_green_holed")[1].split("func ")[0]
    assert "play_cup_drop" in prac
    assert "Vector2(4.5, 4.5)" not in prac

    print("hole_out_feel_check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

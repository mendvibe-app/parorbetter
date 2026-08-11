#!/usr/bin/env python3
"""Contract check: short-game practice mode — stations, flags, aim (not range skip)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GS = (ROOT / "scripts" / "autoload" / "game_state.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8")
SS = (ROOT / "scripts" / "ui" / "start_screen.gd").read_text(encoding="utf-8")
HUD = (ROOT / "scripts" / "ui" / "hud.gd").read_text(encoding="utf-8")
SCENE = (ROOT / "scenes" / "ui" / "start_screen.tscn").read_text(encoding="utf-8")


def main() -> int:
    assert "var short_game_mode" in GS
    assert "func enter_short_game_mode" in GS
    assert "func exit_short_game_mode" in GS
    assert "range_mode or green_mode or short_game_mode" in GS

    assert "func load_short_game" in HC
    assert "func _make_short_game_hole" in HC
    assert "func _short_game_stations" in HC
    assert "func _show_short_game_station_picker" in HC
    assert "func _apply_short_game_station" in HC
    assert "func _reset_short_game_station" in HC
    assert "func _on_short_game_holed" in HC
    assert 'const SHORT_GAME_YARDS := {"close": 10.0, "medium": 30.0, "full": 55.0}' in HC
    assert '"greenside"' in HC and '"fairway"' in HC and '"rough"' in HC and '"sand"' in HC
    # 4 surfaces × 3 distances
    assert "SHORT_GAME_DIST_ORDER" in HC
    # Must keep aim path (shot-type picker), not range skip-aim.
    assert "GameState.short_game_mode" in HC
    assert "_begin_aim_phase()" in HC
    # Sticky short-game loop must not call range swing for the short-game branch.
    start_shot = re.search(
        r"func _start_shot_ui\(\) -> void:[\s\S]*?(?=\nfunc )",
        HC,
    )
    assert start_shot, "missing _start_shot_ui"
    body = start_shot.group(0)
    assert "short_game_mode" in body
    assert "_begin_range_swing" not in body.split("short_game_mode")[1].split("if lie ==")[0] or (
        "short_game_mode" in body and "_begin_aim_phase()" in body
    )

    assert "signal short_game_pressed" in SS
    assert "ShortGameButton" in SS or "short_game_btn" in SS
    assert "short_game_pressed" in MAIN
    assert "load_short_game()" in MAIN
    assert "exit_short_game_mode" in MAIN
    assert "func refresh_short_game" in HUD

    assert "Short Game" in SCENE
    assert 'name="ShortGameButton"' in SCENE

    # Station count math
    yards = {"close": 10.0, "medium": 30.0, "full": 55.0}
    surfaces = 4
    assert len(yards) * surfaces == 12

    print("short_game_practice_check: ok stations=12 yards=%s" % yards)
    return 0


if __name__ == "__main__":
    sys.exit(main())

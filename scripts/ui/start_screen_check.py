#!/usr/bin/env python3
"""Contract check: start screen gates launch; records persist keys + score format."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8")
GS = (ROOT / "scripts" / "autoload" / "game_state.gd").read_text(encoding="utf-8")
SS = (ROOT / "scripts" / "ui" / "start_screen.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")
HUD = (ROOT / "scripts" / "ui" / "hud.gd").read_text(encoding="utf-8")
GO = (ROOT / "scripts" / "ui" / "game_over.gd").read_text(encoding="utf-8")


def format_score_to_par(score: int) -> str:
    """Mirrors GameState.format_score_to_par."""
    if score == 0:
        return "E"
    return f"{score:+d}"


def main() -> int:
    # Launch gated: main must return to start, not auto _start_run in _ready.
    assert "_return_to_start()" in MAIN
    ready = re.search(r"func _ready\(\) -> void:\n((?:.*\n)*?)(?=\nfunc |\Z)", MAIN)
    assert ready, "missing main._ready"
    assert "_start_run(" not in ready.group(1) or "_start_run()" not in ready.group(1).replace(
        "_start_run(false)", ""
    ).replace("_start_run(true)", "")
    # Stricter: no bare auto-start call in ready body
    assert re.search(r"^\s*_start_run\(", ready.group(1), re.M) is None, "main._ready must not auto-start"
    assert "_return_to_start()" in ready.group(1)

    assert "signal start_pressed" in SS
    assert "signal stroke_play_pressed" in SS
    assert "signal green_pressed" in SS
    assert "signal range_pressed" in SS
    assert "func show_screen" in SS
    assert "format_score_to_par" in SS
    assert "Survival" in SS or "stroke_play" in SS

    assert 'RECORDS_PATH := "user://records.cfg"' in GS
    assert "best_score_to_par" in GS
    assert "best_stroke_score_to_par" in GS
    assert "stroke_play_mode" in GS
    assert "func is_stroke_play" in GS
    assert "func apply_hole_result_lives" in GS
    assert "if stroke_play_mode or in_practice():" in GS
    assert "best_deepest_hole" in GS
    assert "has_finished_course" in GS
    assert "func add_score_to_par" in GS
    assert "func format_score_to_par" in GS
    assert "func _load_records" in GS
    assert "func _save_records" in GS
    assert "_update_records_on_end" in GS
    assert "green_mode" in GS
    assert "func in_practice" in GS
    assert "func enter_green_mode" in GS
    assert "func exit_green_mode" in GS

    assert "GameState.add_score_to_par(diff)" in HC
    assert "func _hole_result_feedback" in HC
    assert "is_stroke_play()" in HC
    assert "func load_practice_green" in HC
    assert "GameState.green_mode:" in HC
    assert "func refresh_practice_green" in HUD
    assert "lives_row.visible = GameState.is_survival()" in HUD

    assert "green_pressed.connect(_on_practice_green)" in MAIN
    assert "stroke_play_pressed" in MAIN
    assert "load_practice_green()" in MAIN
    assert "GameState.in_practice()" in MAIN
    assert "reset_run(stroke_play)" in MAIN or "reset_run(p_stroke_play" in GS

    assert "ROUND COMPLETE" in GO
    assert "18 Hole Round" in GO

    assert format_score_to_par(0) == "E"
    assert format_score_to_par(-4) == "-4"
    assert format_score_to_par(2) == "+2"

    assert "if not stroke_play_mode and deepest_hole > best_deepest_hole:" in GS or (
        "not stroke_play_mode" in GS and "best_deepest_hole" in GS
    )
    assert "Survival" in SS
    assert "18 Hole" in SS

    dusk = ROOT / "assets" / "background" / "title_dusk.png"
    assert dusk.is_file(), f"missing {dusk}"
    scene = ROOT / "scenes" / "ui" / "start_screen.tscn"
    assert scene.is_file()
    scene_txt = scene.read_text(encoding="utf-8")
    assert 'name="Buttons" type="VBoxContainer"' in scene_txt
    assert "Survival" in scene_txt
    assert "18 Hole Round" in scene_txt
    assert "Practice Green" in scene_txt
    assert "Practice Range" in scene_txt
    assert 'path="res://scenes/ui/start_screen.tscn"' in (ROOT / "scenes" / "main.tscn").read_text(
        encoding="utf-8"
    )

    print("start_screen_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

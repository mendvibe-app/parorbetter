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
    assert "_start_run()" not in ready.group(1), "main._ready must not auto-start a run"
    assert "_return_to_start()" in ready.group(1)

    assert "signal start_pressed" in SS
    assert "signal green_pressed" in SS
    assert "signal range_pressed" in SS
    assert "func show_screen" in SS
    assert "format_score_to_par" in SS

    assert 'RECORDS_PATH := "user://records.cfg"' in GS
    assert "best_score_to_par" in GS
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
    assert "func load_practice_green" in HC
    assert "func _make_practice_green_hole" in HC
    assert "func _reset_practice_green" in HC
    assert "GameState.green_mode:" in HC  # cup divert in _on_holed_out
    assert "func refresh_practice_green" in HUD

    assert "green_pressed.connect(_on_practice_green)" in MAIN
    assert "load_practice_green()" in MAIN
    assert "GameState.in_practice()" in MAIN

    assert format_score_to_par(0) == "E"
    assert format_score_to_par(-4) == "-4"
    assert format_score_to_par(2) == "+2"

    # Deepest persists on begin_hole (not only end_run); primary falls back to deepest.
    assert "if deepest_hole > best_deepest_hole:" in GS
    assert "_save_records()" in GS
    assert "elif GameState.best_deepest_hole > 0:" in SS
    assert 'score_label.text = str(GameState.best_deepest_hole)' in SS

    dusk = ROOT / "assets" / "background" / "title_dusk.png"
    assert dusk.is_file(), f"missing {dusk}"
    scene = ROOT / "scenes" / "ui" / "start_screen.tscn"
    assert scene.is_file()
    scene_txt = scene.read_text(encoding="utf-8")
    assert 'name="Buttons" type="VBoxContainer"' in scene_txt
    assert "Start Round" in scene_txt
    assert "Practice Green" in scene_txt
    assert "Practice Range" in scene_txt
    assert 'path="res://scenes/ui/start_screen.tscn"' in (ROOT / "scenes" / "main.tscn").read_text(
        encoding="utf-8"
    )

    print("start_screen_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

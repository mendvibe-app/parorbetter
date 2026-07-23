#!/usr/bin/env python3
"""HUD cleanup: scorecard header, wind flag, lie/club icons, no run-on labels."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HUD = (ROOT / "scripts/ui/hud.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
SHOT = (ROOT / "scripts/shot/shot_routine.gd").read_text(encoding="utf-8")
DBG = (ROOT / "scripts/debug/debug_controls.gd").read_text(encoding="utf-8")
FLAG = (ROOT / "scripts/ui/wind_flag.gd").read_text(encoding="utf-8")
ICONS = (ROOT / "scripts/ui/hud_icons.gd").read_text(encoding="utf-8")
CLUB_SEL = (ROOT / "scripts/shot/club_select.gd").read_text(encoding="utf-8")


def main() -> int:
    assert 'HOLE %d · PAR %d · %d YDS' in HUD, "header must show hole · par · yards"
    assert "hole.yardage" in HUD
    assert "form_label()" not in HUD, "form text retired from AdaptLabel"
    assert "get_aim_radius_yards" not in HUD, "○radius text retired from AdaptLabel"
    assert "Strokes %d" in HUD

    assert "form_label()" not in CTRL, "aim feedback must not cram form label"
    assert "○%d yd" not in CTRL and "○%d" not in CTRL, "dispersion radius stays on the circle"
    assert "_show_wind_flag" in CTRL
    assert "WindFlag" in CTRL
    assert "_wind_bias" in CTRL, "aim-circle wind bias arrow"
    assert "WIND_TEXTURES" not in CTRL, "arcade wind arrows retired"
    assert "_wind_sprite" not in CTRL
    assert "No wind adjust needed" not in CTRL
    assert "%s · AIM — drag, Confirm" in CTRL

    assert "Aim %d yd (pin %d)" not in SHOT, "info_label must not be a six-fact run-on"
    assert "HudIcons.lie_texture" in SHOT
    assert "HudIcons.club_texture" in SHOT
    assert "_wind_dir" not in SHOT

    assert "class_name WindFlag" in FLAG
    assert "mph" in FLAG, "tap tip is just the speed"
    assert "wind_aim_hint" not in FLAG, "advice sentence retired; direction reads from lean"
    assert "MAX_LEAN" in FLAG
    assert "pin_flag.png" in FLAG

    assert "lie_tee.png" in ICONS
    assert "club_putter.png" in ICONS
    assert "func lie_texture" in ICONS
    assert "func club_texture" in ICONS

    for name in (
        "lie_tee", "lie_fairway", "lie_rough", "lie_sand", "lie_green",
        "club_driver", "club_wood", "club_hybrid", "club_iron", "club_wedge", "club_putter",
    ):
        assert (ROOT / f"assets/ui/{name}.png").is_file(), name

    assert "HudIcons.club_texture" in CLUB_SEL
    assert "_park_below_hud" in DBG
    assert "HUD_HEIGHT" in DBG
    print("hud_cleanup_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

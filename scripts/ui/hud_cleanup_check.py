#!/usr/bin/env python3
"""HUD cleanup PR1: scorecard header, no form/radius cram, shorter shot strings."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HUD = (ROOT / "scripts/ui/hud.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
SHOT = (ROOT / "scripts/shot/shot_routine.gd").read_text(encoding="utf-8")
DBG = (ROOT / "scripts/debug/debug_controls.gd").read_text(encoding="utf-8")


def main() -> int:
    assert 'HOLE %d · PAR %d · %d YDS' in HUD, "header must show hole · par · yards"
    assert "hole.yardage" in HUD
    assert "form_label()" not in HUD, "form text retired from AdaptLabel"
    assert "get_aim_radius_yards" not in HUD, "○radius text retired from AdaptLabel"
    assert "Strokes %d" in HUD

    assert "form_label()" not in CTRL, "aim feedback must not cram form label"
    assert "○%d yd" not in CTRL and "○%d" not in CTRL, "dispersion radius stays on the circle"
    assert "_show_wind_banner" in CTRL
    assert "No wind adjust needed" not in CTRL
    assert "%s · AIM — drag, Confirm" in CTRL

    assert "Aim %d yd (pin %d)" not in SHOT, "info_label must not be a six-fact run-on"
    assert '"%d yd"' in SHOT
    assert "_wind_dir" not in SHOT

    assert "_park_below_hud" in DBG
    assert "HUD_HEIGHT" in DBG
    print("hud_cleanup_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

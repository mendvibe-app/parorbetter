#!/usr/bin/env python3
"""HUD + course wind flag share paint_flag (mockup plans/wind_direction_speed.png)."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAG = (ROOT / "scripts/ui/wind_flag.gd").read_text(encoding="utf-8")
PIN = (ROOT / "scripts/course/course_pin_flag.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("static func paint_flag" in FLAG, "shared paint_flag")
must("func _draw()" in FLAG or "func _draw() ->" in FLAG, "HUD _draw")
must("paint_flag(self" in FLAG or "paint_flag(self," in FLAG, "HUD uses paint_flag")
must("stream_rotation" not in FLAG, "old weathervane removed")
must("STRENGTH_NORM" in FLAG and "INTO_SCALE_MAX" in FLAG and "DOWN_SCALE_MIN" in FLAG, "strength modes")
must("↑ INTO" not in FLAG and "↓ HELP" not in FLAG, "no axis glyph")

must("class_name CoursePinFlag" in PIN, "course pin class")
# Course pin draws its own screen-scaled stick (paint_flag world floors → white box at putt zoom).
must("POLE_H_SCREEN" in PIN and "POLE_W_SCREEN" in PIN, "pin uses screen-px pole")
must("paint_flag" not in PIN, "course pin no longer uses HUD paint_flag")
must("CoursePinFlagScr" in CTRL or "course_pin_flag.gd" in CTRL, "controller preloads course pin")
must("set_wind" in CTRL, "controller sets wind on pin")
must("stream_rotation" not in CTRL, "controller no longer rotates pin")
must("PIN_FLAG_SCREEN_PX" in CTRL, "course pin screen scale")
must("_park_wind_flag" in CTRL, "wind docked right")
must("PRESET_CENTER_TOP" not in CTRL.split("_wind_flag")[1].split("wind_banner")[0], "wind not center-top")
must("PIN_FLAG_POLE_X" not in CTRL, "texture plant offsets gone")

# Strength monotonicity (mirrors draw math).
STRENGTH_NORM = 40.0
INTO_SCALE_MAX = 1.9
DOWN_SCALE_MIN = 0.22


def into_scale(ay: float) -> float:
    fwd = min(max(abs(ay) / STRENGTH_NORM, 0.0), 1.0)
    return 1.0 + (INTO_SCALE_MAX - 1.0) * fwd


def down_scale(ay: float) -> float:
    fwd = min(max(abs(ay) / STRENGTH_NORM, 0.0), 1.0)
    return 1.0 + (DOWN_SCALE_MIN - 1.0) * fwd


must(into_scale(10) < into_scale(40), "into grows with strength")
must(down_scale(10) > down_scale(40), "downwind shrinks with strength")
must(down_scale(40) >= 0.15, "high down keeps a sliver")

print("wind_flag_check: OK")

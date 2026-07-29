#!/usr/bin/env python3
"""Contract: cart-GPS hole map wired under Debug."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HM = (ROOT / "scripts/ui/hole_map.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("class_name HoleMap" in HM, "HoleMap class")
must("func configure" in HM and "func set_ball" in HM, "configure/set_ball")
must("func park_under_debug" in HM, "park under debug")
must("func _setup_hole_map" in HC and "func _refresh_hole_map" in HC, "controller hooks")
must("_hole_map.set_ball" in HC, "ball tracking")
must("_refresh_hole_map()" in HC, "refresh after build")
print("hole_map_check: OK")

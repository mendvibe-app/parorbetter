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
# Change-club bag sits under map (top-right chrome); icon asset ships with UI.
must("func _park_change_club_btn" in HC, "park bag under map")
must("MAP_H + gap" in HC or "HoleMap.MAP_H" in HC, "below map uses MAP_H")
must("TEX_CLUB_BAG" in HC and "ui_club_bag.png" in HC, "bag icon")
must((ROOT / "assets/ui/ui_club_bag.png").is_file(), "bag png on disk")
must("TextureButton.new()" in HC, "icon button not text label")
print("hole_map_check: OK")

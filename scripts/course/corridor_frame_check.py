#!/usr/bin/env python3
"""Contract: hole presentation uses side belts + corridor camera framing."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("const SIDE_BELT_W" in HC, "SIDE_BELT_W constant")
must("const CORRIDOR_SCREEN_FRAC" in HC, "CORRIDOR_SCREEN_FRAC constant")
must("func _add_side_belts" in HC, "_add_side_belts")
must("func _play_corridor_width" in HC, "_play_corridor_width")
must("_add_side_belts()" in HC, "side belts called from build")
must("CORRIDOR_SCREEN_FRAC" in HC and "view.x * CORRIDOR_SCREEN_FRAC" in HC, "zoom uses corridor frac")
# Trees hug belt, not world-edge picture frame
must("1125.0" not in HC or "strip_x" not in HC, "old edge strip tree coords removed")
must("SIDE_BELT_W" in HC, "side belt width")
must("func _place_tree_group" in HC or "func _add_tree" in HC, "designed tree placement")
# Putt path still separate (must not use corridor-only for putts)
must("_is_putt_context()" in HC, "putt context still branched")
print("corridor_frame_check: OK")

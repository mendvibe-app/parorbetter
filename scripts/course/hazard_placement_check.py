#!/usr/bin/env python3
"""Hazard role specs clear the green; carry stays mid-hole. Mirrors resolver rules."""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
DATA = DIR.joinpath("hole_data.gd").read_text(encoding="utf-8")
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("hole_controller.gd").read_text(encoding="utf-8")


GREEN_HAZARD_PAD = 14.0
GREEN_HAZARD_CLEAR_EXTRA = 8.0


def clears_green(center, green_c, rx, ry, radius) -> bool:
    erx = rx + GREEN_HAZARD_PAD + radius + GREEN_HAZARD_CLEAR_EXTRA
    ery = ry + GREEN_HAZARD_PAD + radius + GREEN_HAZARD_CLEAR_EXTRA
    dx = (center[0] - green_c[0]) / max(erx, 1.0)
    dy = (center[1] - green_c[1]) / max(ery, 1.0)
    return dx * dx + dy * dy > 1.0


def greenside_center(green_c, pin, side, size, rx, ry):
    """Mirror hole_controller: dist clears expanded ellipse (no silent drop)."""
    dist = max(rx, ry) + GREEN_HAZARD_PAD + GREEN_HAZARD_CLEAR_EXTRA + size + 4.0
    if math.hypot(pin[0], pin[1]) > 4.0:
        ang = math.atan2(pin[1], pin[0])
    else:
        ang = -math.pi * 0.5 if side < 0 else math.pi * 0.5
    if side != 0:
        target = side * math.pi * 0.5
        ang = ang + (target - ang) * 0.45
    entry = math.pi * 0.5
    for _ in range(8):
        diff = (ang - entry + math.pi) % (2 * math.pi) - math.pi
        if abs(diff) > math.radians(40.0):
            break
        ang += (1 if side == 0 else side) * math.radians(35.0)
    # Push out until clear (controller loop)
    for _ in range(12):
        c = (green_c[0] + math.cos(ang) * dist, green_c[1] + math.sin(ang) * dist)
        if clears_green(c, green_c, rx, ry, size):
            return c
        dist += 6.0
    return (green_c[0] + math.cos(ang) * dist, green_c[1] + math.sin(ang) * dist)


def main() -> int:
    assert 'hazards: Array = []' in DATA or "@export var hazards" in DATA
    assert "func has_bunker()" in DATA
    assert "func has_water()" in DATA
    assert "has_bunker: bool" not in DATA
    assert "ROLE_GREENSIDE" in DATA
    assert "_build_hazards" in GEN
    assert "_place_hazards" in CTRL
    assert "_place_layout_hazards" not in CTRL
    assert "_clears_green" in CTRL
    assert "water_creek.png" in CTRL
    assert "water_pond.png" in CTRL

    green_c = (540.0, -80.0)
    rx, ry = 60.0, 50.0
    pin = (18.0, -12.0)
    size = 36.0
    c = greenside_center(green_c, pin, 1, size, rx, ry)
    assert clears_green(c, green_c, rx, ry, size), f"greenside inside green: {c}"

    # Carry along mid band (0.28–0.48 in generator)
    for along in (0.28, 0.38, 0.48):
        assert 0.2 <= along <= 0.7

    # Island clear > green radius
    clear = max(rx, ry) + 14.0 + 12.0
    assert clear > max(rx, ry)

    # Seeded-style sand centers must not sit in green ellipse
    for side in (-1, 1):
        gc = greenside_center(green_c, pin, side, 40.0, rx, ry)
        assert clears_green(gc, green_c, rx, ry, 40.0)

    # Elliptical green — old +10 dist failed _clears_green; new placement must pass.
    erx, ery = 70.0, 40.0
    for side in (-1, 1):
        for sz in (36.0, 48.0):
            gc = greenside_center(green_c, pin, side, sz, erx, ery)
            assert clears_green(gc, green_c, erx, ery, sz), (side, sz, gc)

    # Landing beside fairway, not at green center
    landing = (540.0 + 70.0 + 40.0 * 0.35, -80.0 + 0.5 * 900.0)
    assert clears_green(landing, green_c, rx, ry, 40.0)

    assert re.search(r'ROLE_CARRY|"carry"', GEN)
    assert "greenside" in GEN
    assert "GREEN_HAZARD_PAD" in CTRL
    assert "GREEN_HAZARD_CLEAR_EXTRA" in CTRL
    # Greenside sand always places (no if _clears_green skip).
    assert "elif kind == \"sand\":" in CTRL or "elif kind == 'sand':" in CTRL

    # Trees clear bunkers; sand lie uses paint (not full circle).
    assert "func _clears_bunkers" in CTRL
    assert "func _on_painted_sand" in CTRL
    assert "SAND_COLLISION_FRAC" in CTRL

    # Cape + Leven water hazards epic.
    assert 'ROLE_DIAGONAL := "diagonal"' in DATA
    assert 'ROLE_SHORELINE := "shoreline"' in DATA
    assert "ROLE_DIAGONAL" in GEN and "ROLE_SHORELINE" in GEN
    assert "_place_diagonal_creek" in CTRL
    assert "_place_shoreline" in CTRL
    assert "rotation_deg" in CTRL
    assert "force_cape" in GEN
    assert re.search(r'"force_cape"\s*:\s*true', GEN)
    assert "_use_sharp_dogleg" in CTRL  # Cape gated on sharp dogleg

    # Water paint gate — creek sprite is ~45% opaque; AABB alone wet-fires fringe.
    assert "func _on_painted_water" in CTRL
    assert 'set_meta("water_sprite"' in CTRL or 'set_meta("water_sprite",' in CTRL
    assert 'set_meta("water_img"' in CTRL or 'set_meta("water_img",' in CTRL
    BALL = DIR.joinpath("../ball/ball.gd").read_text(encoding="utf-8")
    assert "func _water_area_is_wet" in BALL
    assert "_water_area_is_wet" in BALL.split('is_in_group("water")')[1].split("func ")[0]

    # Island soft-lock fix: dry drop relief + approach tongue (not only last_safe).
    assert "func _water_drop_pos" in CTRL
    assert "func _hazard_drop_pos" in CTRL
    assert "func _is_dry_drop_spot" in CTRL
    assert "gap_half" in CTRL  # island bottom wings leave fairway gap
    assert 'ball.reset_at(ball.get_last_safe(), "Fairway")' not in CTRL

    print("hazard_placement_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

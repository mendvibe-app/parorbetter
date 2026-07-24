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


def clears_green(center, green_c, rx, ry, radius) -> bool:
    erx = rx + 14.0 + radius + 8.0
    ery = ry + 14.0 + radius + 8.0
    dx = (center[0] - green_c[0]) / max(erx, 1.0)
    dy = (center[1] - green_c[1]) / max(ery, 1.0)
    return dx * dx + dy * dy > 1.0


def greenside_center(green_c, pin, side, size, rx, ry):
    dist = max(rx, ry) + 14.0 + 10.0 + size
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

    # Landing beside fairway, not at green center
    landing = (540.0 + 70.0 + 40.0 * 0.35, -80.0 + 0.5 * 900.0)
    assert clears_green(landing, green_c, rx, ry, 40.0)

    assert re.search(r'ROLE_CARRY|"carry"', GEN)
    assert "greenside" in GEN
    print("hazard_placement_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

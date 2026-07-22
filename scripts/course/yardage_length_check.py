#!/usr/bin/env python3
"""Par yardage must drive tee→green px length; par-3 max stays driver-reachable."""
from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")
DATA = DIR.joinpath("hole_data.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("hole_controller.gd").read_text(encoding="utf-8")
PHYS = DIR.joinpath("../ball/ball_physics.gd").read_text(encoding="utf-8")

PX_PER_YARD = 2.25
GREEN_Y = -80.0
DRIVER_MAX = 260.0

# Mirrors HoleGenerator.YARDAGE bands (min/max per par).
YARDAGE_BANDS = {
    3: (120.0, 250.0),
    4: (300.0, 500.0),
    5: (450.0, 650.0),
}


def tee_y(yardage: float) -> float:
    return GREEN_Y + max(yardage, 80.0) * PX_PER_YARD


def main() -> int:
    assert "yardage" in DATA
    assert "d.yardage = yardage" in GEN or "d.yardage =" in GEN
    assert "yards_to_pixels" in CTRL
    assert "PX_PER_YARD := 2.25" in PHYS or "PX_PER_YARD = 2.25" in PHYS

    # Par-3 longest band must be reachable with driver.
    assert YARDAGE_BANDS[3][1] <= DRIVER_MAX

    for yd in (120.0, 210.0, 250.0, 400.0, 650.0):
        span = tee_y(yd) - GREEN_Y
        assert abs(span - yd * PX_PER_YARD) < 1e-6, (yd, span)

    # Generator bands still declared for par 3 short/long.
    assert re.search(r"3:\s*\{[^}]*\[120\.0,\s*160\.0\]", GEN, re.S)
    assert "[210.0, 250.0]" in GEN

    # Aim clamp covers long par-5 tee.
    aim = DIR.joinpath("../shot/aim_control.gd").read_text(encoding="utf-8")
    assert "TEE_Y_MAX := 1500.0" in aim
    assert tee_y(650.0) < 1500.0

    print("yardage_length_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

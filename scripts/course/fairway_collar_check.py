#!/usr/bin/env python3
"""Phase 1 kit: first-cut apron plate; fairway T-junction (no fairway wrap under green)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts/ball/ball.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "func _is_island_green" in HC
    assert "func _green_outer_radii" in HC
    assert "func _collar_arc_points" in HC  # kept for helpers / island paths
    assert "func _add_green_apron" in HC
    assert "_add_green_apron()" in HC
    assert "func _apron_plate_scale" in HC
    assert "GREEN_APRON_SCALE" in HC

    # Phase 1: apron is first-cut tile, not fairway wrap
    apron = HC.split("func _add_green_apron")[1].split("func ")[0]
    assert "TEX_ROUGH" in apron
    assert "TEX_FAIRWAY" not in apron
    assert 'add_to_group("fairway")' not in apron

    # Fairway T-junction — no south collar arc wrap on non-island path
    fw = HC.split("func _add_bent_fairway")[1].split("func ")[0]
    assert "T-junction" in HC or "front_y" in fw
    assert "_collar_arc_points(collar_half)" not in fw
    assert "_is_island_green()" in fw
    assert "half * 0.7" in fw  # island flat tip only

    # First-cut is independent field
    assert "func _first_cut_side_width" in HC
    assert "func _add_first_cut" in HC
    fc = HC.split("func _add_first_cut")[1].split("func ")[0]
    assert "FIRST_CUT_W" not in fc
    assert "TEX_ROUGH" in fc

    # Build order: first-cut + apron before fairway
    build = HC.split("_add_first_cut()")[0]
    # weak order check via later markers
    i_fc = HC.find("_add_first_cut()")
    i_ap = HC.find("_add_green_apron()")
    i_fw = HC.find("_add_bent_fairway(fairway_w)")
    assert 0 <= i_fc < i_ap < i_fw

    assert 'is_in_group("green")' in BALL
    assert 'is_in_group("fairway")' in BALL
    g = BALL.find('is_in_group("green")')
    f = BALL.find('is_in_group("fairway")')
    assert 0 <= g < f, "green group must be checked before fairway"

    print("fairway_collar_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

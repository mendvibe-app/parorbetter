#!/usr/bin/env python3
"""Fairway true collar: continuous approach into non-island greens (no rough moat)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts/ball/ball.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "func _is_island_green" in HC
    assert "func _green_outer_radii" in HC
    assert "func _collar_arc_points" in HC
    assert "COLLAR_UNDERLAP" in HC
    # Seal under green after dark-rough base (≥1.0). Fringe donut retired;
    # green apron ellipse kills rough ring at shoulders (real continuous approach).
    assert "COLLAR_UNDERLAP := 1.04" in HC or "COLLAR_UNDERLAP:=1.04" in HC
    assert "func _add_green_fringe_seal" not in HC
    assert "func _add_green_apron" in HC
    assert "_add_green_apron()" in HC
    assert "GREEN_APRON_SCALE" in HC

    # Collar is the default green-end path; oval/kidney-only gate retired.
    assert 'GreenShape.OVAL or hole.green_shape == HoleData.GreenShape.KIDNEY' not in HC
    assert "not _is_island_green()" in HC
    assert "_collar_arc_points(collar_half)" in HC or "_collar_arc_points(" in HC
    # Wide apron: collar half prefers green outer, not thin 0.7 tongue.
    assert "outer.x" in HC
    assert "collar_half" in HC
    # Green book heat stays on painted surface (not ideal-ellipse bleed into rough).
    assert "GREEN_BOOK_ELLIPSE_FRAC" in HC
    assert "_on_painted_green" in HC.split("func _build_green_book")[1].split("func ")[0]

    # Island still uses apron tongue (water edge), not collar into the ring.
    fw = HC.split("func _add_bent_fairway")[1].split("func ")[0]
    assert "_is_island_green()" in fw
    assert "half * 0.7" in fw  # island flat tip only

    # Legacy apron formula must not be the sole non-island green-end stop.
    # It may remain for island top_y; collared path uses arc, not maxf(...)+6 alone.
    assert "maxf(hole.green_radius_y, 36.0) + 6.0" in HC  # island apron still ok
    assert "Island-only apron" in HC or "island" in fw.lower()

    # Lie: green before fairway when areas overlap under collar.
    assert 'is_in_group("green")' in BALL
    assert 'is_in_group("fairway")' in BALL
    g = BALL.find('is_in_group("green")')
    f = BALL.find('is_in_group("fairway")')
    assert 0 <= g < f, "green group must be checked before fairway"

    print("fairway_collar_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

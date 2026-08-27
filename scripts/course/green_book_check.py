#!/usr/bin/env python3
"""Contract: green book aim camera + yardage-book wash/arrows (not contour grid)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")
PIN = Path(__file__).with_name("course_pin_flag.gd").read_text(encoding="utf-8")


def _const(name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", CTRL)
    assert m, name
    return float(m.group(1))


def main() -> int:
    assert "func _green_book_aim_zoom" in CTRL
    assert "func _build_green_book" in CTRL
    assert "GREEN_BOOK_ZOOM_CAP" in CTRL
    assert "GREEN_BOOK_FIT" in CTRL
    assert "GREEN_BOOK_ZOOM_MAX_PIN_YD" in CTRL
    assert "GREEN_BOOK_SHOW_MAX_PIN_YD" in CTRL
    assert "GREEN_BOOK_TEX_N" in CTRL
    assert _const("GREEN_BOOK_TEX_N") >= 48.0
    assert "TEXTURE_FILTER_LINEAR" in CTRL
    assert "ImageTexture" in CTRL
    # Fall-line arrows (yardage book), not topo contour grid.
    assert "GREEN_BOOK_ARROW_N" in CTRL
    assert "arrows" in CTRL
    assert "green_slope_at" in CTRL
    assert "GREEN_BOOK_CONTOUR" not in CTRL or "CONTOUR_LEVELS" not in CTRL
    assert "Cool = low" in CTRL and "Warm = high" in CTRL
    assert "Arrows = downhill" in CTRL

    show_fn = CTRL.split("func _should_show_green_book")[1].split("func _is_putt_context")[0]
    assert "aim_target" not in show_fn and "apron" not in show_fn

    # Pin: screen-scaled, flag at tip.
    assert "POLE_H_SCREEN" in PIN
    assert "FLAG_TIP_INSET_SCREEN" in PIN
    assert "-pole_h + inset" in PIN

    print(f"green_book_check: ok arrows wash show_max_yd={_const('GREEN_BOOK_SHOW_MAX_PIN_YD'):.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

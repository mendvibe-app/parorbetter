#!/usr/bin/env python3
"""Contract: green book aim camera fits the green (not true-scale putt postage stamp)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")


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
    assert "_green_book_aim_zoom" in CTRL
    assert "GREEN_BOOK_ZOOM_MAX_PIN_YD" in CTRL
    # Far aim-on-pin must not open the book.
    show_fn = CTRL.split("func _should_show_green_book")[1].split("func _is_putt_context")[0]
    assert "aim_target" not in show_fn and "apron" not in show_fn
    assert "GREEN_BOOK_SHOW_MAX_PIN_YD" in show_fn

    assert "GREEN_BOOK_LOOK_BALL" in CTRL

    book_cap = _const("GREEN_BOOK_ZOOM_CAP")
    putt_cap = _const("PUTT_ZOOM_CAP")
    assert book_cap < putt_cap * 0.45, (book_cap, putt_cap)
    assert book_cap <= 45.0, book_cap
    assert _const("GREEN_BOOK_SHOW_MAX_PIN_YD") <= 90.0
    assert _const("GREEN_BOOK_ZOOM_MAX_PIN_YD") <= 100.0

    view_min = 1080.0
    fit = _const("GREEN_BOOK_FIT")
    frac = _const("GREEN_BOOK_VIEW_FRAC")
    floor = _const("GREEN_BOOK_ZOOM_FLOOR")
    half = 40.0 * fit
    z_book = min(max(view_min * frac / half, floor), book_cap)
    assert z_book <= book_cap + 0.01
    assert z_book < 50.0, z_book

    print(f"green_book_check: ok book_cap={book_cap:.0f} show_max_yd={_const('GREEN_BOOK_SHOW_MAX_PIN_YD'):.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

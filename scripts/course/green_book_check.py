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
    assert _const("GREEN_BOOK_ARROW_MIN_SLOPE") == 0.01
    assert _const("GREEN_BOOK_WASH_HALF_FT") == 2.0
    assert _const("GREEN_BOOK_ARROW_MAG_K") == 14.0
    assert _const("PUTT_FALL_ARROW_SCREEN") == 40.0
    assert _const("PUTT_FALL_MIN_SLOPE") == 0.005
    assert "func _refresh_putt_fall_lines" in CTRL
    assert "func _putt_path_break_mag" in CTRL
    assert "_putt_path_break_mag()" in CTRL.split("func _is_tap_in")[1].split("func ")[0]
    build = CTRL.split("func _build_green_book")[1].split("func ")[0]
    assert "GREEN_BOOK_WASH_HALF_FT" in build
    assert "_putt_fall" in build
    assert "h_span" not in build  # per-green min–max stretch is gone
    assert "GREEN_BOOK_CONTOUR" not in CTRL or "CONTOUR_LEVELS" not in CTRL
    assert "Cool = low" in CTRL and "Warm = high" in CTRL
    assert "Arrows = downhill" in CTRL

    show_fn = CTRL.split("func _should_show_green_book")[1].split("func _is_putt_context")[0]
    assert "aim_target" not in show_fn and "apron" not in show_fn
    # Phase 3: flag on green only during aim. Book zoom = green ∪ ball (chips + address).
    assert _const("GREEN_BOOK_ZOOM_CAP") < _const("PUTT_ZOOM_CAP")
    assert "GREEN_BOOK_LOOK_BALL" not in CTRL
    assert "func _green_book_frame_rect" in CTRL
    assert "func _green_book_aim_look" in CTRL
    assert "func _greenside_book_frame" in CTRL
    assert "GREEN_BOOK_BALL_PAD" in CTRL
    zoom_fn = CTRL.split("func _desired_camera_zoom")[1].split("func ")[0]
    assert "_green_book_aim_zoom" in zoom_fn
    assert "_greenside_book_frame" in zoom_fn
    assert "_putt_frame_zoom" in zoom_fn
    look_fn = CTRL.split("func _desired_camera_look")[1].split("func ")[0]
    assert "_green_book_aim_look" in look_fn or "_greenside_book_frame" in look_fn
    frame_fn = CTRL.split("func _green_book_frame_rect")[1].split("func ")[0]
    assert "ball.global_position" in frame_fn
    sync = CTRL.split("func _sync_pin_flag_visible")[1].split("func ")[0]
    assert "_pin_flag.visible = _aiming and not hole_complete" in sync
    # Short-game follow softens driver punch / look lead.
    assert "FLIGHT_LAND_FRAC_SHORT" in CTRL
    assert "FLIGHT_LOOK_LEAD_SHORT_MUL" in CTRL
    assert "_flight_short_game" in CTRL
    assert "is_short_game_shot" in CTRL.split("func _follow_ball")[1].split("func ")[0]

    # Pin: screen-scaled, flag at tip.
    assert "POLE_H_SCREEN" in PIN
    assert "FLAG_TIP_INSET_SCREEN" in PIN
    assert "-pole_h + inset" in PIN

    print(f"green_book_check: ok arrows wash show_max_yd={_const('GREEN_BOOK_SHOW_MAX_PIN_YD'):.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

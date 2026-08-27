#!/usr/bin/env python3
"""True-scale ball everywhere; putt camera only on Green; pin height band."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts/ball/ball.gd").read_text(encoding="utf-8")


def _const(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def main() -> int:
    putt_ctx = CTRL.split("func _is_putt_context")[1].split("func ")[0]
    assert 'get_lie() == "Green"' in putt_ctx or "get_lie() == 'Green'" in putt_ctx
    assert "28.0" not in putt_ctx and "<= 28" not in putt_ctx

    assert "PIN_FLAG_SCREEN_PX" in CTRL
    assert "PIN_FLAG_SCREEN_PX_APPROACH" in CTRL
    assert "PIN_FLAG_H_MIN" in CTRL and "PIN_FLAG_H_MAX" in CTRL
    assert 20.0 <= _const(CTRL, "PIN_FLAG_SCREEN_PX") <= 56.0
    # Pin stays for green aim/read.
    sync = CTRL.split("func _sync_pin_flag_visible")[1].split("func ")[0]
    assert "_aiming" in sync

    assert "func _visual_ball_radius" in BALL
    vis = BALL.split("func _visual_ball_radius")[1].split("func ")[0]
    assert "return BALL_R_PUTT" in vis
    assert "SHORT_GAME_TRUE_SCALE_YD" not in BALL
    assert "SHORT_GAME_VISUAL_TYPES" not in BALL
    assert abs(_const(BALL, "BALL_R_PUTT") - 0.102) < 0.001
    # Legacy BALL_R alias must not reintroduce flight exaggerate.
    assert _const(BALL, "BALL_R") <= 0.15, _const(BALL, "BALL_R")

    print(
        f"short_game_scale_check: ok always-true-scale "
        f"pin_screen={_const(CTRL, 'PIN_FLAG_SCREEN_PX'):.0f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

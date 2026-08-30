#!/usr/bin/env python3
"""Contract: putt camera frames ball→cup in the HUD+panel-safe rect at every length.

Mirrors HoleController._putt_frame_zoom(). Zoom is span = dist + pad, not a
per-yardage table and not whole-green / object-size floors.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")
UI = Path(__file__).resolve().parents[1].joinpath("ui/ui_scale.gd").read_text(encoding="utf-8")

PX_PER_FOOT = 2.25 / 3.0  # BallPhysics.PX_PER_YARD / 3
VIEW = (1080.0, 1920.0)
# Tap-in through putter max (PUTTER_MAX_YD 25 → 75 ft).
LENGTHS_FT = (3, 6, 8, 12, 17, 25, 36, 50, 75)


def _const(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def putt_frame_zoom(
    dist_ft: float,
    *,
    cap: float,
    floor: float,
    span_pad: float,
    span_pad_frac: float,
    span_pad_min: float,
    span_floor: float,
    view_frac: float,
    hud_h: float,
    chrome_h: float,
    vertical: bool = True,
) -> float:
    dist = dist_ft * PX_PER_FOOT
    pad = min(max(dist * span_pad_frac, span_pad_min), span_pad)
    dx = 0.0 if vertical else dist * 0.7071
    dy = dist if vertical else dist * 0.7071
    span_x = max(abs(dx) + pad * 2.0, span_floor)
    span_y = max(abs(dy) + pad * 2.0, span_floor)
    safe_h = VIEW[1] - hud_h - chrome_h
    z = min(VIEW[0] * view_frac / span_x, max(safe_h, 1.0) * view_frac / span_y)
    return min(max(z, floor), cap)


def main() -> int:
    assert "func _putt_frame_zoom" in CTRL
    assert "PUTT_SPAN_COEFF" not in CTRL
    assert "SHOT_PANEL_H_PUTT" in CTRL
    zoom_fn = CTRL.split("func _desired_camera_zoom")[1].split("func ")[0]
    assert "_greenside_book_frame" in zoom_fn or "not _is_putt_context()" in zoom_fn
    assert "_putt_frame_zoom" in zoom_fn
    assert "func _putt_frame_look" in CTRL
    assert "func _putt_bottom_chrome" in CTRL
    look = CTRL.split("func _desired_camera_look")[1].split("func ")[0]
    assert "_putt_frame_look" in look
    frame_look = CTRL.split("func _putt_frame_look")[1].split("func ")[0]
    assert "lerp(_cup_pos, 0.5)" in frame_look
    assert "lerp(_aim_target" not in frame_look
    zoom_body = CTRL.split("func _putt_frame_zoom")[1].split("func ")[0]
    assert "_putt_bottom_chrome" in zoom_body
    assert "span_x" in zoom_body and "span_y" in zoom_body

    cap = _const(CTRL, "PUTT_ZOOM_CAP")
    kw = dict(
        cap=cap,
        floor=_const(CTRL, "PUTT_ZOOM_FLOOR"),
        span_pad=_const(CTRL, "PUTT_SPAN_PAD"),
        span_pad_frac=_const(CTRL, "PUTT_SPAN_PAD_FRAC"),
        span_pad_min=_const(CTRL, "PUTT_SPAN_PAD_MIN"),
        span_floor=_const(CTRL, "PUTT_SPAN_FLOOR"),
        view_frac=_const(CTRL, "PUTT_VIEW_FRAC"),
        hud_h=_const(UI, "HUD_HEIGHT"),
        chrome_h=_const(UI, "SHOT_PANEL_H_PUTT"),
    )
    assert cap >= 100.0, cap
    assert _const(CTRL, "PINCH_ABS_ZOOM_MAX") >= cap - 0.01

    safe_h = VIEW[1] - kw["hud_h"] - kw["chrome_h"]
    zs = []
    for ft in LENGTHS_FT:
        z = putt_frame_zoom(float(ft), **kw)
        zs.append(z)
        dist = ft * PX_PER_FOOT
        # Ball→cup must fit in the execute-safe height at every length.
        assert dist * z <= safe_h + 1e-6, (ft, dist * z, safe_h)
        # Short putts tighter than whole-green book zoom (cap 36).
        if ft <= 17:
            assert z > 36.0, (ft, z)

    # Longer putt → more open (or equal at the cap on tap-ins).
    for a, b, fa, fb in zip(zs, zs[1:], LENGTHS_FT, LENGTHS_FT[1:]):
        assert a >= b - 1e-6, (fa, a, fb, b)

    z3, z6, z17, z75 = zs[0], zs[LENGTHS_FT.index(6)], zs[LENGTHS_FT.index(17)], zs[-1]
    # Short putts pull in; lags stay open. Fixed 2px pad used to frame a 6-footer like ~11 ft.
    assert z6 > z17 > z75, (z6, z17, z75)
    assert z6 >= 100.0, z6

    # Roll eases toward live remaining (same as settle), not a locked 18% bump.
    assert "PUTT_ROLL_ZOOM_IN" not in CTRL
    proc = CTRL.split("func _process(_delta: float) -> void:")[-1].split("\nfunc ")[0]
    putt_roll = proc.split("if _is_putt_context() and _putt_cam_active:")[1].split("else:")[0]
    assert "_desired_camera_zoom()" in putt_roll
    assert "_desired_camera_look()" in putt_roll
    lerp_z = _const(CTRL, "PUTT_ROLL_ZOOM_LERP")
    assert abs(lerp_z - 0.08) < 1e-6, lerp_z  # match settle so rest isn't a second punch
    print(
        f"putt_camera_zoom_check: ok z(3ft)={z3:.1f} z(6ft)={z6:.1f} "
        f"z(17ft)={z17:.1f} z(75ft)={z75:.1f} lengths={len(LENGTHS_FT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

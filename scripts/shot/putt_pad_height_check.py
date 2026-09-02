#!/usr/bin/env python3
"""Recon: putt pad height vs pace precision (fractional lane → smaller panel = harder)."""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
PUTT = DIR.joinpath("putt_stroke.gd").read_text(encoding="utf-8")
GESTURE = DIR.joinpath("tempo_gesture.gd").read_text(encoding="utf-8")
UI = DIR.joinpath("../ui/ui_scale.gd").read_text(encoding="utf-8")
ROUTINE = DIR.joinpath("shot_routine.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")
BALL = DIR.joinpath("../ball/ball.gd").read_text(encoding="utf-8")

VIEW = (1080.0, 1920.0)
PX_PER_FOOT = 2.25 / 3.0  # BallPhysics.PX_PER_YARD / 3
LENGTHS_FT = (3, 6, 12, 20, 36, 75)


def _f(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def pad_h(panel: float, top: float, bottom: float, safe_b: float = 0.0) -> float:
    return panel - top - (bottom + safe_b)


def putt_frame_zoom(dist_ft: float, chrome_h: float, *, vertical: bool = True) -> dict:
    """Mirror HoleController._putt_frame_zoom + ball/cup screen span in the HUD–panel band."""
    dist = dist_ft * PX_PER_FOOT
    pad = min(
        max(dist * _f(CTRL, "PUTT_SPAN_PAD_FRAC"), _f(CTRL, "PUTT_SPAN_PAD_MIN")),
        _f(CTRL, "PUTT_SPAN_PAD"),
    )
    dx = 0.0 if vertical else dist * 0.7071
    dy = dist if vertical else dist * 0.7071
    span_x = max(abs(dx) + pad * 2.0, _f(CTRL, "PUTT_SPAN_FLOOR"))
    span_y = max(abs(dy) + pad * 2.0, _f(CTRL, "PUTT_SPAN_FLOOR"))
    hud = _f(UI, "HUD_HEIGHT")
    safe_h = VIEW[1] - hud - chrome_h
    view_frac = _f(CTRL, "PUTT_VIEW_FRAC")
    z_w = VIEW[0] * view_frac / span_x
    z_h = max(safe_h, 1.0) * view_frac / span_y
    z = min(max(min(z_w, z_h), _f(CTRL, "PUTT_ZOOM_FLOOR")), _f(CTRL, "PUTT_ZOOM_CAP"))
    pair_px = dist * z
    ball_px = 2.0 * _f(BALL, "BALL_R_PUTT") * z
    return {
        "z": z,
        "pair_px": pair_px,
        "safe_h": safe_h,
        "fit": pair_px <= safe_h + 1e-6,
        "ball_px": ball_px,
        "world_ft": (safe_h / z) / PX_PER_FOOT,
        "height_limited": z_h <= z_w and z < _f(CTRL, "PUTT_ZOOM_CAP") - 1e-6,
    }


def main() -> int:
    panel_full = _f(UI, "SHOT_PANEL_H")
    panel_was = 640.0  # Phase 4 SHOT_PANEL_H_PUTT — deleted; keep the 640-vs-900 math
    compact = _f(UI, "SHOT_PAD_TOP_COMPACT")
    bottom = _f(UI, "CONTROLS_PAD_BOTTOM")
    marker_min = _f(PUTT, "MARKER_MIN_FRAC")
    marker_max = _f(PUTT, "MARKER_MAX_FRAC")
    power_floor = _f(PUTT, "POWER_FLOOR")
    band_half = _f(PUTT, "BAND_HALF")
    band_perfect = _f(PUTT, "BAND_PERFECT")

    addr = GESTURE.split("func address_hint")[1].split("func ")[0]
    top = GESTURE.split("func top_hint")[1].split("func ")[0]
    assert "_is_putt()" in addr and "y = 0.22" in addr
    assert "_is_putt()" in top and "y = 0.92" in top
    lane_frac = 0.92 - 0.22

    # Power is lane fraction, not pixels — shrinking size.y compresses the same map.
    sample = GESTURE.split("func _finish_impact")[1].split("func ")[0]
    assert '"backswing_frac": _peak_disp / lane' in sample
    layout = ROUTINE.split("func layout_shot_chrome")[1].split("func ")[0]
    assert "SHOT_PANEL_H_PUTT" not in layout
    assert "SHOT_PAD_TOP_COMPACT" in layout
    assert "SHOT_PANEL_H_PUTT" not in UI
    assert panel_full == 900.0, panel_full

    span = marker_max - marker_min
    rel_per_frac = math.log(1.0 / power_floor) / span  # d(ln ft) / d(frac)

    def lane(panel: float, safe_b: float = 0.0) -> float:
        return pad_h(panel, compact, bottom, safe_b) * lane_frac

    def ft_per_px(ft: float, lane_px: float) -> float:
        return ft * rel_per_frac / lane_px

    old = lane(panel_was)
    now = lane(panel_full)
    ratio = old / now
    assert old < now, (old, now)
    print(
        f"putt_pad_height: panel now {panel_full:.0f} (was {panel_was:.0f})  "
        f"lane {now:.0f}/{old:.0f}px  ({(now / old - 1) * 100:.0f}% more travel than 640, "
        f"{1 / ratio:.2f}x ft error per px on the old pad)"
    )
    print(
        f"  PERFECT band {band_half * band_perfect * now:.1f}px now vs "
        f"{band_half * band_perfect * old:.1f}px at {panel_was:.0f}"
    )
    for ft in (12, 20, 36):
        print(
            f"  {ft:2d} ft: {ft_per_px(ft, now):.3f} ft/px now vs "
            f"{ft_per_px(ft, old):.3f} at {panel_was:.0f}  "
            f"(8px miss {8 * ft_per_px(ft, now):.1f} vs {8 * ft_per_px(ft, old):.1f} ft)"
        )

    chrome_fn = CTRL.split("func _putt_bottom_chrome")[1].split("func ")[0]
    assert "SHOT_PANEL_H_PUTT" not in chrome_fn
    assert "SHOT_PANEL_H" in chrome_fn
    for chrome in (panel_was, 720.0, panel_full):
        for ft in LENGTHS_FT:
            r = putt_frame_zoom(float(ft), chrome)
            assert r["fit"], (ft, chrome, r)
        r36 = putt_frame_zoom(36.0, chrome)
        print(
            f"  camera {chrome:.0f} chrome: 36ft z={r36['z']:.1f} ball={r36['ball_px']:.1f}px "
            f"slack={r36['safe_h'] - r36['pair_px']:.0f}px fit"
        )
    w640 = putt_frame_zoom(36.0, panel_was)["world_ft"]
    w900 = putt_frame_zoom(36.0, panel_full)["world_ft"]
    assert abs(w640 - w900) < 0.05, (w640, w900)
    r3_640 = putt_frame_zoom(3.0, panel_was)
    r3_900 = putt_frame_zoom(3.0, panel_full)
    assert abs(r3_640["z"] - r3_900["z"]) < 0.05
    assert r3_640["world_ft"] > r3_900["world_ft"]
    print(
        f"  3ft cap: world in band {r3_640['world_ft']:.1f}ft @640 vs "
        f"{r3_900['world_ft']:.1f}ft @900 (same z={r3_640['z']:.0f})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

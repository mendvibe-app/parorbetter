#!/usr/bin/env python3
"""Contract: putt setup zoom grades short vs long; roll holds locked frame.

True-scale Phase 2: distance framing + soft object-size floor on short/mid putts.
Mirrors HoleController._desired_camera_zoom() (putt branch).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")
BALL = Path(__file__).resolve().parents[1].joinpath("ball/ball.gd").read_text(encoding="utf-8")

PX_PER_FOOT = 2.25 / 3.0  # BallPhysics.PX_PER_YARD / 3
VIEW_MIN = 1080.0  # canvas_items stretch normalizes to design width
BALL_FILL = 33.0 / 64.0
CUP_FILL = 43.0 / 64.0


def _const(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def desired_putt_zoom(
    dist_ft: float,
    *,
    cap: float,
    floor: float,
    span_coeff: float,
    span_pad: float,
    span_floor: float,
    view_frac: float,
    min_ball_px: float,
    min_cup_px: float,
    blend_start: float,
    blend_end: float,
    ball_r: float,
    cup_r: float,
) -> float:
    dist = dist_ft * PX_PER_FOOT
    half_span = max(dist * span_coeff + span_pad, span_floor)
    z_fit = VIEW_MIN * view_frac / half_span
    vis_ball = BALL_FILL * (ball_r * 2.0)
    vis_cup = CUP_FILL * (cup_r * 2.0)
    z_obj = max(min_ball_px / vis_ball, min_cup_px / vis_cup)
    t = min(max((dist_ft - blend_start) / max(blend_end - blend_start, 1.0), 0.0), 1.0)
    z = (1.0 - t) * max(z_fit, z_obj) + t * z_fit
    return min(max(z, floor), cap)


def main() -> int:
    assert "PUTT_ZOOM_CAP" in CTRL
    assert "PUTT_SPAN_FLOOR" in CTRL
    assert "PUTT_MIN_CUP_SCREEN_PX" in CTRL
    assert "PUTT_MIN_BALL_SCREEN_PX" in CTRL
    assert "PUTT_SAFE_SCREEN_Y" in CTRL
    assert "func _ui_safe_look" in CTRL
    assert "lerpf(maxf(z_fit, z_obj), z_fit, t_long)" in CTRL
    assert "PINCH_ABS_ZOOM_MAX" in CTRL
    safe_y = _const(CTRL, "PUTT_SAFE_SCREEN_Y")
    assert 0.32 <= safe_y <= 0.48, safe_y  # above mid, clear of swing pad

    # Roll lock — no live chase punch.
    assert "func _lock_putt_camera" in CTRL
    assert "func _clear_putt_camera_lock" in CTRL
    assert "_putt_cam_active" in CTRL
    assert "PUTT_ROLL_LOOK_LERP" in CTRL
    assert "PUTT_TIGHTEN_RADIUS" not in CTRL

    cap = _const(CTRL, "PUTT_ZOOM_CAP")
    floor = _const(CTRL, "PUTT_ZOOM_FLOOR")
    span_coeff = _const(CTRL, "PUTT_SPAN_COEFF")
    span_pad = _const(CTRL, "PUTT_SPAN_PAD")
    span_floor = _const(CTRL, "PUTT_SPAN_FLOOR")
    view_frac = _const(CTRL, "PUTT_VIEW_FRAC")
    min_ball = _const(CTRL, "PUTT_MIN_BALL_SCREEN_PX")
    min_cup = _const(CTRL, "PUTT_MIN_CUP_SCREEN_PX")
    blend_start = _const(CTRL, "PUTT_OBJ_BLEND_START_FT")
    blend_end = _const(CTRL, "PUTT_OBJ_BLEND_END_FT")
    pinch_max = _const(CTRL, "PINCH_ABS_ZOOM_MAX")
    ball_r = _const(BALL, "BALL_R_PUTT")
    cup_r = _const(CTRL, "CUP_RADIUS")

    assert cap >= 100.0, cap
    assert span_floor < 8.0, span_floor  # old 12 blocked z>~47
    assert pinch_max >= cap - 0.01, (pinch_max, cap)

    kw = dict(
        cap=cap,
        floor=floor,
        span_coeff=span_coeff,
        span_pad=span_pad,
        span_floor=span_floor,
        view_frac=view_frac,
        min_ball_px=min_ball,
        min_cup_px=min_cup,
        blend_start=blend_start,
        blend_end=blend_end,
        ball_r=ball_r,
        cup_r=cup_r,
    )

    z_2ft = desired_putt_zoom(2.0, **kw)
    z_10ft = desired_putt_zoom(10.0, **kw)
    z_30ft = desired_putt_zoom(30.0, **kw)
    z_44ft = desired_putt_zoom(44.0, **kw)  # playtest 1686
    z_60ft = desired_putt_zoom(60.0, **kw)

    # Short putts much closer than mid/long lags.
    assert z_2ft > 80.0, z_2ft
    assert z_2ft > z_30ft > z_60ft, (z_2ft, z_30ft, z_60ft)
    assert z_10ft > z_44ft > z_60ft, (z_10ft, z_44ft, z_60ft)

    vis_cup = CUP_FILL * (cup_r * 2.0)
    vis_ball = BALL_FILL * (ball_r * 2.0)
    assert vis_cup * z_2ft >= min_cup * 0.9, (vis_cup * z_2ft, min_cup)
    assert vis_ball * z_2ft >= min_ball * 0.9, (vis_ball * z_2ft, min_ball)
    # Mid ~44 ft: glanceable (was ~10 px cup / ~4 px ball).
    assert vis_cup * z_44ft >= 14.0, vis_cup * z_44ft
    assert vis_ball * z_44ft >= 6.0, vis_ball * z_44ft
    assert z_44ft >= 50.0, z_44ft
    # Long lags still open vs short.
    assert z_60ft < z_10ft * 0.65, (z_60ft, z_10ft)

    print(
        f"putt_camera_zoom_check: ok z(2ft)={z_2ft:.1f} z(10ft)={z_10ft:.1f} "
        f"z(44ft)={z_44ft:.1f} z(60ft)={z_60ft:.1f} "
        f"cup_px@44={vis_cup * z_44ft:.1f} ball_px@44={vis_ball * z_44ft:.1f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

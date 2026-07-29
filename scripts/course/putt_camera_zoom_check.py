#!/usr/bin/env python3
"""Contract: putt setup zoom grades short vs long; roll holds locked frame.

Mirrors HoleController._desired_camera_zoom() (putt branch) and the stroke-start
lock used during putt roll. Live zoom-in / PUTT_TIGHTEN punch during roll was
jarring on short putts — zoom is frozen at launch framing instead.
"""
from __future__ import annotations

import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")

PX_PER_FOOT = 2.25 / 3.0  # BallPhysics.PX_PER_YARD / 3
VIEW_MIN = 1080.0  # canvas_items stretch normalizes to design width


def desired_putt_zoom(dist_ft: float) -> float:
    dist = dist_ft * PX_PER_FOOT
    half_span = max(dist * 0.90 + 6.0, 12.0)
    return min(max(VIEW_MIN * 0.52 / half_span, 2.6), 42.0)


def main() -> int:
    # Setup framing formula unchanged (short putts still read tighter at aim).
    assert "var half_span := maxf(dist * 0.90 + 6.0, 12.0)" in CTRL
    assert "clampf(view_min * 0.52 / half_span, 2.6, 42.0)" in CTRL

    # Roll lock — no live chase punch.
    assert "func _lock_putt_camera" in CTRL
    assert "func _clear_putt_camera_lock" in CTRL
    assert "_putt_cam_active" in CTRL
    assert "PUTT_ROLL_LOOK_LERP" in CTRL
    assert "PUTT_ROLL_BALL_WEIGHT" in CTRL
    assert "PUTT_ROLL_ZOOM_LERP" in CTRL
    assert "PUTT_TIGHTEN_RADIUS" not in CTRL
    assert "_putt_cam_look.lerp(ball.global_position, PUTT_ROLL_BALL_WEIGHT)" in CTRL
    assert "camera.zoom = camera.zoom.lerp(_putt_cam_zoom, PUTT_ROLL_ZOOM_LERP)" in CTRL

    z_2ft = desired_putt_zoom(2.0)
    z_6ft = desired_putt_zoom(6.0)
    z_10ft = desired_putt_zoom(10.0)
    z_15ft = desired_putt_zoom(15.0)
    z_35ft = desired_putt_zoom(35.0)
    z_60ft = desired_putt_zoom(60.0)

    # Short putts (<~10 ft) read clearly tighter than the 20-40 ft range.
    assert z_2ft > z_35ft * 1.5, (z_2ft, z_35ft)
    assert z_10ft > z_35ft * 1.3, (z_10ft, z_35ft)

    # Monotonic falloff — no flat plateau spanning the whole putting range like before.
    assert z_2ft >= z_6ft >= z_10ft >= z_15ft >= z_35ft >= z_60ft, (
        z_2ft, z_6ft, z_10ft, z_15ft, z_35ft, z_60ft,
    )
    assert z_15ft > z_35ft, (z_15ft, z_35ft)
    assert z_35ft > z_60ft, (z_35ft, z_60ft)

    # Long lags still zoom out (formula not accidentally clamped tight for them too).
    assert z_60ft < 15.0, z_60ft

    print(f"putt_camera_zoom_check: ok z(2ft)={z_2ft:.1f} z(10ft)={z_10ft:.1f} "
          f"z(35ft)={z_35ft:.1f} z(60ft)={z_60ft:.1f} (roll locked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Contract: putt camera zoom tightens for short putts, punches in on close roll.

Mirrors HoleController._desired_camera_zoom() (putt branch) and the roll-time
zoom-lerp / look-bias gating in _process(). Old constants (half_span floor 34,
cap 7.5) clamped every putt under ~70 ft to one flat zoom — this guards the
fix stays a monotonic, meaningfully-graded curve instead of drifting back.
"""
from __future__ import annotations

import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")

PX_PER_FOOT = 2.25 / 3.0  # BallPhysics.PX_PER_YARD / 3
VIEW_MIN = 1080.0  # confirmed via headless run: canvas_items stretch normalizes to design width


def desired_putt_zoom(dist_ft: float) -> float:
    dist = dist_ft * PX_PER_FOOT
    half_span = max(dist * 0.90 + 6.0, 12.0)
    return min(max(VIEW_MIN * 0.52 / half_span, 2.6), 42.0)


def main() -> int:
    assert "var half_span := maxf(dist * 0.90 + 6.0, 12.0)" in CTRL
    assert "clampf(view_min * 0.52 / half_span, 2.6, 42.0)" in CTRL
    assert "const PUTT_TIGHTEN_RADIUS := 11.25" in CTRL

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

    # Roll punch-in: gated on distance-to-cup, not air time (putts have none).
    assert "putt_closing_in and ball.state == GolfBall.State.ROLL" in CTRL
    assert "look.lerp(_cup_pos, 0.5 if putt_closing_in else 0.35)" in CTRL

    print(f"putt_camera_zoom_check: ok z(2ft)={z_2ft:.1f} z(10ft)={z_10ft:.1f} "
          f"z(35ft)={z_35ft:.1f} z(60ft)={z_60ft:.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

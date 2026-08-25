#!/usr/bin/env python3
"""Contract: mid-approach has margin; long tee (~216) opens corridor + look toward pin."""
from __future__ import annotations

import re
import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")

PX_PER_YARD = 2.25
VIEW_MIN = 1080.0


def _const(name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", CTRL)
    assert m, name
    return float(m.group(1))


def approach_pin_zoom(pin_yd: float, view_min: float = VIEW_MIN) -> float:
    coeff = _const("APPROACH_SPAN_COEFF")
    pad = _const("APPROACH_SPAN_PAD")
    floor = _const("APPROACH_SPAN_FLOOR")
    frac = _const("APPROACH_VIEW_FRAC")
    zmin = _const("APPROACH_ZOOM_MIN")
    zmax = _const("APPROACH_ZOOM_MAX")
    dist = max(pin_yd, 8.0) * PX_PER_YARD
    half_span = max(dist * coeff + pad, floor)
    return min(max(view_min * frac / half_span, zmin), zmax)


def corridor_zoom(view_x: float = 1080.0, width: float = 200.0) -> float:
    frac = _const("CORRIDOR_SCREEN_FRAC")
    zmin = _const("CORRIDOR_ZOOM_MIN")
    zmax = _const("CORRIDOR_ZOOM_MAX")
    return min(max(view_x * frac / width, zmin), zmax)


def aim_zoom(pin_yd: float, z_cor: float | None = None) -> float:
    if z_cor is None:
        z_cor = corridor_zoom()
    open_yd = _const("APPROACH_TEE_OPEN_YD")
    tee_frac = _const("APPROACH_TEE_CORRIDOR_FRAC")
    if pin_yd >= open_yd:
        return z_cor * tee_frac
    hi = _const("APPROACH_ZOOM_HI")
    long_hi = _const("APPROACH_ZOOM_LONG")
    z_pin = approach_pin_zoom(pin_yd)
    t = max(0.0, min(1.0, (pin_yd - hi) / max(long_hi - hi, 1.0)))
    return z_pin + (z_cor * 0.88 - z_pin) * t


def main() -> int:
    assert "APPROACH_TEE_OPEN_YD" in CTRL
    assert "TEE_LOOK_PIN_BIAS" in CTRL
    assert "CORRIDOR_ZOOM_MAX" in CTRL
    assert "TEE_LOOK_PIN_BIAS" in CTRL
    assert "ball.global_position.lerp(_cup_pos, TEE_LOOK_PIN_BIAS)" in CTRL
    load = CTRL.split("func load_hole")[1].split("func load_range")[0]
    assert "_desired_camera_zoom()" in load

    z_cor = corridor_zoom()
    z50 = aim_zoom(50.0, z_cor)
    z112 = aim_zoom(112.0, z_cor)
    z216 = aim_zoom(216.0, z_cor)
    z220 = aim_zoom(220.0, z_cor)

    assert z112 <= 3.2, z112
    assert z50 > z112 > z216, (z50, z112, z216)
    # Long tee: open corridor, not mid-iron glue.
    assert z216 <= z_cor * 0.85 + 0.05, (z216, z_cor)
    assert z216 <= 1.35, z216
    assert z220 <= z216 + 0.05, (z220, z216)
    assert _const("CORRIDOR_ZOOM_MAX") <= 1.65
    assert _const("APPROACH_TEE_OPEN_YD") <= 190.0

    print(
        f"approach_camera_zoom_check: ok z50={z50:.2f} z112={z112:.2f} "
        f"z216={z216:.2f} z_cor={z_cor:.2f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

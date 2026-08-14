#!/usr/bin/env python3
"""Contract: pin-primary approach aim zoom; 109 yd par-3 must not stay corridor-wide.

Mirrors HoleController._approach_pin_zoom + pin→corridor ease (APPROACH_ZOOM_HI/LONG).
"""
from __future__ import annotations

import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")

PX_PER_YARD = 2.25
VIEW_MIN = 1080.0
APPROACH_HI = 150.0
LONG_HI = 220.0


def approach_pin_zoom(pin_yd: float, view_min: float = VIEW_MIN) -> float:
    dist = max(pin_yd, 8.0) * PX_PER_YARD
    half_span = max(dist * 0.52 + 18.0, 48.0)
    return min(max(view_min * 0.62 / half_span, 1.35), 7.5)


def aim_zoom(pin_yd: float, z_cor: float = 1.35, book: bool = True) -> float:
    z_pin = approach_pin_zoom(pin_yd)
    t = max(0.0, min(1.0, (pin_yd - APPROACH_HI) / max(LONG_HI - APPROACH_HI, 1.0)))
    z = z_pin + (z_cor * 0.88 - z_pin) * t
    if book:
        book_w = max(0.0, min(1.0, (pin_yd - 28.0) / 52.0))
        z *= 0.98 + (0.94 - 0.98) * book_w
    return z


def main() -> int:
    assert "func _approach_pin_zoom" in CTRL
    assert "APPROACH_ZOOM_HI" in CTRL and "APPROACH_ZOOM_LONG" in CTRL
    assert "150.0" in CTRL and "220.0" in CTRL
    aim_fn = CTRL.split("func _desired_camera_zoom")[1].split("func ")[0]
    assert "lerpf(z_pin" in aim_fn or "lerpf(z_pin," in aim_fn
    assert "0.52" in CTRL.split("func _approach_pin_zoom")[1].split("func ")[0]
    # Putt untouched
    assert "view_min * 0.52 / half_span" in aim_fn

    z_cor = 1.35
    z50 = aim_zoom(50.0, z_cor)
    z109 = aim_zoom(109.0, z_cor)  # screenshot case
    z150 = aim_zoom(150.0, z_cor)
    z220 = aim_zoom(220.0, z_cor)
    z_cor_long = z_cor * 0.88

    # Pure pin through 150
    assert abs(z150 - approach_pin_zoom(150.0) * (0.98 + (0.94 - 0.98) * 1.0)) < 0.15 or z150 > z_cor * 2.0
    # 109 yd must not be corridor-wide (playtest fail)
    assert z109 > z_cor_long * 2.0, (z109, z_cor_long)
    assert z109 >= 3.2, z109
    # Monotonic: shorter → tighter
    assert z50 > z109 > z150 or (z50 > z109 and z109 >= z150 * 0.95), (z50, z109, z150)
    # Long tee near corridor
    assert abs(z220 - z_cor_long) < 0.05 or z220 <= z_cor, (z220, z_cor_long)
    assert z220 < z109, (z220, z109)

    print(
        f"approach_camera_zoom_check: ok z50={z50:.2f} z109={z109:.2f} "
        f"z150={z150:.2f} z220={z220:.2f} (cor_long~{z_cor_long:.2f})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Contract: short approach aim zoom tightens with pin yards vs corridor-only base.

Mirrors HoleController._approach_pin_zoom + non-putt blend in _desired_camera_zoom.
Putt branch and flight zoom are out of scope (putt_camera_zoom_check / flight_tracer).
"""
from __future__ import annotations

import sys
from pathlib import Path

CTRL = Path(__file__).with_name("hole_controller.gd").read_text(encoding="utf-8")
GRADE = (
    Path(__file__).resolve().parents[1].joinpath("shot/tempo_grade.gd").read_text(encoding="utf-8")
)

PX_PER_YARD = 2.25
VIEW_MIN = 1080.0
CHIP_YD = 20.0
SHORT_HI = 90.0


def approach_pin_zoom(pin_yd: float, view_min: float = VIEW_MIN) -> float:
    dist = max(pin_yd, 8.0) * PX_PER_YARD
    half_span = max(dist * 0.72 + 40.0, 70.0)
    return min(max(view_min * 0.50 / half_span, 1.15), 5.5)


def blend_weight(pin_yd: float) -> float:
    return 1.0 - max(0.0, min(1.0, (pin_yd - CHIP_YD) / max(SHORT_HI - CHIP_YD, 1.0)))


def blended(z_cor: float, pin_yd: float, book: bool = True) -> float:
    z_pin = approach_pin_zoom(pin_yd)
    w = blend_weight(pin_yd) * 0.88
    z = z_cor + (z_pin - z_cor) * w
    if book:
        book_w = max(0.0, min(1.0, (pin_yd - 28.0) / 52.0))
        z *= 0.96 + (0.90 - 0.96) * book_w
    return z


def main() -> int:
    assert "func _approach_pin_zoom" in CTRL
    aim_fn = CTRL.split("func _desired_camera_zoom")[1].split("func ")[0]
    assert "TempoGrade.CHIP_YD" in aim_fn
    assert "blend * 0.88" in aim_fn or "0.88" in aim_fn
    # Putt branch inside desired zoom still uses distance formula (untouched)
    assert "view_min * 0.52 / half_span" in aim_fn
    assert "func _approach_pin_zoom" in CTRL
    # Flight zoom not mixed into aim formula
    assert "_flight_camera_zoom" not in aim_fn
    assert "CHIP_YD" in GRADE

    z_cor = 1.35  # mid corridor
    z30 = blended(z_cor, 30.0, book=True)
    z50 = blended(z_cor, 50.0, book=True)
    z90 = blended(z_cor, 90.0, book=True)
    z_old_30 = z_cor * 0.92  # old green-book floor at short pin
    # Short wedge much tighter than old corridor*0.92 path
    assert z30 > z_old_30 * 1.8, (z30, z_old_30)
    # Monotonic: shorter pin → tighter (higher zoom)
    assert z30 > z50 > z90, (z30, z50, z90)
    # Long end of short band near corridor (not putt-tight)
    assert z90 < z_cor * 1.2, (z90, z_cor)
    # Pure long tee branch stays corridor * 0.88 (no pin blend past 90)
    assert blend_weight(120.0) == 0.0
    assert blend_weight(CHIP_YD) == 1.0

    print(
        f"approach_camera_zoom_check: ok z30={z30:.2f} z50={z50:.2f} z90={z90:.2f} "
        f"(old short book ~{z_old_30:.2f})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

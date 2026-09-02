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


def _f(src: str, name: str) -> float:
    m = re.search(rf"const {name}\s*:=\s*([0-9.]+)", src)
    assert m, name
    return float(m.group(1))


def pad_h(panel: float, top: float, bottom: float, safe_b: float = 0.0) -> float:
    return panel - top - (bottom + safe_b)


def main() -> int:
    panel_full = _f(UI, "SHOT_PANEL_H")
    panel_putt = _f(UI, "SHOT_PANEL_H_PUTT")
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
    assert "SHOT_PANEL_H_PUTT" in layout
    assert "SHOT_PAD_TOP_COMPACT" in layout

    span = marker_max - marker_min
    rel_per_frac = math.log(1.0 / power_floor) / span  # d(ln ft) / d(frac)

    def lane(panel: float, safe_b: float = 0.0) -> float:
        return pad_h(panel, compact, bottom, safe_b) * lane_frac

    def ft_per_px(ft: float, lane_px: float) -> float:
        return ft * rel_per_frac / lane_px

    old = lane(panel_full)
    now = lane(panel_putt)
    ratio = now / old
    assert old > now, (old, now)
    # Linear: panel shrink = lane shrink. 640/900 chrome-fixed → 508/768 = 0.661.
    pad_ratio = pad_h(panel_putt, compact, bottom) / pad_h(panel_full, compact, bottom)
    assert abs(ratio - pad_ratio) < 1e-9
    print(
        f"putt_pad_height: panel {panel_putt:.0f} vs {panel_full:.0f}  "
        f"lane {now:.0f}/{old:.0f}px  ({(1 - ratio) * 100:.0f}% less travel, "
        f"{1 / ratio:.2f}x ft error per px)"
    )
    print(
        f"  PERFECT band {band_half * band_perfect * now:.1f}px now vs "
        f"{band_half * band_perfect * old:.1f}px at {panel_full:.0f}"
    )
    for ft in (12, 20, 36):
        print(
            f"  {ft:2d} ft: {ft_per_px(ft, now):.3f} ft/px now vs "
            f"{ft_per_px(ft, old):.3f} at {panel_full:.0f}  "
            f"(8px miss {8 * ft_per_px(ft, now):.1f} vs {8 * ft_per_px(ft, old):.1f} ft)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

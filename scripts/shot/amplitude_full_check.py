#!/usr/bin/env python3
"""Phase 1 — full-swing amplitude→power curve, inverse, mash tax, punch isolation.

Usage:
  python scripts/shot/amplitude_full_check.py
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
PHYS = (DIR.parent / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
GRADE = (DIR / "tempo_grade.gd").read_text(encoding="utf-8")
ROUTINE = (DIR / "shot_routine.gd").read_text(encoding="utf-8")
GESTURE = (DIR / "tempo_gesture.gd").read_text(encoding="utf-8")


def _f(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    assert m, f"missing: {pattern}"
    return float(m.group(1))


POWER_POCKET_LO = _f(PHYS, r"const POWER_POCKET_LO\s*:=\s*([0-9.]+)")
POWER_POCKET_HI = _f(PHYS, r"const POWER_POCKET_HI\s*:=\s*([0-9.]+)")
FULL_ADDRESS_Y = _f(PHYS, r"const FULL_ADDRESS_Y\s*:=\s*([0-9.]+)")
FULL_TOP_Y = _f(PHYS, r"const FULL_TOP_Y\s*:=\s*([0-9.]+)")
# bs_floor("full") else-branch literal in tempo_grade.gd
_m_bs = re.search(
    r'static func bs_floor\([^)]*\)[^:]*:[\s\S]*?else\s+([0-9.]+)',
    GRADE,
)
assert _m_bs, "bs_floor full else literal not found"
BS_FLOOR_FULL = float(_m_bs.group(1))


def full_lane_pad_len() -> float:
    return abs(FULL_TOP_Y - FULL_ADDRESS_Y)


def power_from_amplitude(backswing_len: float) -> float:
    floor_len = BS_FLOOR_FULL
    full_len = full_lane_pad_len()
    span = max(full_len - floor_len, 0.001)
    t = min(max((backswing_len - floor_len) / span, 0.0), 1.0)
    return POWER_POCKET_LO + (1.0 - POWER_POCKET_LO) * t


def amplitude_for_power(power: float) -> float:
    floor_len = BS_FLOOR_FULL
    full_len = full_lane_pad_len()
    p = min(max(power, POWER_POCKET_LO), 1.0)
    t = (p - POWER_POCKET_LO) / max(1.0 - POWER_POCKET_LO, 0.001)
    return floor_len + t * (full_len - floor_len)


def force_factor(power: float) -> float:
    """Mirror BallPhysics.force_factor mash branch only (no baby tax)."""
    p = min(max(power, 0.0), 1.0)
    if p > POWER_POCKET_HI:
        return min(max((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0), 1.0)
    return 0.0


def main() -> int:
    assert "static func power_from_amplitude" in PHYS
    assert "static func amplitude_for_power" in PHYS
    assert "static func full_lane_pad_len" in PHYS
    assert "TempoGrade.bs_floor(\"full\")" in PHYS
    # Geometry sync with gesture defaults for full.
    assert "var y := 0.30" in GESTURE
    assert re.search(r"func top_hint[\s\S]*?var y := 0\.92", GESTURE), "full top_hint y drifted"

    len_full = full_lane_pad_len()
    assert abs(len_full - 0.62) < 1e-9, len_full
    assert abs(POWER_POCKET_LO - 0.60) < 1e-9
    assert abs(POWER_POCKET_HI - 0.92) < 1e-9
    assert abs(BS_FLOOR_FULL - 0.18) < 1e-9, BS_FLOOR_FULL

    # Endpoints.
    assert abs(power_from_amplitude(BS_FLOOR_FULL) - POWER_POCKET_LO) < 1e-9
    assert abs(power_from_amplitude(len_full) - 1.0) < 1e-9
    # Past top clamps at 1.0.
    assert abs(power_from_amplitude(len_full + 0.05) - 1.0) < 1e-9

    # Inverse round-trip at pocket + mid.
    for p in (POWER_POCKET_LO, 0.75, POWER_POCKET_HI, 1.0):
        amp = amplitude_for_power(p)
        back = power_from_amplitude(amp)
        assert abs(back - p) < 1e-9, (p, amp, back)

    # Pocket mark sits between floor and lane top.
    pocket_len = amplitude_for_power(POWER_POCKET_HI)
    assert BS_FLOOR_FULL < pocket_len < len_full, (pocket_len, len_full)

    # --- Safety: overswing past pocket actually taxes via force_factor ---
    assert force_factor(POWER_POCKET_HI) == 0.0
    assert force_factor(power_from_amplitude(pocket_len)) == 0.0
    full_pull = power_from_amplitude(len_full)
    assert abs(full_pull - 1.0) < 1e-9
    mash = force_factor(full_pull)
    assert mash > 0.99, f"full-lane pull must max mash tax, got {mash}"
    # Mid-overswing (between pocket and top) also taxes.
    mid_len = (pocket_len + len_full) * 0.5
    mid_p = power_from_amplitude(mid_len)
    assert mid_p > POWER_POCKET_HI
    assert force_factor(mid_p) > 0.0, mid_p

    # Launch still keys mash off true_power when set (Phase 1 wires amp → true_power).
    assert "if result.true_power > 0.0:" in PHYS
    assert "force_p = result.true_power" in PHYS
    assert "amp_power if amp_power >= 0.0 else true_power_pct" in ROUTINE

    # --- Safety: punch stays aim-solved (bit-identical path) ---
    # Amplitude branch is gated on flight_shot_type() == "full" only.
    assert 'if flight_shot_type() == "full":' in ROUTINE
    assert "power = clampf(amp_power * power_mul, 0.05, 1.0)" in ROUTINE
    assert "power = clampf(committed_power * power_mul, 0.05, 1.0)" in ROUTINE
    # Punch pad/grade identity still remaps via flight_shot_type; power else-branch.
    assert 'return "punch"' in ROUTINE or "punch_mode" in ROUTINE
    # Markers only when pad_type == "full".
    assert 'if pad_type == "full":' in ROUTINE
    assert "full_show_markers = true" in ROUTINE
    assert "_draw_full_amplitude_markers" in GESTURE

    # Tempo ratio still independent: grade has no power_from_amplitude.
    assert "power_from_amplitude" not in GRADE

    print("amplitude_full_check: OK")
    print(f"  LEN_FULL={len_full:.2f} floor={BS_FLOOR_FULL:.2f} pocket_len={pocket_len:.3f}")
    print(f"  power@floor={power_from_amplitude(BS_FLOOR_FULL):.2f} @top={full_pull:.2f}")
    print(f"  force_factor(@top)={mash:.2f} (mash tax fires)")
    print("  punch/non-full: committed*power_mul path retained")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        raise SystemExit(1)

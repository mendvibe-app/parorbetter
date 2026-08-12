#!/usr/bin/env python3
"""Phase 2 — pitch/flop amplitude map + chip already on PuttStroke; punch still aim.

Usage:
  python scripts/shot/amplitude_short_check.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
PHYS = (DIR.parent / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
GRADE = (DIR / "tempo_grade.gd").read_text(encoding="utf-8")
ROUTINE = (DIR / "shot_routine.gd").read_text(encoding="utf-8")
GESTURE = (DIR / "tempo_gesture.gd").read_text(encoding="utf-8")
PUTT = (DIR / "putt_stroke.gd").read_text(encoding="utf-8")


def _f(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    assert m, f"missing: {pattern}"
    return float(m.group(1))


POWER_POCKET_LO = _f(PHYS, r"const POWER_POCKET_LO\s*:=\s*([0-9.]+)")
POWER_POCKET_HI = _f(PHYS, r"const POWER_POCKET_HI\s*:=\s*([0-9.]+)")
FULL_ADDRESS_Y = _f(PHYS, r"const FULL_ADDRESS_Y\s*:=\s*([0-9.]+)")
FULL_TOP_Y = _f(PHYS, r"const FULL_TOP_Y\s*:=\s*([0-9.]+)")
SHORT_ADDRESS_Y = _f(PHYS, r"const SHORT_ADDRESS_Y\s*:=\s*([0-9.]+)")
SHORT_TOP_Y = _f(PHYS, r"const SHORT_TOP_Y\s*:=\s*([0-9.]+)")
CHIP_ADDRESS_Y = _f(PHYS, r"const CHIP_ADDRESS_Y\s*:=\s*([0-9.]+)")
CHIP_TOP_Y = _f(PHYS, r"const CHIP_TOP_Y\s*:=\s*([0-9.]+)")

_m_bs = re.search(
    r'static func bs_floor\([^)]*\)[^:]*:[\s\S]*?else\s+([0-9.]+)',
    GRADE,
)
assert _m_bs
BS_FLOOR_FULL = float(_m_bs.group(1))
BS_FLOOR_SHORT = _f(
    GRADE,
    r'static func bs_floor\([^)]*\)[^:]*:[\s\S]*?return \(\s*\n\s*([0-9.]+)',
)


def lane_pad_len(shot_type: str) -> float:
    if shot_type in ("pitch", "flop", "punch"):
        return abs(SHORT_TOP_Y - SHORT_ADDRESS_Y)
    if shot_type == "chip":
        return abs(CHIP_TOP_Y - CHIP_ADDRESS_Y)
    return abs(FULL_TOP_Y - FULL_ADDRESS_Y)


def bs_floor(shot_type: str) -> float:
    if shot_type in ("putt", "pitch", "flop", "punch"):
        return BS_FLOOR_SHORT
    return BS_FLOOR_FULL


def power_from_amplitude(backswing_len: float, shot_type: str = "full") -> float:
    floor_len = bs_floor(shot_type)
    full_len = lane_pad_len(shot_type)
    span = max(full_len - floor_len, 0.001)
    t = min(max((backswing_len - floor_len) / span, 0.0), 1.0)
    return POWER_POCKET_LO + (1.0 - POWER_POCKET_LO) * t


def amplitude_for_power(power: float, shot_type: str = "full") -> float:
    floor_len = bs_floor(shot_type)
    full_len = lane_pad_len(shot_type)
    p = min(max(power, POWER_POCKET_LO), 1.0)
    t = (p - POWER_POCKET_LO) / max(1.0 - POWER_POCKET_LO, 0.001)
    return floor_len + t * (full_len - floor_len)


def force_factor(power: float) -> float:
    p = min(max(power, 0.0), 1.0)
    if p > POWER_POCKET_HI:
        return min(max((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0), 1.0)
    return 0.0


def main() -> int:
    assert "static func lane_pad_len" in PHYS
    assert "static func uses_amplitude_power" in PHYS
    assert 'shot_type == "full" or shot_type == "pitch" or shot_type == "flop"' in PHYS
    assert "BallPhysics.uses_amplitude_power" in ROUTINE
    assert 'power_from_amplitude(' in ROUTINE
    # Punch still aim-solved.
    assert "aim sets distance" in ROUTINE  # punch hints
    assert "PUNCH" in ROUTINE

    # Geometry sync with gesture.
    assert abs(lane_pad_len("full") - 0.62) < 1e-9
    assert abs(lane_pad_len("pitch") - 0.50) < 1e-9
    assert abs(lane_pad_len("flop") - 0.50) < 1e-9
    assert abs(lane_pad_len("chip") - 0.65) < 1e-9

    for st in ("full", "pitch", "flop"):
        fl = lane_pad_len(st)
        assert abs(power_from_amplitude(bs_floor(st), st) - POWER_POCKET_LO) < 1e-9
        assert abs(power_from_amplitude(fl, st) - 1.0) < 1e-9
        pocket = amplitude_for_power(POWER_POCKET_HI, st)
        assert bs_floor(st) < pocket < fl
        assert force_factor(power_from_amplitude(fl, st)) > 0.99

    # Chip stays on PuttStroke log map (not linear pad-H).
    assert "static func power_from_frac" in PUTT
    assert 'shot_type == "putt" or shot_type == "chip"' in ROUTINE
    assert "PuttStroke.grade" in ROUTINE or "PuttStroke.marker_frac" in ROUTINE
    # Chip hints say pull length.
    assert "CHIP — pull length = power" in ROUTINE

    # Markers draw for pitch/flop too.
    assert 'shot_type == "pitch" or shot_type == "flop"' in GESTURE

    print("amplitude_short_check: OK")
    print(
        f"  pitch/flop LEN={lane_pad_len('pitch'):.2f} floor={bs_floor('pitch'):.2f} "
        f"pocket={amplitude_for_power(POWER_POCKET_HI, 'pitch'):.3f}"
    )
    print("  chip: PuttStroke amplitude-primary; punch: still aim-solved")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        raise SystemExit(1)

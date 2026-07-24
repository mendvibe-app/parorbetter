#!/usr/bin/env python3
"""Contract check: putt pace is real (fixed max) and MISS doesn't triple-stack distance."""
from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
PHYS = DIR.joinpath("ball_physics.gd").read_text(encoding="utf-8")
GRADE = DIR.joinpath("../shot/tempo_grade.gd").read_text(encoding="utf-8")
HOLE = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")

PUTTER_MAX_YD = 40.0


def recommended_power(remaining_yd: float, club_max: float) -> float:
    need = max(remaining_yd, 2.0)
    return min(max(need / club_max, 0.05), 1.0)


def putt_roll_yards(committed_power: float, tempo_power_mul: float, contact: str) -> float:
    """Mirror launch_velocity putt distance after the unstack fix."""
    # Tempo already applied into result.power = committed * tempo_power_mul
    result_power = committed_power * tempo_power_mul
    # No contact_multiplier on putt distance
    power_mul = result_power * 1.0
    total = PUTTER_MAX_YD * power_mul
    dist_err = {"THIN": 1.12, "FAT": 0.78, "MISS": 1.0, "GOOD": 1.0, "PERFECT": 1.0}.get(contact, 1.0)
    return total * dist_err


def main() -> int:
    assert "PUTTER_MAX_YD := 40.0" in PHYS
    assert "remaining_yd * 1.6" not in PHYS
    assert "max_yards\": PUTTER_MAX_YD" in PHYS or "PUTTER_MAX_YD" in PHYS

    # Fixed max → short vs long putts commit different %
    p3 = recommended_power(3.0, PUTTER_MAX_YD)
    p20 = recommended_power(20.0, PUTTER_MAX_YD)
    assert abs(p3 - 3.0 / PUTTER_MAX_YD) < 1e-6 or abs(p3 - max(3.0, 2.0) / PUTTER_MAX_YD) < 1e-6
    assert p20 > p3 + 0.2, (p3, p20)
    assert abs(p20 - 20.0 / PUTTER_MAX_YD) < 1e-6

    # Old self-cancel bug: remaining/(remaining*1.6) was always 0.625
    assert abs(p3 - 0.625) > 0.2
    assert abs(p20 - 0.625) > 0.01

    # Source: putt path skips contact_multiplier on distance
    assert "if not is_putt:" in PHYS
    assert "contact_multiplier(result.contact_quality)" in PHYS
    # MISS dist_err removed (no 0.65 branch)
    assert "ShotResult.ContactQuality.MISS:" not in PHYS.split("if is_putt:")[1].split("return {")[0] or \
        "dist_err = 0.65" not in PHYS
    assert "dist_err = 0.65" not in PHYS

    # MISS putt ≈ half intended via tempo power_mul only (~0.50), not ~13%
    committed = recommended_power(14.0, PUTTER_MAX_YD)
    intended = PUTTER_MAX_YD * committed
    miss_roll = putt_roll_yards(committed, 0.50, "MISS")
    old_stack = intended * 0.50 * 0.4 * 0.65
    assert miss_roll >= intended * 0.45, miss_roll
    assert miss_roll <= intended * 0.55, miss_roll
    assert miss_roll > old_stack * 2.5, (miss_roll, old_stack)

    # Putt stroke owns the MISS distance floor (not TempoGrade ratio)
    PUTT = DIR.joinpath("../shot/putt_stroke.gd").read_text(encoding="utf-8")
    assert "power_mul = minf(power_mul, 0.50)" in PUTT or "min(power_mul, 0.50)" in PUTT
    assert "PuttStroke" in DIR.joinpath("../shot/shot_routine.gd").read_text(encoding="utf-8")

    # Pace UI: aim/stroke stay blind — no live pace/pin numbers on screen
    assert "_refresh_putt_pace_feedback" in HOLE
    assert "Putt — set line & pace" in HOLE
    assert "Pin %d yd" not in HOLE
    assert "pace %d yd" not in HOLE
    assert 'feedback.text = "Putter"' not in HOLE
    # Internal pace still computed for grading (aim distance → committed_power)
    assert "aim_yd" in HOLE or "distance_to(_aim_target)" in HOLE

    # Long lag reachable: 95 ft under putter max with pad room above the marker
    assert PUTTER_MAX_YD * 3.0 >= 95.0
    p95 = recommended_power(95.0 / 3.0, PUTTER_MAX_YD)
    assert p95 < 0.95, p95  # headroom past the hole
    assert "SCALE_TICK_FT := [45, 60, 90]" in PUTT or "45, 60, 90" in PUTT

    # Greens large enough that a 95 ft putt isn't edge-to-edge on a medium green
    GEN = DIR.joinpath("../course/hole_generator.gd").read_text(encoding="utf-8")
    assert "lerpf(42.0, 78.0, green_size)" in GEN
    # Putt camera leaves margin so long lags read as travel
    assert "view_min * 0.40" in HOLE or "view_min * 0.4" in HOLE

    print("putt_pace_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Phase 0/1 swing instrumentation — F1 plumbing + TempoGrade contact-only power_mul.

Phase 1: full swings read power from amplitude in shot_routine; pitch/flop/punch
stay aim-solved. TempoGrade.power_mul remains contact-tier only (no amplitude).

Usage:
  python scripts/shot/amplitude_power_check.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
GESTURE = (DIR / "tempo_gesture.gd").read_text(encoding="utf-8")
GRADE = (DIR / "tempo_grade.gd").read_text(encoding="utf-8")
PUTT = (DIR / "putt_stroke.gd").read_text(encoding="utf-8")
ROUTINE = (DIR / "shot_routine.gd").read_text(encoding="utf-8")
DEBUG = (DIR.parent / "debug" / "debug_controls.gd").read_text(encoding="utf-8")
HOLE = (DIR.parent / "course" / "hole_controller.gd").read_text(encoding="utf-8")
PHYS = (DIR.parent / "ball" / "ball_physics.gd").read_text(encoding="utf-8")


def _require(src: str, needle: str, where: str) -> None:
    assert needle in src, f"missing in {where}: {needle!r}"


def main() -> int:
    _require(GESTURE, '"backswing_len":', "tempo_gesture.gd")
    _require(GESTURE, '"backswing_frac":', "tempo_gesture.gd")

    # TempoGrade: amplitude still balance-only; power_mul contact-tier only.
    _require(GRADE, "sample.get(\"backswing_len\"", "tempo_grade.gd")
    assert "power_from_frac" not in GRADE
    assert "power_from_amplitude" not in GRADE
    assert re.search(
        r'var power_mul := 1\.0[\s\S]*?contact == ShotResult\.ContactQuality\.MISS',
        GRADE,
    ), "tempo_grade power_mul block drifted"

    # Phase 1: full uses amplitude; non-full keeps committed * power_mul.
    _require(ROUTINE, 'flight_shot_type() == "full"', "shot_routine.gd")
    _require(ROUTINE, "BallPhysics.power_from_amplitude", "shot_routine.gd")
    _require(
        ROUTINE,
        "power = clampf(committed_power * power_mul, 0.05, 1.0)",
        "shot_routine.gd",
    )
    _require(ROUTINE, "solve_committed_power", "shot_routine.gd")
    # Punch must not take the amplitude branch (gate is flight_shot_type).
    assert 'flight_shot_type() == "full"' in ROUTINE
    _require(ROUTINE, "pull length = power", "shot_routine.gd")  # mixed-window UI

    _require(ROUTINE, 'verdict["backswing_len"]', "shot_routine.gd")
    _require(ROUTINE, 'verdict["rolled_power"]', "shot_routine.gd")
    stamp_idx = ROUTINE.find('verdict["backswing_len"]')
    force_idx = ROUTINE.find("GameState.force_perfect")
    assert stamp_idx > force_idx > 0, "amplitude stamp must follow force_perfect path"

    _require(HOLE, '"true_power": result.true_power', "hole_controller.gd")
    _require(DEBUG, "Amp BS len", "debug_controls.gd")
    _require(DEBUG, "Amp frac", "debug_controls.gd")
    assert "AmplitudeSparkline" not in DEBUG

    _require(PUTT, "static func power_from_frac", "putt_stroke.gd")
    _require(PHYS, "static func power_from_amplitude", "ball_physics.gd")
    _require(PHYS, "static func amplitude_for_power", "ball_physics.gd")

    print("amplitude_power_check: OK")
    print("  TempoGrade power_mul: contact only (no amplitude)")
    print("  Full: power_from_amplitude; non-full: committed * power_mul")
    print("  Mixed-window hint present; F1 Amp plumbing intact")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        raise SystemExit(1)

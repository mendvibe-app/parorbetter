#!/usr/bin/env python3
"""Phase 0 swing instrumentation — amplitude vs aim-solved power contracts.

No amplitude→power mapping yet. This harness locks today's TempoGrade-family
invariant (full/pitch/flop/punch: amplitude does not feed rolled power) and
keeps the putt/chip reference shape visible for Phase 1.

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


def _require(src: str, needle: str, where: str) -> None:
    assert needle in src, f"missing in {where}: {needle!r}"


def main() -> int:
    # --- Gesture still emits both amplitude units (Phase 1 picks later) ---
    _require(GESTURE, '"backswing_len":', "tempo_gesture.gd")
    _require(GESTURE, '"backswing_frac":', "tempo_gesture.gd")
    _require(GESTURE, "_peak_disp / pad", "tempo_gesture.gd")
    _require(GESTURE, "_peak_disp / lane", "tempo_gesture.gd")

    # --- TempoGrade family: amplitude is balance-only, not power ---
    _require(GRADE, "sample.get(\"backswing_len\"", "tempo_grade.gd")
    assert "power_from_frac" not in GRADE, "tempo_grade must not own amplitude→power"
    # power_mul still contact-tier only (thin/miss floors) — no amplitude term.
    assert re.search(
        r'var power_mul := 1\.0[\s\S]*?contact == ShotResult\.ContactQuality\.MISS',
        GRADE,
    ), "tempo_grade power_mul block drifted"
    assert "power_from_frac" not in GRADE
    assert "rolled :=" not in GRADE

    # ShotRoutine full path still: power = committed * power_mul (aim-solved base).
    _require(
        ROUTINE,
        'var power := clampf(committed_power * float(verdict["power_mul"]), 0.05, 1.0)',
        "shot_routine.gd",
    )
    _require(ROUTINE, "solve_committed_power", "shot_routine.gd")

    # --- Phase 0 instrumentation plumbing (display only) ---
    _require(ROUTINE, 'verdict["backswing_len"]', "shot_routine.gd")
    _require(ROUTINE, 'verdict["backswing_frac"]', "shot_routine.gd")
    _require(ROUTINE, 'verdict["committed_power"]', "shot_routine.gd")
    _require(ROUTINE, 'verdict["true_power"]', "shot_routine.gd")
    _require(ROUTINE, 'verdict["rolled_power"]', "shot_routine.gd")
    # Stamp after force overrides — real pull still visible on QA forced shots.
    stamp_idx = ROUTINE.find('verdict["backswing_len"]')
    force_idx = ROUTINE.find("GameState.force_perfect")
    assert stamp_idx > force_idx > 0, "amplitude stamp must follow force_perfect path"

    _require(HOLE, '"true_power": result.true_power', "hole_controller.gd")
    _require(HOLE, '"committed_power": shot_routine.committed_power', "hole_controller.gd")

    _require(DEBUG, "Amp BS len", "debug_controls.gd")
    _require(DEBUG, "backswing_len", "debug_controls.gd")
    _require(DEBUG, "backswing_frac", "debug_controls.gd")
    _require(DEBUG, "rolled_power", "debug_controls.gd")
    # No Phase-0 amplitude sparkline Control — text gap line only.
    assert "AmplitudeSparkline" not in DEBUG
    assert "amplitude_to_power" not in ROUTINE
    assert "amplitude_to_power" not in GRADE
    assert "amplitude_to_power" not in GESTURE

    # --- Putt/chip reference shape (NOT in the no-amp→power invariant) ---
    _require(PUTT, "static func power_from_frac", "putt_stroke.gd")
    _require(PUTT, "static func marker_frac", "putt_stroke.gd")
    _require(PUTT, "var rolled := power_from_frac(actual)", "putt_stroke.gd")
    _require(
        PUTT,
        'sample.get("backswing_frac"',
        "putt_stroke.gd",
    )

    # --- Phase 1 scaffold (harness-only; no .gd stub) ---
    # When Phase 1 lands: implement amplitude_to_power here, golden-test it,
    # and flip the TempoGrade-family invariant above.
    print("amplitude_power_check: Phase 0 OK")
    print("  TempoGrade family: amplitude does not feed rolled power")
    print("  PuttStroke.power_from_frac: present (reference shape)")
    print("  F1 plumbing: backswing_len + backswing_frac + commit/true/rolled")
    print("  Phase 1: implement amplitude_to_power in this harness (not in .gd yet)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        raise SystemExit(1)

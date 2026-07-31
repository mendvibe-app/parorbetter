#!/usr/bin/env python3
"""Practice swings: per shot type, auto-chain, dwell for feedback, no standalone button."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
GS = (ROOT / "scripts/autoload/game_state.gd").read_text(encoding="utf-8")
SR = (ROOT / "scripts/shot/shot_routine.gd").read_text(encoding="utf-8")
DBG = (ROOT / "scripts/debug/debug_controls.gd").read_text(encoding="utf-8")


def main() -> None:
    # Per-type prefs (full / pitch / chip / putt)
    assert "practice_reps" in GS
    assert "func practice_swing_count_for" in GS
    assert "func set_practice_swing_count" in GS
    assert 'prefs", "practice_reps"' in GS or "practice_reps" in GS
    assert "func _load_practice_reps" in GS
    # Migration from flat count still recognized
    assert "practice_swing_count" in GS  # legacy key read in _load_practice_reps
    assert '"full"' in GS and '"pitch"' in GS and '"chip"' in GS and '"putt"' in GS

    # Standalone Practice Swing button gone
    assert "PracticeSwingButton" not in HC
    assert "_setup_practice_btn" not in HC
    assert "_start_practice_swing" not in HC
    assert "_practice_btn" not in HC

    # Auto-chain uses per-shot-type count
    assert "_practice_reps_left" in HC
    assert "practice_swing_count_for" in HC
    assert "_practice_count_for_current_shot" in HC
    assert "TempoGrade.shot_type_for" in HC
    confirm = HC.split("func _confirm_aim")[1].split("func ")[0]
    assert "_practice_reps_left" in confirm
    assert "_practice_count_for_current_shot" in confirm
    assert "_start_power_swing(is_practice" in confirm or "_start_power_swing(" in confirm
    prac = HC.split("func _on_practice_result")[1].split("func ")[0]
    assert "_practice_reps_left" in prac
    assert "_start_power_swing(true" in prac
    assert "_start_power_swing(false, true)" in prac
    assert "_aiming = true" not in prac  # no return to aim between reps
    # Feedback dwell long enough to read (not the old 0.4s flash)
    assert "create_timer(2.2)" in prac or "create_timer(2." in prac
    assert "create_timer(0.4)" not in prac

    # Range ignored
    assert "range_mode" in confirm

    # Rep dots
    assert "func set_rep_indicator" in SR
    assert "RepDots" in SR

    # F1: one spin per shot type
    assert "practice_spins" in DBG
    assert "Practice swings" in DBG
    assert "set_practice_swing_count" in DBG
    for st in ("full", "pitch", "chip", "putt"):
        assert f'"{st}"' in DBG or f"'{st}'" in DBG

    print("practice_reps_check: ok")


if __name__ == "__main__":
    main()

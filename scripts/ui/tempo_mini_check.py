#!/usr/bin/env python3
"""Tempo mini readout: two-part pace for full/pitch; amplitude path for putt."""

from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
MINI = DIR.joinpath("tempo_mini.gd").read_text(encoding="utf-8")
PANEL = DIR.joinpath("shot_result_panel.gd").read_text(encoding="utf-8")
TSCN = DIR.joinpath("../../scenes/ui/shot_result_panel.tscn").read_text(encoding="utf-8")
GRADE = DIR.joinpath("../shot/tempo_grade.gd").read_text(encoding="utf-8")
METER = DIR.joinpath("../shot/meter_display.gd").read_text(encoding="utf-8")

BAND_PERFECT, BAND_GOOD = 0.50, 1.15


def needle_color(abs_n: float) -> str:
    if abs_n <= BAND_PERFECT:
        return "green"
    if abs_n <= BAND_GOOD:
        return "yellow"
    return "red"


def main() -> int:
    assert "GameState.last_tempo_metrics" in PANEL
    assert '"tolerance"' in MINI and '"target"' in MINI and '"ratio"' in MINI
    assert '"target_frac"' in MINI and '"actual_frac"' in MINI

    assert "TempoGrade.BAND_PERFECT" in MINI and "TempoGrade.BAND_GOOD" in MINI
    assert "PuttStroke.BAND_PERFECT" in MINI and "PuttStroke.BAND_GOOD" in MINI
    assert needle_color(0.3) == "green"

    # Full/pitch: two-part pace, not single Early/Late
    assert "backswing_read" in MINI and "downswing_read" in MINI
    assert "back_line" in MINI and "down_line" in MINI
    assert "func _pace_color" in MINI
    assert "Backswing" in MINI or "back_line" in MINI
    # Amplitude path still uses Early/Late/On time
    amp = MINI.split("func _draw_amplitude_strip")[1]
    assert "_verdict_word" in MINI
    assert '"Early"' in MINI and '"On time"' in MINI and '"Late"' in MINI
    assert "_verdict_word" in amp

    assert "NEEDLE_POP_FROM" in MINI and "create_tween" in MINI
    assert "verdict == _last_verdict" in MINI

    assert "func pace_reads" in GRADE and "func pace_copy" in GRADE
    assert "PACE_TOL_FRAC" in GRADE
    # Scoring contact path still ratio-based (not pace)
    assert "abs_n * 0.22" in GRADE

    # Live meter gated to practice || range
    assert "GameState.range_mode" in METER
    assert "p_practice" in METER or "practice" in METER
    assert "live_coach" in METER

    assert PANEL.count("tempo_mini.show_verdict(GameState.last_tempo_metrics") == 2
    assert 'name="TempoMini"' in TSCN

    print("tempo_mini_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Tempo mini readout: reuses MeterDisplay's grading bands, pops once per shot."""

from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
MINI = DIR.joinpath("tempo_mini.gd").read_text(encoding="utf-8")
PANEL = DIR.joinpath("shot_result_panel.gd").read_text(encoding="utf-8")
TSCN = DIR.joinpath("../../scenes/ui/shot_result_panel.tscn").read_text(encoding="utf-8")

BAND_PERFECT, BAND_GOOD = 0.50, 1.15  # TempoGrade / PuttStroke


def needle_color(abs_n: float) -> str:
    """Mirrors TempoMini._needle_color."""
    if abs_n <= BAND_PERFECT:
        return "green"
    if abs_n <= BAND_GOOD:
        return "yellow"
    return "red"


def main() -> int:
    # Verdict comes from the real measurement GameState already stored — no
    # new plumbing, no re-deriving shot_type/timing_scale.
    assert "GameState.last_tempo_metrics" in PANEL
    assert '"tolerance"' in MINI and '"target"' in MINI and '"ratio"' in MINI
    assert '"target_frac"' in MINI and '"actual_frac"' in MINI

    # Same grading bands as the swing-time meter, for both shot families.
    assert "TempoGrade.BAND_PERFECT" in MINI and "TempoGrade.BAND_GOOD" in MINI
    assert "PuttStroke.BAND_PERFECT" in MINI and "PuttStroke.BAND_GOOD" in MINI
    assert needle_color(0.3) == "green"
    assert needle_color(0.9) == "yellow"
    assert needle_color(1.5) == "red"

    # No title/verdict prose — Body label on the panel already says it in words.
    strip_fns = MINI.split("func _draw_ratio_strip")[1] + MINI.split("func _draw_amplitude_strip")[1]
    assert "Tempo ~" not in strip_fns
    assert "PRACTICE" not in MINI

    # Needle-only pop: track/band/tick draw unconditionally, only the needle
    # texture is transformed by the animated scale.
    assert "NEEDLE_POP_FROM" in MINI and "NEEDLE_POP_TO" in MINI
    assert "create_tween" in MINI and "tween_method(_set_needle_scale" in MINI
    assert "Vector2(ns, ns)" in MINI  # needle transform uses the tweened scale

    # Dedup guard: launch → final on the same putt verdict must not re-pop.
    assert "verdict == _last_verdict" in MINI and "return" in MINI.split("verdict == _last_verdict")[1][:40]

    # Legibility revision: needle drawn big enough for the source art's baked-in
    # outline/highlight to resolve at NEAREST-filter minification (was 18.0, crushed).
    assert "nd := 30.0" in MINI or "nd := 28.0" in MINI or "nd := 32.0" in MINI
    # Procedural dark-outline ring underneath the needle, not a title-text glow.
    assert "OUTLINE_COLOR" in MINI and "OUTLINE_SCALE" in MINI
    assert MINI.count("draw_texture(TEX_NEEDLE") == 2  # outline pass + graded-color pass
    # Good-zone band reads as a guide (stroke only), not a shape competing with the needle.
    assert MINI.count("OUTLINE_COLOR, false, 2.0)") == 2  # ratio strip + amplitude strip

    # Plain-language word next to the number, graded off the same tol as the band.
    assert "_verdict_word" in MINI
    assert '"Early"' in MINI and '"On time"' in MINI and '"Late"' in MINI

    # Wired into both result-screen entry points, keyed off report.lie.
    assert PANEL.count("tempo_mini.show_verdict(GameState.last_tempo_metrics") == 2
    assert 'report.lie == "Green"' in PANEL

    # Scene: sibling of Panel/Hint, not nested inside the VBox report box.
    assert 'name="TempoMini"' in TSCN
    assert 'script = ExtResource("3")' in TSCN
    assert TSCN.index('name="Panel"') < TSCN.index('name="TempoMini"') < TSCN.index('name="Hint"')

    print("tempo_mini_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

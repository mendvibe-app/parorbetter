#!/usr/bin/env python3
"""Scorecard: stroke-play card, hole-out reveal, game-over summary."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SC = (ROOT / "scripts/ui/scorecard.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
GO = (ROOT / "scripts/ui/game_over.gd").read_text(encoding="utf-8")


def main() -> None:
    assert "class_name ScoreCard" in SC
    assert "func populate" in SC
    assert "func reveal_hole" in SC
    assert "func reveal_all" in SC
    assert "func present_embedded" in SC
    assert "Scoring.result_from_diff" in SC
    assert "draw_arc" in SC or "draw_polyline" in SC
    assert "BIRDIE" in SC and "BOGEY" in SC

    assert "scorecard" in HC
    assert "reveal_hole" in HC
    assert "show_for_stroke_play" in HC
    assert "add_score_to_par(diff)" in HC
    # Reveal after score post
    holed = HC.split("func _on_holed_out")[1].split("func ")[0]
    assert "add_score_to_par" in holed
    assert "reveal_hole" in holed
    assert "is_stroke_play" in holed

    assert "ScoreCard" in GO
    assert "present_embedded" in GO
    assert "_hole_card_line" not in GO

    print("scorecard_check: ok")


if __name__ == "__main__":
    main()

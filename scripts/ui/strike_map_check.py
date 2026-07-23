#!/usr/bin/env python3
"""Strike map: dot from real measurement, category-consistent; cloud from stance only."""

from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
SM = DIR.joinpath("strike_map.gd").read_text(encoding="utf-8")
PANEL = DIR.joinpath("shot_result_panel.gd").read_text(encoding="utf-8")
REPORT = DIR.joinpath("../systems/shot_report.gd").read_text(encoding="utf-8")
TSCN = DIR.joinpath("../../scenes/ui/shot_result_panel.tscn").read_text(encoding="utf-8")

BAND_PERFECT, BAND_GOOD, BAND_THIN_FAT = 0.50, 1.15, 1.85  # TempoGrade / PuttStroke


def vertical_frac(err: float, tol: float) -> float:
    """Mirrors StrikeMap._vertical_frac metric path."""
    return max(-1.0, min(1.0, err / max(tol, 0.001) / BAND_THIN_FAT))


def category(err: float, tol: float) -> str:
    """Mirrors TempoGrade.grade / PuttStroke.grade banding."""
    n = abs(err) / max(tol, 0.001)
    if n <= BAND_PERFECT:
        return "perfect"
    if n <= BAND_GOOD:
        return "good"
    if n <= BAND_THIN_FAT:
        return "thin" if err > 0.0 else "fat"
    return "miss"


def main() -> int:
    # Dot y always agrees with the contact category by construction
    tol = 0.77  # full-swing tol at decent balance; any tol > 0 works
    for err_n in [0.0, 0.3, 0.49, 0.51, 1.1, 1.2, 1.8, 1.9, 5.0]:
        for sign in (1.0, -1.0):
            err = sign * err_n * tol
            y = vertical_frac(err, tol)
            cat = category(err, tol)
            if cat == "thin":
                assert y > BAND_GOOD / BAND_THIN_FAT  # above the GOOD zone, top half
            elif cat == "fat":
                assert y < -BAND_GOOD / BAND_THIN_FAT
            elif cat == "perfect":
                assert abs(y) <= BAND_PERFECT / BAND_THIN_FAT + 1e-9  # near center
            elif cat == "miss":
                assert abs(y) == 1.0  # clamped to the face edge
    # Sign convention: thin/long = top (+), fat/short = bottom (−)
    assert vertical_frac(1.0, tol) > 0.0 > vertical_frac(-1.0, tol)

    # Vertical position comes from the stored measurement, not fabricated
    assert "GameState.last_tempo_metrics" in SM
    assert '"actual_frac"' in SM and '"ratio"' in SM  # putt + full paths
    assert "TempoGrade.BAND_THIN_FAT" in SM

    # Cloud = repeatability from stance alone, fresh each shot, never stored
    assert "1.0 - clampf(report.stance" in SM
    assert "_ghosts.clear()" in SM
    scatter = lambda stance: (1.0 - stance)  # noqa: E731
    assert scatter(1.0) == 0.0 and scatter(0.0) > scatter(0.7)

    # Honesty: nothing textual drawn on the face (no toe/heel axis claims)
    assert "draw_string" not in SM

    # Pure gate matches the rest of the game (PERFECT + balance >= 0.72)
    assert "TempoGrade.PURE_BALANCE" in SM

    # Panel wires the map on both launch and final
    assert PANEL.count("strike_map.show_strike(report)") == 2
    assert "strike_map.gd" in TSCN and 'name="StrikeMap"' in TSCN

    # Dot replaced the prose — glance no longer prints contact/balance/line
    assert "Contact %s" not in REPORT.split("func glance_text")[1].split("func ")[0]
    assert "bal_word" not in REPORT.split("func glance_text")[1].split("func ")[0]

    print("strike_map_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

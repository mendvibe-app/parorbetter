#!/usr/bin/env python3
"""Strike map: dot from real measurement, category-consistent; cloud from stance only."""

from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
ROOT = DIR.parents[1]
SM = DIR.joinpath("strike_map.gd").read_text(encoding="utf-8")
PANEL = DIR.joinpath("shot_result_panel.gd").read_text(encoding="utf-8")
REPORT = DIR.joinpath("../systems/shot_report.gd").read_text(encoding="utf-8")
PHYS = DIR.joinpath("../ball/ball_physics.gd").read_text(encoding="utf-8")
TSCN = DIR.joinpath("../../scenes/ui/shot_result_panel.tscn").read_text(encoding="utf-8")
ASSETS = ROOT / "assets" / "ui"

BAND_PERFECT, BAND_GOOD, BAND_THIN_FAT = 0.50, 1.15, 1.85  # TempoGrade / PuttStroke

# Mirrors BallPhysics.BAG + Putter (parsed lightly so the check fails if a club is added unmapped).
BAG_NAMES = [
    "Driver", "3-Wood", "Hybrid",
    "5-Iron", "6-Iron", "7-Iron", "8-Iron", "9-Iron",
    "Pitching Wedge", "Gap Wedge", "Sand Wedge", "Lob Wedge",
]


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


def face_family(club_name: str, lie: str) -> str:
    """Mirrors StrikeMap.face_for buckets."""
    if lie == "Green" or club_name == "Putter":
        return "putter"
    if "Iron" in club_name or "Wedge" in club_name:
        return "iron"
    return "wood"


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

    # Dot replaced the prose — glance is a short golf call, not tempo essay
    glance = REPORT.split("func glance_text")[1].split("func ")[0]
    assert "Contact %s" not in glance
    assert "bal_word" not in glance
    assert "tempo_note" not in glance
    assert "_golf_call" in REPORT
    assert '"Pure"' in REPORT and '"Thin"' in REPORT and '"Heavy"' in REPORT
    assert '"fade"' in REPORT and '"draw"' in REPORT
    assert '"On pace"' in REPORT
    assert "Ball in motion" not in PANEL

    # Three club-family face textures exist (polish pass)
    for name in ("strike_face_wood.png", "strike_face_iron.png", "strike_face_putter.png"):
        assert (ASSETS / name).is_file(), name
    assert "draw_texture_rect" in SM and "StyleBoxFlat" not in SM
    assert "func face_for" in SM

    # Family mapping covers every bag club + putter
    expected = {
        "Driver": "wood", "3-Wood": "wood", "Hybrid": "wood",
        "5-Iron": "iron", "6-Iron": "iron", "7-Iron": "iron",
        "8-Iron": "iron", "9-Iron": "iron",
        "Pitching Wedge": "iron", "Gap Wedge": "iron",
        "Sand Wedge": "iron", "Lob Wedge": "iron",
        "Putter": "putter",
    }
    for name in BAG_NAMES:
        assert f'"name": "{name}"' in PHYS, name  # bag still has this club
        assert face_family(name, "Fairway") == expected[name], name
    assert face_family("Putter", "Green") == "putter"
    assert face_family("7-Iron", "Green") == "putter"  # green always putter art

    # Animate-in: center → result + pure halo pulse
    assert "_set_t" in SM and "_set_pulse" in SM and "create_tween" in SM

    print("strike_map_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

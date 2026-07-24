#!/usr/bin/env python3
"""Assert Crunchy Pixel style docs + references + course/UI assets exist."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STYLE = (ROOT / "art" / "STYLE.md").read_text(encoding="utf-8")


def main() -> int:
    assert "# Art Style Skill: Crunchy Pixel" in STYLE
    assert "art/references/" in STYLE
    assert "All visual assets" in STYLE
    for name in (
        "ref_fairway.png",
        "ref_rough_a.png",
        "ref_rough_b.png",
        "ref_water.png",
        "ref_sand.png",
    ):
        assert (ROOT / "art" / "references" / name).is_file(), name
    for name in (
        "fairway_tile_a.png",
        "rough_tile_a.png",
        "rough_tile_b.png",
        "water_tile.png",
    ):
        assert (ROOT / "assets" / "terrain" / name).is_file(), name
    for name in ("bunker_blob.png", "bunker_crescent.png", "bunker_cluster.png", "water_creek.png", "water_pond.png"):
        assert (ROOT / "assets" / "hazards" / name).is_file(), name
    for name in (
        "ui_tempo_landmark_start.png",
        "ui_tempo_lane.png",
        "ui_putt_landmark_start.png",
        "ui_putt_lane.png",
        "ui_tempo_meter_track.png",
        "strike_face_iron.png",
        "club_driver.png",
        "lie_fairway.png",
    ):
        assert (ROOT / "assets" / "ui" / name).is_file(), name
    assert (ROOT / "assets" / "ball" / "ball.png").is_file()
    theme_path = ROOT / "assets" / "ui" / "game_theme.tres"
    assert theme_path.is_file()
    theme = theme_path.read_text(encoding="utf-8")
    assert "PanelContainer/styles/panel" in theme
    assert "Button/styles/normal" in theme
    assert "Crunchy Pixel" in (ROOT / "art" / "prompts" / "terrain.md").read_text(encoding="utf-8")
    print("crunchy_pixel_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

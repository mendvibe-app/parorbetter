#!/usr/bin/env python3
"""Hole-kit contracts: lie follows paint, thin creeks, no island, trusted dunks."""
from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
DATA = DIR.joinpath("hole_data.gd").read_text(encoding="utf-8")
CTRL = DIR.joinpath("hole_controller.gd").read_text(encoding="utf-8")
GEN = DIR.joinpath("hole_generator.gd").read_text(encoding="utf-8")
BALL = DIR.joinpath("../ball/ball.gd").read_text(encoding="utf-8")


def _fn(src: str, name: str) -> str:
    token = f"func {name}"
    i = src.find(token)
    assert i >= 0, name
    rest = src[i + len(token) :]
    nxt = rest.find("\nfunc ")
    return rest if nxt < 0 else rest[:nxt]


def main() -> int:
    for token in (
        "rough / first-cut / fairway / collar / green",
        "ROLE_SIDE_LAKE",
        "BUNKER_GREEN_COLLAR_PX := 8.0",
        "first_cut_left",
        "first_cut_right",
        "apron_plate_scale",
        "water_neighbor_side",
        "func bunker_hits_dilated_green",
        "func bunker_on_water_neighbor_side",
    ):
        assert token in DATA, token

    assert "0 = that side DIES" in DATA or "side DIES" in DATA

    assert "first_cut_left" in CTRL
    assert "apron_plate_scale" in CTRL
    assert "func _first_cut_side_width" in CTRL
    assert "TEX_ROUGH" in _fn(CTRL, "_add_green_apron")
    assert "d.first_cut_left" in GEN
    assert "d.apron_plate_scale" in GEN

    def hits(bc, br, gc, rx, ry, collar=8.0) -> bool:
        erx = max(rx, 1.0) + collar + br
        ery = max(ry, 1.0) + collar + br
        dx = (bc[0] - gc[0]) / erx
        dy = (bc[1] - gc[1]) / ery
        return dx * dx + dy * dy <= 1.0

    assert hits((540.0, -80.0), 20.0, (540.0, -80.0), 36.0, 36.0)
    assert not hits((540.0 + 80.0, -80.0), 20.0, (540.0, -80.0), 36.0, 36.0)

    assert "func _make_bunker_lobes" in CTRL
    assert "TEX_BUNKER_GRAIN" in CTRL
    assert "func _place_side_lake" in CTRL
    assert "for water_pass in [true, false]" in CTRL
    assert "ROLE_SIDE_LAKE" in CTRL
    assert "CARRY_HALF_W_MAX := 6.0" in CTRL

    # Lie follows painted cuts, not the old fairway tube.
    lie = _fn(CTRL, "_classify_lie")
    assert "fairway_half + 20.0" not in lie
    assert "_fairway_poly" in lie
    assert "_first_cut_poly" in lie
    assert "_apron_poly" in lie
    assert "_water_polys" in lie
    assert "func _point_in_cut" in CTRL

    # Island ring never emitted from the randomizer.
    assert "Island ring retired from randomizer" in GEN
    assert '_haz("water", HoleData.ROLE_ISLAND_RING' not in GEN
    assert "Island layout retired from the randomizer" in GEN

    # Thin creek lock (5–15 ft), not rivers.
    assert "lerpf(9.0, 14.0, t)" in GEN
    water_fn = _fn(CTRL, "_add_water_poly")
    assert "RectangleShape2D" not in water_fn
    assert "never AABB" in water_fn
    assert "texture_rotation = 0.0" in water_fn
    assert "GROUND_TILE_PX" in water_fn

    # Side-lake peels behind the green (playtest: water band as par-3 backdrop).
    lake = _fn(CTRL, "_place_side_lake")
    assert "/ 160.0" in lake
    assert "WATER_OFFSCREEN * 1.35" in lake  # far bank still off-screen
    assert "ease_top_y := GREEN_Y + 120.0" not in lake

    # Trees: stamp center on land (canopy may overhang the bank).
    trees = _fn(CTRL, "_place_tree_group")
    assert "_bunker_hits_water(try_c, TREE_WATER_PAD)" in trees
    assert "canopy := r * 1.15" not in trees
    assert "for dy in" in trees

    # No forced water on peninsula / island_green (repeating par-3 combo).
    assert "peninsula art no longer forces" in GEN or "Island layout retired — peninsula art" in GEN
    assert 'do not force water' in GEN
    assert "last_water" in _fn(GEN, "_build_hazards")
    assert "func _water_role" in GEN
    assert "func _spread_par" in GEN
    assert "not a par-3 front nine" in GEN

    cut = _fn(CTRL, "_place_water_cut")
    assert "_add_water_poly(pts)" in cut
    assert "_shore_polyline" not in cut

    # Specced sand always stamps.
    bunker = _fn(CTRL, "_add_bunker")
    assert "specced sand always stamps" in bunker
    assert 'push_warning("skip bunker' not in bunker

    # Shore lip is not wet. Chip settle hitchhiker stayed reverted.
    shore = _fn(CTRL, "_add_shore_sprite")
    assert 'add_to_group("water")' not in shore
    assert 'or _shot_type == "chip"' not in BALL

    print("hole_kit_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

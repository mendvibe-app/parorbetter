#!/usr/bin/env python3
"""Trees are designed hole hazards (generator specs + collision + Trees lie)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = (ROOT / "scripts/course/hole_data.gd").read_text(encoding="utf-8")
GEN = (ROOT / "scripts/course/hole_generator.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
BALL = (ROOT / "scripts/ball/ball.gd").read_text(encoding="utf-8")
PHYS = (ROOT / "scripts/ball/ball_physics.gd").read_text(encoding="utf-8")


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("func has_trees" in DATA, "has_trees")
must("kind=sand|water|tree" in DATA or "tree" in DATA, "tree kind documented")
must("func _build_trees" in GEN, "_build_trees")
must("_haz_tree" in GEN, "_haz_tree")
must('"trees"' in GEN, "archetype trees weight")
must("_build_trees(" in GEN, "trees merged into hole")
must("func _place_tree_group" in CTRL, "_place_tree_group")
must("func _add_tree" in CTRL, "_add_tree")
must('add_to_group("tree")' in CTRL or ', "tree")' in CTRL, "tree collision group")
must("_scatter_trees" not in CTRL, "decorative scatter removed")
must('is_in_group("tree")' in BALL, "ball hits trees")
must('"Trees"' in BALL and '"Trees"' in PHYS, "Trees lie")
must("lie == \"Trees\"" in PHYS or 'lie == "Trees"' in PHYS, "trees club gate")
must("return 0.58" in PHYS, "trees distance mult")
# Trees must not stamp into bunkers (playtest: canopy mid-sand).
must("func _clears_bunkers" in CTRL, "_clears_bunkers")
must("_clears_bunkers(" in CTRL, "tree place checks bunkers")
must("BUNKER_TREE_PAD" in CTRL, "bunker-tree pad")
must("_bunker_hits_water(try_c, TREE_WATER_PAD)" in CTRL, "tree water test is stamp center, not canopy")
must("canopy := r * 1.15" not in CTRL, "do not require dry canopy")
must("for dy in" in CTRL, "tree along-nudge off creek")


def clears_bunkers(center, radius, bunkers, pad=6.0) -> bool:
    for c, r in bunkers:
        if (center[0] - c[0]) ** 2 + (center[1] - c[1]) ** 2 < (r + radius + pad) ** 2:
            return False
    return True


bunkers = [((650.0, 380.0), 40.0)]
must(not clears_bunkers((650.0, 380.0), 20.0, bunkers), "tree in bunker blocked")
must(not clears_bunkers((690.0, 380.0), 20.0, bunkers), "tree lip blocked")
must(clears_bunkers((750.0, 380.0), 20.0, bunkers), "tree clear of bunker")
print("tree_hazard_check: OK")

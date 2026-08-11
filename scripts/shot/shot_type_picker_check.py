#!/usr/bin/env python3
"""Contract: manual shot-type picker + eligibility + carry/rest aim marks."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
TG = (ROOT / "scripts" / "shot" / "tempo_grade.gd").read_text(encoding="utf-8")
SR = (ROOT / "scripts" / "shot" / "shot_routine.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")


def _bag_max(name: str) -> float:
    m = re.search(rf'{{"name": "{re.escape(name)}", "max_yards": ([0-9.]+)', PHYS)
    assert m, name
    return float(m.group(1))


def eligible(club_max: float) -> list[str]:
    types = ["full"]
    if club_max <= 0:
        return types
    if club_max <= _bag_max("7-Iron"):
        types.append("chip")
    if club_max <= _bag_max("Pitching Wedge"):
        types.append("pitch")
    if club_max <= _bag_max("Sand Wedge") + 0.01:
        types.append("flop")
    return types


def main() -> int:
    assert "static func eligible_shot_types" in PHYS
    assert "static func _bag_max_yards" in PHYS
    assert "flop" in PHYS.split("func eligible_shot_types")[1][:800]
    assert "Sand Wedge" in PHYS and "Lob Wedge" in PHYS and "Gap Wedge" in PHYS
    assert "static func recommend_shot_type" in TG
    assert "return shot_type_for" in TG
    assert "TOL_FLOP" in TG
    assert "p_shot_type_override" in SR
    assert "eligible_shot_types" in SR
    assert "FLOP_MAX_YD" in SR or "flop" in SR
    assert "_chosen_shot_type" in HC
    assert "_shot_type_row" in HC
    assert "_recommended_shot_type" in HC
    assert "_aim_carry_land_point" in HC
    assert "_aim_land_mark" in HC
    assert "_aim_roll_line" in HC
    assert "_setup_shot_type_row" in HC
    assert "p_shot_type_override" in HC or "type_override" in HC
    assert "Flop" in HC
    # Vertical column — no horizontal side-clip on 4 types.
    assert "VBoxContainer" in HC
    assert "_shot_type_col_height" in HC
    assert "_SHOT_TYPE_COL_W" in HC
    assert "SIZE_EXPAND_FILL" in HC

    assert eligible(260.0) == ["full"]
    assert eligible(175.0) == ["full"]  # 6-Iron
    assert eligible(160.0) == ["full", "chip"]  # 7-Iron
    assert eligible(130.0) == ["full", "chip"]  # 9-Iron
    assert eligible(110.0) == ["full", "chip", "pitch"]  # PW — no flop
    assert eligible(95.0) == ["full", "chip", "pitch"]  # GW — no flop
    assert eligible(80.0) == ["full", "chip", "pitch", "flop"]  # SW
    assert eligible(65.0) == ["full", "chip", "pitch", "flop"]  # LW
    assert "flop" not in eligible(95.0)

    # Phase 4 guide familiarity — shared fade, path unchanged
    GS = (ROOT / "scripts" / "autoload" / "game_state.gd").read_text(encoding="utf-8")
    assert "get_shot_type_form" in GS
    assert "record_shot_type_rep" in GS
    assert "func guide_alpha_for_shot_type" in GS
    assert "func survival_guide_form" in GS
    assert "SHOT_TYPE_GUIDE_REPS" in GS
    GEST = (ROOT / "scripts" / "shot" / "tempo_gesture.gd").read_text(encoding="utf-8")
    assert "guide_alpha_for_shot_type" in GEST
    assert "form * 1.35" not in GEST

    print("shot_type_picker_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

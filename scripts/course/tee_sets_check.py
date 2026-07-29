#!/usr/bin/env python3
"""Contract: Blue/White/Red tees + progress-based active set."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = (ROOT / "scripts/course/hole_data.gd").read_text(encoding="utf-8")
GEN = (ROOT / "scripts/course/hole_generator.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")
GS = (ROOT / "scripts/autoload/game_state.gd").read_text(encoding="utf-8")
HUD = (ROOT / "scripts/ui/hud.gd").read_text(encoding="utf-8")


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("enum TeeSet" in DATA, "TeeSet enum")
must("tee_blue_offset_yd" in DATA and "tee_red_offset_yd" in DATA, "tee offsets")
must("func tee_yards" in DATA, "tee_yards")
must("func active_tee_set_for_hole" in GS, "active_tee_set_for_hole")
must("t < 0.33" in GS and "t < 0.66" in GS, "progress thresholds")
must("func _setup_tee_positions" in CTRL, "_setup_tee_positions")
must("func _add_tee_boxes" in CTRL, "_add_tee_boxes")
must("_tee_back_pos" in CTRL, "fairway uses back tee")
must("tee_blue_offset_yd" in GEN, "generator sets offsets")
must("tee_set_label" in HUD or "tee_yards" in HUD, "HUD shows active tee yardage")

# Yardage order helper (mirror tee_yards defaults)
def tee_yd(white: float, blue_off: float, red_off: float, set_name: str) -> float:
    if set_name == "BLUE":
        return max(white + blue_off, 60.0)
    if set_name == "RED":
        return max(white + red_off, 50.0)
    return max(white, 50.0)


w, b, r = 400.0, 20.0, -18.0
assert tee_yd(w, b, r, "BLUE") > tee_yd(w, b, r, "WHITE") > tee_yd(w, b, r, "RED")

# Progress bands: hole 1 t=0 → Red; mid t≈0.25 still Red; late Blue
# difficulty_t = u^2, u=(n-1)/(N-1)
def t(n: int, N: int = 18) -> float:
    u = (n - 1) / max(N - 1, 1)
    return u * u


assert t(1) < 0.33
assert t(9) < 0.66  # u=8/17≈0.47, t≈0.22 → Red
assert t(14) >= 0.33  # u=13/17≈0.76, t≈0.58 → White
assert t(18) >= 0.66  # u=1, t=1 → Blue

print("tee_sets_check: OK")

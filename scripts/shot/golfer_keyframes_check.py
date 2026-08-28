#!/usr/bin/env python3
"""Contract: 8 golfer keyframes + blend helpers in tempo_gesture."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TG = (ROOT / "scripts/shot/tempo_gesture.gd").read_text(encoding="utf-8")
UI = ROOT / "assets/ui"

KEYS = ["address", "takeaway", "mid", "late", "top", "early_down", "impact", "follow"]
PREFIXES = ["ui_golfer_", "ui_golfer_putt_", "ui_golfer_chip_"]


def must(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


must("func _golfer_keyframes" in TG, "_golfer_keyframes")
must("func _golfer_blend_strip" in TG, "_golfer_blend_strip")
must("round(x)" in TG.split("func _golfer_blend_strip")[1].split("func ")[0], "snap not crossfade")
must("GOLFER_COL_FRAC" in TG, "golfer column")
must("func _lane_x" in TG, "_lane_x")
must("func _is_left_handed" in TG, "handedness")
must("TEX_GOLFER_TAKEAWAY" in TG and "TEX_GOLFER_LATE" in TG, "full intermediate consts")
must("TEX_GOLFER_EARLY_DOWN" in TG, "early_down const")
must("TEX_GOLFER_PUTT_TAKEAWAY" in TG and "TEX_GOLFER_CHIP_LATE" in TG, "putt/chip intermediates")
must("func _uses_chip_golfer" in TG, "pitch uses chip golfer set")
must("shot_type == \"pitch\"" in TG or 'shot_type == "pitch"' in TG, "pitch branch")


def snap_index(n: int, t01: float) -> int:
    """Mirrors TempoGesture._golfer_blend_strip nearest-frame pick."""
    x = max(0.0, min(1.0, t01)) * float(n - 1)
    return max(0, min(n - 1, int(round(x))))


must(snap_index(5, 0.0) == 0, "backswing start = address")
must(snap_index(5, 1.0) == 4, "backswing end = top")
must(snap_index(5, 0.5) == 2, "backswing mid")
must(snap_index(3, 0.0) == 0, "downswing start = top")
must(snap_index(3, 1.0) == 2, "downswing end = impact")


for pre in PREFIXES:
    for k in KEYS:
        p = UI / f"{pre}{k}.png"
        must(p.exists(), f"missing {p.name}")

print("golfer_keyframes_check: OK")

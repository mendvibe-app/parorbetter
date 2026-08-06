#!/usr/bin/env python3
"""Contact-quality haptics: Haptics autoload, init at boot, impact mapping."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJ = (ROOT / "project.godot").read_text(encoding="utf-8")
MAIN = (ROOT / "scripts/main.gd").read_text(encoding="utf-8")
ROUTINE = (ROOT / "scripts/shot/shot_routine.gd").read_text(encoding="utf-8")
HAPT = (ROOT / "scripts/autoload/haptics.gd").read_text(encoding="utf-8")
DBG = (ROOT / "scripts/debug/debug_controls.gd").read_text(encoding="utf-8")


def main() -> None:
    assert 'Haptics="*res://scripts/autoload/haptics.gd"' in PROJ or "haptics.gd" in PROJ
    assert "func init" in HAPT
    assert "func light" in HAPT and "func medium" in HAPT and "func heavy" in HAPT
    assert "Haptics.init()" in MAIN
    assert "func _haptic_impact" in ROUTINE
    assert "Haptics.light()" in ROUTINE or "_haptic_light" in ROUTINE
    assert "Haptics.medium()" in ROUTINE or "_haptic_medium" in ROUTINE
    assert "Haptics.heavy()" in ROUTINE or "_haptic_heavy" in ROUTINE
    # MISS double-pulse must not block the shot pipeline with await
    impact = ROUTINE.split("func _haptic_impact")[1].split("func ")[0]
    assert "create_timer(0.09)" in impact
    assert "await " not in impact
    # Duration fallback still present for desktop
    assert "vibrate_handheld" in ROUTINE
    assert "HapticSmokeBtn" in DBG or "Haptic medium" in DBG
    # Plugin artifacts staged for custom Android/iOS builds
    assert (ROOT / "android/plugins/Haptics.gdap").is_file()
    assert (ROOT / "android/plugins/haptics-release.aar").is_file()
    assert (ROOT / "ios/plugins/haptics/haptics.gdip").is_file()
    print("haptics_check: ok")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Contract check for concurrent shot resolve — fails if the model drifts."""
from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).parent
SRC = DIR.joinpath("shot_routine.gd").read_text(encoding="utf-8")
PS = DIR.joinpath("power_stance.gd").read_text(encoding="utf-8")
SW = DIR.joinpath("swing_contact.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "enum Phase { IDLE, ACTIVE, DONE }" in SRC, "expected merged ACTIVE phase"
    assert "Phase.POWER" not in SRC and "Phase.SWING" not in SRC, "POWER/SWING phases must be gone"
    assert "_on_power_committed" not in SRC, "power commit must not resolve the shot"
    assert re.search(
        r"_on_swing_committed[\s\S]*?_power = power_stance\.power", SRC
    ), "impact must sample live power"
    assert re.search(
        r"_on_swing_committed[\s\S]*?_stability = power_stance\.stability", SRC
    ), "impact must sample live stability"
    assert "swing_contact.set_enabled(true)" in SRC, "swing must start enabled with power"
    assert "func _emit_result" in SRC
    assert SRC.index("power_stance.set_enabled(false)") > SRC.index("func _emit_result")

    # Soft early-release
    assert "balance_broken" in PS
    assert "EARLY_RELEASE_STAB_MUL" in PS and "EARLY_RELEASE_STAB_CEIL" in PS
    assert "_on_power_released" in SRC
    assert "Phase.ACTIVE" in SRC

    # Space/Enter: power key-match must not commit; swing must still own them
    key_block = PS.split("match event.physical_keycode:")[1].split("return")[0]
    assert "KEY_SPACE" not in key_block, "Space must not commit power"
    assert "KEY_ENTER" not in key_block, "Enter must not commit power"
    assert "KEY_SPACE" in SW and "confirm_shot" in SW, "swing must own Space/confirm_shot"

    print("shot_concurrent_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

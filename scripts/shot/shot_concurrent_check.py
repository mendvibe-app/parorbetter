#!/usr/bin/env python3
"""Contract check for concurrent shot resolve — fails if the model drifts."""
from __future__ import annotations

import re
import sys
from pathlib import Path

SRC = Path(__file__).with_name("shot_routine.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "enum Phase { IDLE, ACTIVE, DONE }" in SRC, "expected merged ACTIVE phase"
    assert "Phase.POWER" not in SRC and "Phase.SWING" not in SRC, "POWER/SWING phases must be gone"
    assert "_on_power_committed" not in SRC, "power commit must not resolve the shot"
    assert "power_stance.committed.connect" not in SRC, "must not wire power commit as resolver"
    assert re.search(
        r"_on_swing_committed[\s\S]*?_power = power_stance\.power", SRC
    ), "impact must sample live power"
    assert re.search(
        r"_on_swing_committed[\s\S]*?_stability = power_stance\.stability", SRC
    ), "impact must sample live stability"
    assert "swing_contact.set_enabled(true)" in SRC, "swing must start enabled with power"
    assert "power_stance.set_enabled(false)\n\tswing_contact.set_enabled(false)" in SRC.replace(
        "\r\n", "\n"
    ) or (
        "power_stance.set_enabled(false)" in SRC
        and SRC.index("power_stance.set_enabled(false)")
        > SRC.index("func _emit_result")
    ), "both controls disable only at emit"
    print("shot_concurrent_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

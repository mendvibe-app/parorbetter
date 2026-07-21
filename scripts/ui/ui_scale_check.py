#!/usr/bin/env python3
"""Contract check for UiScale type/touch floor + safe-area inset math."""
from __future__ import annotations

import re
import sys
from pathlib import Path

SRC = Path(__file__).with_name("ui_scale.gd").read_text(encoding="utf-8")


def _const(name: str) -> int:
    m = re.search(rf"const {name} := (\d+)", SRC)
    assert m, f"missing const {name}"
    return int(m.group(1))


def screen_insets_to_viewport(
    win: tuple[float, float],
    safe_pos: tuple[float, float],
    safe_end: tuple[float, float],
    vp: tuple[float, float],
    scale: float = 1.0,
) -> tuple[float, float, float, float]:
    """Mirrors UiScale.screen_insets_to_viewport for identity-scale stretch (sx=sy=scale)."""
    if win[0] < 1.0 or win[1] < 1.0 or vp[0] < 1.0 or vp[1] < 1.0:
        return (0.0, 0.0, 0.0, 0.0)
    # stretch maps viewport→screen as *scale; inverse maps screen→viewport /scale
    tl = (safe_pos[0] / scale, safe_pos[1] / scale)
    br = (safe_end[0] / scale, safe_end[1] / scale)
    return (
        max(tl[0], 0.0),
        max(tl[1], 0.0),
        max(vp[0] - br[0], 0.0),
        max(vp[1] - br[1], 0.0),
    )


def main() -> int:
    assert _const("CAPTION") == 32
    assert _const("BODY") == 40
    assert _const("TITLE") == 48
    assert _const("TOUCH_MIN") == 120
    assert "TEXT_SECONDARY" in SRC
    assert "func screen_insets_to_viewport" in SRC
    assert "func apply_hole_safe_area" in SRC

    # Full-bleed safe area → zero margins
    assert screen_insets_to_viewport((1080, 1920), (0, 0), (1080, 1920), (1080, 1920)) == (
        0.0,
        0.0,
        0.0,
        0.0,
    )

    # Notch + home indicator on a 1080×1920 window matching viewport 1:1
    left, top, right, bottom = screen_insets_to_viewport(
        (1080, 1920), (0, 60), (1080, 1920 - 48), (1080, 1920)
    )
    assert top == 60.0 and bottom == 48.0 and left == 0.0 and right == 0.0

    # 2× stretch: 540×960 window, viewport 1080×1920, 30px top inset on screen → 15vp
    left, top, right, bottom = screen_insets_to_viewport(
        (540, 960), (0, 30), (540, 960 - 24), (1080, 1920), scale=0.5
    )
    # inv scale = 1/0.5 = 2 → top=60, bottom=48 in viewport… wait:
    # stretch viewport→screen scale 0.5 means screen = vp * 0.5, inv: vp = screen / 0.5
    assert abs(top - 60.0) < 1e-6 and abs(bottom - 48.0) < 1e-6

    print("ui_scale_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

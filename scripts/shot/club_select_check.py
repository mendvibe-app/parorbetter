#!/usr/bin/env python3
"""Club select: full-bag scroll must receive drags (PASS), not eat them (STOP)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "scripts/shot/club_select.gd").read_text(encoding="utf-8")
CTRL = (ROOT / "scripts/course/hole_controller.gd").read_text(encoding="utf-8")


def main() -> int:
    assert "MOUSE_FILTER_PASS" in SRC, "club rows must PASS so ScrollContainer gets drag"
    assert "SCROLL_MODE_SHOW_ALWAYS" in SRC, "scrollbar affordance for desktop"
    assert "_on_scroll_gui_input" in SRC, "owned drag-scroll handler"
    assert "DRAG_DEADZONE" in SRC, "tap vs drag threshold"
    assert "_on_row_pressed" in SRC, "ignore select after scroll drag"
    assert "view_h - 48.0" in SRC or "view_h - 48" in SRC, "panel capped to viewport"
    assert "move_child(_club_select, -1)" in CTRL, "club select modal on top of UI layer"
    print("club_select_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

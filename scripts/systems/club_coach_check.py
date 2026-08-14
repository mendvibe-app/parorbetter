#!/usr/bin/env python3
"""ClubCoachLog contracts — schema wipe so pre–flight-rebuild history is discarded."""
from __future__ import annotations

from pathlib import Path

SRC = Path(__file__).with_name("club_coach_log.gd").read_text(encoding="utf-8")
GS = Path(__file__).resolve().parents[1].joinpath("autoload/game_state.gd").read_text(
    encoding="utf-8"
)


def main() -> int:
    assert "const SCHEMA_VERSION" in SRC
    assert "SCHEMA_VERSION := 2" in SRC or "SCHEMA_VERSION:=2" in SRC
    assert 'META_SECTION := "_meta"' in SRC or 'META_SECTION:="_meta"' in SRC
    assert "func clear_data" in SRC
    assert "func load_data" in SRC
    assert "func save_data" in SRC
    load_fn = SRC.split("func load_data")[1].split("func ")[0]
    assert "schema_version" in load_fn
    assert "clear_data()" in load_fn
    assert "SCHEMA_VERSION" in load_fn
    save_fn = SRC.split("func save_data")[1].split("func ")[0]
    assert "schema_version" in save_fn
    assert "META_SECTION" in save_fn
    # Coach persists across runs — must not clear inside reset_run.
    reset_fn = GS.split("func reset_run")[1].split("func ")[0]
    assert "club_coach" not in reset_fn or "clear_data" not in reset_fn
    assert "club_coach.load_data()" in GS
    print("club_coach_check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

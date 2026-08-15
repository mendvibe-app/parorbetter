#!/usr/bin/env python3
"""ClubCoachLog contracts — schema wipe + dual tip priority (coach vs select)."""
from __future__ import annotations

from pathlib import Path

DIR = Path(__file__).resolve().parent
SRC = (DIR / "club_coach_log.gd").read_text(encoding="utf-8")
GS = DIR.parents[0].joinpath("autoload/game_state.gd").read_text(encoding="utf-8")
CLUB_SELECT = DIR.parents[0].joinpath("shot/club_select.gd").read_text(encoding="utf-8")
COACH_SCREEN = DIR.parents[0].joinpath("ui/coach_screen.gd").read_text(encoding="utf-8")

TEMPO_THRESHOLD = 0.35
PATH_THRESHOLD = 0.25
CONTACT_MISS_FRACTION = 0.40
MIN_SAMPLES = 5
# ShotResult.ContactQuality
THIN, FAT, MISS = 2, 3, 4


def avg(arr: list) -> float:
    if not arr:
        return 0.0
    return sum(float(v) for v in arr) / len(arr)


def tip_tempo(stats: dict) -> dict | None:
    t = avg(stats.get("tempo_err_history", []))
    if t <= -TEMPO_THRESHOLD:
        return {"tag": "rushed_transition"}
    if t >= TEMPO_THRESHOLD:
        return {"tag": "lingering_top"}
    return None


def tip_path(stats: dict) -> dict | None:
    p = avg(stats.get("path_error_history", []))
    if p >= PATH_THRESHOLD:
        return {"tag": "slice_tendency"}
    if p <= -PATH_THRESHOLD:
        return {"tag": "hook_tendency"}
    return None


def tip_contact(stats: dict) -> dict | None:
    tally = stats.get("contact_tally", {})
    lifetime = sum(int(v) for v in tally.values())
    bad = sum(int(tally.get(k, 0)) for k in (THIN, FAT, MISS))
    if lifetime > 0 and bad / lifetime > CONTACT_MISS_FRACTION:
        return {"tag": "contact_issue"}
    return None


def resolve_tip(stats: dict, mode: str = "coach") -> dict:
    if int(stats.get("shots_logged", 0)) < MIN_SAMPLES:
        return {"tag": "insufficient_data"}
    order = (
        (tip_path, tip_contact, tip_tempo)
        if mode == "select"
        else (tip_tempo, tip_path, tip_contact)
    )
    for fn in order:
        hit = fn(stats)
        if hit:
            return hit
    return {"tag": "on_track"}


def main() -> int:
    assert "const SCHEMA_VERSION" in SRC
    assert "SCHEMA_VERSION := 3" in SRC or "SCHEMA_VERSION:=3" in SRC
    assert "func clear_data" in SRC
    load_fn = SRC.split("func load_data")[1].split("func ")[0]
    assert "schema_version" in load_fn and "clear_data()" in load_fn
    reset_fn = GS.split("func reset_run")[1].split("func ")[0]
    assert "clear_data" not in reset_fn or "club_coach" not in reset_fn
    assert "club_coach.load_data()" in GS

    # Dual-mode resolve
    assert 'mode: String = "coach"' in SRC or 'mode := "coach"' in SRC or 'mode: String = "coach"' in SRC
    assert "func _tip_tempo" in SRC and "func _tip_path" in SRC and "func _tip_contact" in SRC
    resolve_fn = SRC.split("static func resolve_tip")[1].split("static func _tip_tempo")[0]
    assert 'mode == "select"' in resolve_fn
    # Select order: path before tempo
    select_branch = resolve_fn.split('mode == "select"')[1].split("else:")[0]
    assert "_tip_path" in select_branch
    assert select_branch.find("_tip_path") < select_branch.find("_tip_tempo")
    # Coach (else): tempo before path
    else_branch = resolve_fn.split("else:")[1]
    assert else_branch.find("_tip_tempo") < else_branch.find("_tip_path")

    assert 'resolve_tip(stats, "select")' in CLUB_SELECT
    assert "resolve_tip(stats)" in COACH_SCREEN  # default coach mode

    # Synthetic: rushed tempo + slice path
    stats = {
        "shots_logged": 10,
        "tempo_err_history": [-0.5] * 8,
        "path_error_history": [0.4] * 8,
        "contact_tally": {1: 8},  # GOOD
    }
    assert resolve_tip(stats, "coach")["tag"] == "rushed_transition"
    assert resolve_tip(stats, "select")["tag"] == "slice_tendency"
    # Select falls through to tempo when path/contact clean
    clean_path = {
        "shots_logged": 10,
        "tempo_err_history": [-0.5] * 8,
        "path_error_history": [0.0] * 8,
        "contact_tally": {1: 8},
    }
    assert resolve_tip(clean_path, "select")["tag"] == "rushed_transition"
    assert resolve_tip({"shots_logged": 2}, "coach")["tag"] == "insufficient_data"

    print("club_coach_check: ok (schema + coach/select tip priority)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Contract check for tempo-ratio swing — fails if the anti-arcade rules drift."""
from __future__ import annotations

import sys
from pathlib import Path

DIR = Path(__file__).parent
GRADE = DIR.joinpath("tempo_grade.gd").read_text(encoding="utf-8")
GESTURE = DIR.joinpath("tempo_gesture.gd").read_text(encoding="utf-8")
ROUTINE = DIR.joinpath("shot_routine.gd").read_text(encoding="utf-8")
REPORT = DIR.joinpath("../systems/shot_report.gd").read_text(encoding="utf-8")
METER = DIR.joinpath("meter_display.gd").read_text(encoding="utf-8")

TARGET_FULL = 3.0
TARGET_SHORT = 2.0
TOL_FULL = 1.1
TOL_SHORT = 0.85
BAND_PERFECT = 0.50
BAND_GOOD = 1.15
BAND_THIN_FAT = 1.85
PURE_BALANCE = 0.72
CHIP_YD = 50.0
CHIP_POWER_CAP = 0.42


def shot_type_for(lie: str, remaining_yd: float, club_max_yards: float = 0.0) -> str:
    if lie == "Green":
        return "putt"
    gate = CHIP_YD
    if club_max_yards > 1.0:
        gate = min(CHIP_YD, club_max_yards * CHIP_POWER_CAP)
    if remaining_yd < gate:
        return "chip"
    return "full"


def ratio(t_takeaway: float, t_top: float, t_impact: float) -> float:
    bs = t_top - t_takeaway
    ds = t_impact - t_top
    if ds <= 0.001:
        return 99.0
    if bs <= 0.0:
        return 0.0
    return bs / ds


def balance(sample: dict, tighten: float = 1.0, shot_type: str = "full") -> float:
    t = max(tighten, 0.0)
    accel = float(sample.get("max_accel", 0.0))
    jerk = float(sample.get("max_jerk", 0.0))
    bs_len = float(sample.get("backswing_len", 0.0))
    ft_len = float(sample.get("follow_through_len", 0.0))
    incomplete = bool(sample.get("incomplete", False))
    short_game = shot_type in ("putt", "chip")
    bs_floor = 0.10 if short_game else 0.18
    ft_floor = 0.04 if short_game else 0.08
    accel_pen = min(max((accel - 8.0) / 24.0, 0.0), 1.0) * t
    jerk_pen = min(max((jerk - 0.6) / 1.4, 0.0), 1.0) * t
    short_bs = min(max((bs_floor - bs_len) / bs_floor, 0.0), 1.0)
    short_ft = 0.0 if incomplete else min(max((ft_floor - ft_len) / ft_floor, 0.0), 1.0)
    incomplete_pen = ((0.30 if short_game else 0.55) if incomplete else 0.0)
    pen = accel_pen * 0.35 + jerk_pen * 0.30 + short_bs * 0.20 + short_ft * 0.15 + incomplete_pen
    return min(max(1.0 - pen, 0.0), 1.0)


def tolerance_width(shot_type: str, bal: float, timing_scale: float = 1.0, tol_scale: float = 1.0) -> float:
    base_tol = TOL_SHORT if shot_type in ("putt", "chip") else TOL_FULL
    base = base_tol * max(tol_scale, 0.15) * max(timing_scale, 0.35)
    shrink = 0.35 + (1.0 - 0.35) * min(max(bal, 0.0), 1.0)
    return base * shrink


def grade(sample: dict, shot_type: str, timing_scale: float = 1.0, tol_scale: float = 1.0, bal_tighten: float = 1.0) -> dict:
    target = TARGET_SHORT if shot_type in ("putt", "chip") else TARGET_FULL
    bal = balance(sample, bal_tighten, shot_type)
    r = ratio(sample["t_takeaway"], sample["t_top"], sample["t_impact"])
    err = r - target
    base_tol = TOL_SHORT if shot_type in ("putt", "chip") else TOL_FULL
    base = base_tol * max(tol_scale, 0.15) * max(timing_scale, 0.35)
    raw_n = abs(err) / max(base, 0.01)
    bal_for_tol = max(bal, 0.70) if raw_n <= BAND_GOOD else bal
    shrink = 0.35 + (1.0 - 0.35) * min(max(bal_for_tol, 0.0), 1.0)
    tol = base * shrink
    abs_n = abs(err) / max(tol, 0.01)
    incomplete = bool(sample.get("incomplete", False))
    if incomplete:
        contact = "MISS" if abs_n > BAND_GOOD else ("FAT" if err < 0.0 else "THIN")
    elif abs_n <= BAND_PERFECT:
        contact = "PERFECT"
    elif abs_n <= BAND_GOOD:
        contact = "GOOD"
    elif abs_n <= BAND_THIN_FAT:
        contact = "FAT" if err < 0.0 else "THIN"
    else:
        contact = "MISS"
    if bal < 0.35 and contact == "PERFECT":
        contact = "GOOD"
    if bal < 0.25 and contact == "GOOD" and raw_n > BAND_GOOD:
        contact = "FAT" if err < 0.0 else "THIN"
    power_mul = min(max(1.0 - abs_n * 0.22, 0.55), 1.0)
    if contact == "MISS":
        power_mul = min(power_mul, 0.50)
    path = max(min((1.0 if err > 0.01 else (-1.0 if err < -0.01 else 0.0)) * abs_n * 0.35, 1.0), -1.0)
    if bal < 0.35:
        path = max(min(path * (1.0 + (0.35 - bal)), 1.0), -1.0)
    return {"ratio": r, "balance": bal, "tolerance": tol, "contact": contact, "power_mul": power_mul, "path_error": path, "target": target}


def main() -> int:
    # Source contracts — mirror TempoGrade constants
    assert "TARGET_FULL := 3.0" in GRADE
    assert "TARGET_SHORT := 2.0" in GRADE
    assert "TOL_FULL := 1.1" in GRADE
    assert "TOL_SHORT := 0.85" in GRADE
    assert "BAND_PERFECT := 0.50" in GRADE
    assert "BAND_GOOD := 1.15" in GRADE
    assert "BAND_THIN_FAT := 1.85" in GRADE
    assert "abs_n * 0.22" in GRADE
    assert "abs_n * 0.35" in GRADE
    assert "maxf(bal, 0.70)" in GRADE or "max(bal, 0.70)" in GRADE
    assert "power_mul" in GRADE and "path_error" in GRADE
    assert "RELEASE_IS_IMPACT" in GESTURE
    assert "TempoGesture" in ROUTINE
    assert "PowerStance" not in ROUTINE
    assert "SwingContact" not in ROUTINE
    assert "committed_power" in ROUTINE
    assert "practice_mode" in ROUTINE
    assert "PURE_BALANCE" in ROUTINE
    assert "CHIP_YD := 50.0" in GRADE
    assert "CHIP_POWER_CAP" in GRADE
    assert 'club_name.contains("Wedge")' not in GRADE
    assert "club_max_yards" in GRADE
    # Chip vs full is swing size, not club identity — but gate caps by club % so Gap
    # isn't forced onto 2:1 while still near a stock swing.
    assert shot_type_for("Fairway", 90.0) == "full"
    assert shot_type_for("Fairway", 70.0) == "full"
    assert shot_type_for("Fairway", 49.0) == "chip"  # no club → absolute CHIP_YD
    assert shot_type_for("Fairway", 10.0) == "chip"
    assert shot_type_for("Green", 90.0) == "putt"
    assert shot_type_for("Sand", 80.0) == "full"
    # Gap 85 yd: chip gate = min(50, 85*0.42) ≈ 35.7 — 40 yd stays full like an iron
    assert shot_type_for("Fairway", 40.0, 85.0) == "full"
    assert shot_type_for("Fairway", 30.0, 85.0) == "chip"
    # Mid-iron unchanged: still chips below 50
    assert shot_type_for("Fairway", 49.0, 160.0) == "chip"
    assert shot_type_for("Fairway", 55.0, 160.0) == "full"

    # Speed invariance: same ratio at 2× overall speed grades identically
    slow = {"t_takeaway": 0.0, "t_top": 0.75, "t_impact": 1.0, "max_accel": 2.0, "max_jerk": 0.2, "backswing_len": 0.35, "follow_through_len": 0.15, "incomplete": False}
    fast = {"t_takeaway": 0.0, "t_top": 0.375, "t_impact": 0.5, "max_accel": 2.0, "max_jerk": 0.2, "backswing_len": 0.35, "follow_through_len": 0.15, "incomplete": False}
    assert abs(ratio(0.0, 0.75, 1.0) - 3.0) < 1e-6
    assert abs(ratio(0.0, 0.375, 0.5) - 3.0) < 1e-6
    gs = grade(slow, "full")
    gf = grade(fast, "full")
    assert gs["contact"] == gf["contact"] == "PERFECT", (gs, gf)
    assert abs(gs["power_mul"] - gf["power_mul"]) < 1e-6
    assert abs(gs["path_error"] - gf["path_error"]) < 1e-6
    assert gs["power_mul"] <= 1.0 + 1e-9
    assert gs["power_mul"] >= 0.99  # on-tempo keeps carry

    # 14-hcp mild miss (~3.8 at full balance) stays GOOD with playable carry
    mild = dict(slow)
    mild["t_top"] = 0.76
    mild["t_impact"] = 0.96  # 0.76/0.20 = 3.8
    gm = grade(mild, "full")
    assert abs(gm["ratio"] - 3.8) < 0.05, gm
    assert gm["contact"] in ("GOOD", "THIN"), gm
    assert gm["power_mul"] >= 0.82, gm
    assert gm["path_error"] > 0.0

    # Mild tempo + lurch balance must stay playable (not hosel from accel alone)
    snappy = {
        "t_takeaway": 0.0, "t_top": 0.783, "t_impact": 0.968,  # 4.23:1 like playtest
        "max_accel": 40.0, "max_jerk": 2.0, "backswing_len": 0.35, "follow_through_len": 0.12, "incomplete": False,
    }
    gsl = grade(snappy, "full")
    assert abs(gsl["ratio"] - 4.23) < 0.05, gsl
    assert gsl["balance"] < 0.4, gsl
    assert gsl["contact"] != "MISS", gsl
    assert gsl["power_mul"] >= 0.55, gsl

    # Playtest best: ~3.5:1 + lurch → GOOD (not THIN), playable carry mul
    best = {
        "t_takeaway": 0.0, "t_top": 0.596, "t_impact": 0.766,  # 3.51:1
        "max_accel": 35.0, "max_jerk": 1.8, "backswing_len": 0.35, "follow_through_len": 0.12, "incomplete": False,
    }
    gb = grade(best, "full")
    assert abs(gb["ratio"] - 3.5) < 0.05, gb
    assert gb["balance"] < 0.4, gb
    assert gb["contact"] in ("PERFECT", "GOOD"), gb
    assert gb["power_mul"] >= 0.85, gb

    # Extreme ~6:1 still MISS with low power
    wild = dict(slow)
    wild["t_top"] = 0.90
    wild["t_impact"] = 1.05  # 0.90/0.15 = 6.0
    gw = grade(wild, "full")
    assert abs(gw["ratio"] - 6.0) < 0.05, gw
    assert gw["contact"] == "MISS", gw
    assert gw["power_mul"] <= 0.50, gw

    # Incomplete + off tempo → hard mishit
    incomplete = dict(slow)
    incomplete["incomplete"] = True
    incomplete["t_top"] = 0.90
    incomplete["t_impact"] = 1.05
    incomplete["follow_through_len"] = 0.0
    gi = grade(incomplete, "full")
    assert gi["contact"] == "MISS", gi
    assert gi["power_mul"] <= 0.50, gi

    # Rushed costs BOTH distance and accuracy (milder than old curve)
    rushed = dict(slow)
    rushed["t_top"] = 0.3
    rushed["t_impact"] = 0.55  # 0.3/0.25 = 1.2
    gr = grade(rushed, "full")
    assert gr["power_mul"] < 1.0, gr
    assert gr["path_error"] < 0.0, "rushed must pull left (negative path)"
    assert abs(gr["path_error"]) > 0.05

    # Dragged → positive path, also distance leak
    dragged = dict(slow)
    dragged["t_top"] = 0.85
    dragged["t_impact"] = 1.0  # 0.85/0.15 ≈ 5.67
    gd = grade(dragged, "full")
    assert gd["power_mul"] < 1.0
    assert gd["path_error"] > 0.0, "dragged must push right"

    # Balance loss tightens, never widens
    calm = balance({"max_accel": 1.0, "max_jerk": 0.1, "backswing_len": 0.4, "follow_through_len": 0.2, "incomplete": False})
    lurch = balance({"max_accel": 40.0, "max_jerk": 2.5, "backswing_len": 0.05, "follow_through_len": 0.0, "incomplete": True})
    assert calm > lurch
    tw_calm = tolerance_width("full", calm)
    tw_lurch = tolerance_width("full", lurch)
    assert tw_lurch < tw_calm, (tw_lurch, tw_calm)
    assert tw_calm <= TOL_FULL * 1.0 + 1e-6

    # Putt graded against 2:1 not 3:1
    putt_ok = {"t_takeaway": 0.0, "t_top": 0.4, "t_impact": 0.6, "max_accel": 2.0, "max_jerk": 0.2, "backswing_len": 0.3, "follow_through_len": 0.12, "incomplete": False}
    assert abs(ratio(0.0, 0.4, 0.6) - 2.0) < 1e-6
    gp = grade(putt_ok, "putt")
    assert gp["target"] == TARGET_SHORT
    assert gp["contact"] == "PERFECT", gp
    gf_wrong = grade(putt_ok, "full")
    assert gf_wrong["contact"] != "PERFECT" or abs(gf_wrong["ratio"] - TARGET_FULL) < 0.2
    assert gf_wrong["ratio"] < TARGET_FULL
    assert gf_wrong["path_error"] <= 0.0 or gf_wrong["contact"] != "PERFECT"

    # Natural short putt length must not get full-swing balance punishment
    short_putt = {
        "t_takeaway": 0.0, "t_top": 0.4, "t_impact": 0.6,
        "max_accel": 3.0, "max_jerk": 0.3, "backswing_len": 0.12, "follow_through_len": 0.05, "incomplete": False,
    }
    bp_full = balance(short_putt, 1.0, "full")
    bp_putt = balance(short_putt, 1.0, "putt")
    assert bp_putt > bp_full, (bp_putt, bp_full)
    assert bp_putt >= 0.85, bp_putt
    gp_short = grade(short_putt, "putt")
    assert gp_short["contact"] == "PERFECT", gp_short
    assert gp_short["balance"] >= 0.72, gp_short

    # Soft green path amplify still present but milder than old 1.35
    assert "path * 1.1" in ROUTINE
    assert "bs_floor" in GRADE and "short_game" in GRADE

    # Gesture reads continuous path, not three taps
    assert "InputEventScreenDrag" in GESTURE
    assert "moment.emit" in GESTURE
    assert "DEADZONE" in GESTURE
    assert '"START"' in GESTURE or "START" in GESTURE
    assert '"TOP"' in GESTURE or 'status = "TOP"' in GESTURE
    assert "THROUGH" in GESTURE
    assert "FOLLOW" in GESTURE
    assert "live_ratio" in GESTURE
    assert "PULL" in GESTURE
    assert "rushed" in METER and "ideal" in METER and ("too quick" in METER or "dragged" in METER)
    assert "func glance_text" in REPORT
    assert "rushed" in GRADE
    assert "through too quick" in GRADE
    assert "linger" in GRADE or "pull/pause" in GRADE
    assert "on tempo" in GRADE
    assert "bal_for_tol" in GRADE or "maxf(bal, 0.70)" in GRADE

    # Mobile-native: interrupt abort (no ghost commit), edge deadzone, EMA knob
    assert "func _abort_swing" in GESTURE
    assert "touch.canceled" in GESTURE
    assert "NOTIFICATION_APPLICATION_FOCUS_OUT" in GESTURE
    assert "NOTIFICATION_APPLICATION_PAUSED" in GESTURE
    assert "_abort_swing()" in GESTURE
    assert "static var EMA_ALPHA" in GESTURE
    assert "EDGE_DEADZONE_FRAC" in GESTURE
    assert "func screen_x_ok" in GESTURE
    # Abort must reset without emitting committed
    abort_body = GESTURE.split("func _abort_swing")[1].split("func ")[0]
    assert "reset()" in abort_body
    assert "committed.emit" not in abort_body

    # Edge rejection math — 4% floor 24px on a 1080-wide viewport
    EDGE_FRAC = 0.04
    EDGE_MIN = 24.0

    def edge_margin(w: float) -> float:
        return max(w * EDGE_FRAC, EDGE_MIN)

    def screen_x_ok(x: float, w: float) -> bool:
        m = edge_margin(w)
        return x >= m and x <= w - m

    assert abs(edge_margin(1080.0) - 43.2) < 1e-6
    assert edge_margin(400.0) == 24.0  # floor kicks in
    assert screen_x_ok(540.0, 1080.0)
    assert not screen_x_ok(10.0, 1080.0)
    assert not screen_x_ok(1070.0, 1080.0)
    assert screen_x_ok(50.0, 1080.0)
    assert not screen_x_ok(20.0, 400.0)  # inside floor margin
    assert screen_x_ok(30.0, 400.0)

    print("tempo_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

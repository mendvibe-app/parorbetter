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
DEBUG = DIR.joinpath("../debug/debug_controls.gd").read_text(encoding="utf-8")
HOLE = DIR.joinpath("../course/hole_controller.gd").read_text(encoding="utf-8")

TARGET_FULL = 3.0
TARGET_SHORT = 2.0
TOL_FULL = 1.1
TOL_SHORT = 1.35
BAND_PERFECT = 0.50
BAND_GOOD = 1.15
BAND_THIN_FAT = 1.85
PURE_BALANCE = 0.72
PITCH_YD = 50.0
PITCH_POWER_CAP = 0.42
CHIP_YD = 20.0


def shot_type_for(lie: str, remaining_yd: float, club_max_yards: float = 0.0) -> str:
    """Mirror TempoGrade.shot_type_for — chip <20, pitch below gated yd, else full."""
    if lie == "Green":
        return "putt"
    if remaining_yd < CHIP_YD:
        return "chip"
    gate = PITCH_YD
    if club_max_yards > 1.0:
        gate = min(PITCH_YD, club_max_yards * PITCH_POWER_CAP)
    if remaining_yd < gate:
        return "pitch"
    return "full"


def ratio(t_takeaway: float, t_top: float, t_impact: float) -> float:
    bs = t_top - t_takeaway
    ds = t_impact - t_top
    if ds <= 0.001:
        return 99.0
    if bs <= 0.0:
        return 0.0
    return bs / ds


def balance_detail(sample: dict, tighten: float = 1.0, shot_type: str = "full") -> dict:
    t = max(tighten, 0.0)
    accel = float(sample.get("max_accel", 0.0))
    jerk = float(sample.get("max_jerk", 0.0))
    bs_len = float(sample.get("backswing_len", 0.0))
    ft_len = float(sample.get("follow_through_len", 0.0))
    incomplete = bool(sample.get("incomplete", False))
    is_pitch = shot_type == "pitch"
    short_game = shot_type in ("putt", "pitch")
    bs_floor = 0.10 if short_game else 0.18
    ft_floor = 0.04 if short_game else 0.08
    accel_lo = 32.0 if is_pitch else 28.0
    accel_span = 40.0 if is_pitch else 40.0
    accel_pen = min(max((accel - accel_lo) / accel_span, 0.0), 1.0) * t
    jerk_pen = min(max((jerk - 0.6) / 1.4, 0.0), 1.0) * t
    short_bs = min(max((bs_floor - bs_len) / bs_floor, 0.0), 1.0)
    short_ft = 0.0 if incomplete else min(max((ft_floor - ft_len) / ft_floor, 0.0), 1.0)
    incomplete_pen = ((0.30 if short_game else 0.55) if incomplete else 0.0)
    peak_vel = float(sample.get("peak_vel", 0.0))
    transition_ratio = float(sample.get("vel_at_top", 0.0)) / max(peak_vel, 0.001)
    tr_lo = 0.28 if is_pitch else 0.15
    tr_hi = 0.75 if is_pitch else 0.55
    transition_pen = min(max((transition_ratio - tr_lo) / max(tr_hi - tr_lo, 0.05), 0.0), 1.0) * t
    accel_w = 0.25 if is_pitch else 0.35
    trans_w = 0.10 if is_pitch else 0.15
    cast_s = accel_pen * accel_w
    jerky_s = jerk_pen * 0.15
    rush_s = transition_pen * trans_w
    short_bs_s = short_bs * 0.20
    short_ft_s = short_ft * 0.15
    pen = cast_s + jerky_s + rush_s + short_bs_s + short_ft_s + incomplete_pen
    return {
        "score": min(max(1.0 - pen, 0.0), 1.0),
        "causes": {
            "cast": cast_s,
            "jerky": jerky_s,
            "rushed_transition": rush_s,
            "short_backswing": short_bs_s,
            "short_finish": short_ft_s,
            "incomplete": incomplete_pen,
        },
    }


def balance(sample: dict, tighten: float = 1.0, shot_type: str = "full") -> float:
    return float(balance_detail(sample, tighten, shot_type)["score"])


def tolerance_width(shot_type: str, bal: float, timing_scale: float = 1.0, tol_scale: float = 1.0) -> float:
    base_tol = TOL_SHORT if shot_type in ("putt", "pitch") else TOL_FULL
    base = base_tol * max(tol_scale, 0.15) * max(timing_scale, 0.35)
    shrink = 0.35 + (1.0 - 0.35) * min(max(bal, 0.0), 1.0)
    return base * shrink


def grade(sample: dict, shot_type: str, timing_scale: float = 1.0, tol_scale: float = 1.0, bal_tighten: float = 1.0) -> dict:
    target = TARGET_SHORT if shot_type in ("putt", "pitch") else TARGET_FULL
    bal = balance(sample, bal_tighten, shot_type)
    r = ratio(sample["t_takeaway"], sample["t_top"], sample["t_impact"])
    err = r - target
    base_tol = TOL_SHORT if shot_type in ("putt", "pitch") else TOL_FULL
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
    # Distance owned by contact tier; tempo only taxes once out of GOOD.
    power_mul = 1.0
    if contact in ("THIN", "FAT"):
        over = max(abs_n - BAND_GOOD, 0.0)
        power_mul = min(max(1.0 - over * 0.30, 0.55), 1.0)
    elif contact == "MISS":
        power_mul = 0.50
    path = max(min((1.0 if err > 0.01 else (-1.0 if err < -0.01 else 0.0)) * abs_n * 0.35, 1.0), -1.0)
    if bal < 0.35:
        path = max(min(path * (1.0 + (0.35 - bal)), 1.0), -1.0)
    return {"ratio": r, "balance": bal, "tolerance": tol, "contact": contact, "power_mul": power_mul, "path_error": path, "target": target}


def main() -> int:
    # Source contracts — mirror TempoGrade constants
    assert "TARGET_FULL := 3.0" in GRADE
    assert "TARGET_SHORT := 2.0" in GRADE
    assert "TOL_FULL := 1.1" in GRADE
    assert "TOL_SHORT := 1.35" in GRADE
    assert "is_pitch" in GRADE  # pitch softens accel/transition vs full
    assert "BAND_PERFECT := 0.50" in GRADE
    assert "BAND_GOOD := 1.15" in GRADE
    assert "BAND_THIN_FAT := 1.85" in GRADE
    # Contact tier owns distance; no continuous abs_n leak inside PERFECT/GOOD.
    assert "var power_mul := 1.0" in GRADE
    assert "abs_n - BAND_GOOD" in GRADE
    assert "abs_n * 0.22" not in GRADE
    assert "abs_n * 0.35" in GRADE  # path still continuous
    assert "maxf(bal, 0.70)" in GRADE or "max(bal, 0.70)" in GRADE
    assert "power_mul" in GRADE and "path_error" in GRADE
    assert "return 1.06" in (DIR.parent / "ball" / "ball_physics.gd").read_text(encoding="utf-8")
    # Unified diagnosis: balance_detail + diagnose_swing; no bal_word / lurch in notes
    assert "func balance_detail" in GRADE
    assert "func diagnose_swing" in GRADE
    assert "bal_word" not in GRADE
    assert '"lurch"' not in GRADE and "'lurch'" not in GRADE
    assert "Cast at it" in GRADE
    assert "Rushed the transition" in GRADE
    # Transition check: graded relative to the swing's own peak speed (drift guard —
    # a hardcoded threshold here would silently defeat the "adapts to any swing speed" design).
    assert "transition_ratio" in GRADE and "transition_pen" in GRADE
    assert "peak_vel" in GRADE and "vel_at_top" in GRADE
    assert "jerk_pen * 0.15" in GRADE and "trans_w" in GRADE
    assert "_peak_vel" in GESTURE and "_vel_at_top" in GESTURE
    # Accel/jerk fold-in is deferred past the top-detection check so the exact
    # reversal frame (guaranteed sharp regardless of skill) can be excluded.
    assert "is_top_frame" in GESTURE and "was_had_top" in GESTURE
    # Transition detection lag fix: backdate t_top to peak disp; exclude pending window.
    assert "_t_peak_disp" in GESTURE
    assert "lerpf(_t_peak_disp, now" in GESTURE or "_t_top = _t_peak_disp" in GESTURE
    assert "pending_top" in GESTURE
    # Cast spike: frame cap + post-confirm wall window (not backdated _t_top).
    assert "ACCEL_FRAME_CAP" in GESTURE
    assert "POST_TOP_ACCEL_EXCLUDE_SEC" in GESTURE
    assert "post_top_guard" in GESTURE
    assert "_t_top_confirmed" in GESTURE
    assert "TOP_CONFIRM_BLEND" in GESTURE
    assert "ACCEL_SMOOTH_N" in GESTURE
    assert "_accel_ring" in GESTURE
    # Soft-land contact when down long vs guide (playtest low ratio + MISS stack).
    assert "r_raw" in GRADE and "lerpf(r_raw, target" in GRADE
    # Low ratio must not always mean "rushed transition" (use absolute down leg).
    assert 'down_read == "fast"' in GRADE
    assert "Under %.0f:1" in GRADE or "Under %s:1" in GRADE or "longer back or freer through" in GRADE
    assert "_skip_jerk_frame" not in GESTURE
    assert "RELEASE_IS_IMPACT" not in GESTURE
    assert "TempoGesture" in ROUTINE
    assert "PowerStance" not in ROUTINE
    assert "SwingContact" not in ROUTINE
    assert "committed_power" in ROUTINE
    assert "practice_mode" in ROUTINE
    assert "func pace_reads" in GRADE and "func pace_copy" in GRADE
    assert "PACE_TOL_FRAC" in GRADE
    assert "ratio_ok" in GRADE  # never "on time" when ratio is off
    assert "Through too quick for that backswing" in GRADE
    assert "live_coach" in METER and "GameState.range_mode" in METER
    assert "layout_shot_chrome" in ROUTINE
    assert "SHOT_PAD_TOP_COMPACT" in (DIR.parent / "ui" / "ui_scale.gd").read_text(encoding="utf-8")
    # Pad size is shot-type only — not show_meter — so practice pad == real pad.
    layout = ROUTINE.split("func layout_shot_chrome")[1].split("func ")[0]
    assert "SHOT_PAD_TOP_COMPACT if (shot_type == \"putt\"" in layout or "shot_type == \"putt\"" in layout
    assert "pad_top := UiScale.SHOT_PAD_TOP if show_meter" not in layout
    # Takeaway starts on axis lock (not finger-down) — pitch ghost wait no longer inflates 2:1.
    assert "VEL_TOP_EPS_PITCH" in GESTURE
    begin_fn = GESTURE.split("func _begin")[1].split("func ")[0]
    assert "_t_takeaway = -1.0" in begin_fn or "_t_takeaway = -1" in begin_fn
    assert "_t_takeaway = now" in GESTURE.split("func _update")[1].split("func ")[0]
    assert "PURE_BALANCE" in ROUTINE
    assert "PITCH_YD := 50.0" in GRADE
    assert "PITCH_POWER_CAP" in GRADE
    assert "CHIP_YD := 20.0" in GRADE
    assert 'club_name.contains("Wedge")' not in GRADE
    assert "club_max_yards" in GRADE
    # Pitch vs full is swing size, not club identity — but gate caps by club % so Gap
    # isn't forced onto 2:1 while still near a stock swing.
    assert shot_type_for("Fairway", 90.0) == "full"
    assert shot_type_for("Fairway", 70.0) == "full"
    assert shot_type_for("Fairway", 49.0) == "pitch"  # no club → absolute PITCH_YD
    assert shot_type_for("Fairway", 10.0) == "chip"  # inside CHIP_YD
    assert shot_type_for("Fairway", 25.0) == "pitch"  # between chip and pitch gate
    assert shot_type_for("Green", 90.0) == "putt"
    assert shot_type_for("Sand", 80.0) == "full"
    # Gap 85 yd: pitch gate = min(50, 85*0.42) ≈ 35.7 — 40 yd stays full like an iron
    assert shot_type_for("Fairway", 40.0, 85.0) == "full"
    assert shot_type_for("Fairway", 30.0, 85.0) == "pitch"
    # Mid-iron unchanged: still pitches below 50
    assert shot_type_for("Fairway", 49.0, 160.0) == "pitch"
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
    assert abs(gs["power_mul"] - 1.0) < 1e-9  # PERFECT: tier owns distance

    # 14-hcp mild miss (~3.8 at full balance) stays GOOD — full carry, path may drift
    mild = dict(slow)
    mild["t_top"] = 0.76
    mild["t_impact"] = 0.96  # 0.76/0.20 = 3.8
    gm = grade(mild, "full")
    assert abs(gm["ratio"] - 3.8) < 0.05, gm
    assert gm["contact"] in ("GOOD", "THIN"), gm
    if gm["contact"] == "GOOD":
        assert abs(gm["power_mul"] - 1.0) < 1e-9, gm
    else:
        assert gm["power_mul"] >= 0.55, gm
    assert gm["path_error"] > 0.0

    # Mild tempo + lurch balance must stay playable (not hosel from accel alone).
    # These legacy samples predate the transition check (no peak_vel/vel_at_top),
    # so it defaults to 0 penalty — jerk's freed-up weight (30%→15%) only half
    # lands here, balance sits ~0.15 higher than pre-reweight. A real erratic
    # swing with no pause at top would also fail the transition check and land
    # back near the old value.
    snappy = {
        "t_takeaway": 0.0, "t_top": 0.783, "t_impact": 0.968,  # 4.23:1 like playtest
        # max_accel in new cast band (lo 28 / span 40) — was 40 under old 8/24 scale
        "max_accel": 58.0, "max_jerk": 2.0, "backswing_len": 0.35, "follow_through_len": 0.12, "incomplete": False,
    }
    gsl = grade(snappy, "full")
    assert abs(gsl["ratio"] - 4.23) < 0.05, gsl
    assert gsl["balance"] < 0.6, gsl
    assert gsl["contact"] != "MISS", gsl
    if gsl["contact"] in ("PERFECT", "GOOD"):
        assert abs(gsl["power_mul"] - 1.0) < 1e-9, gsl
    else:
        assert gsl["power_mul"] >= 0.55, gsl

    # Playtest best: ~3.5:1 + lurch → GOOD (not THIN), full carry in-band
    best = {
        "t_takeaway": 0.0, "t_top": 0.596, "t_impact": 0.766,  # 3.51:1
        "max_accel": 60.0, "max_jerk": 1.8, "backswing_len": 0.35, "follow_through_len": 0.12, "incomplete": False,
    }
    gb = grade(best, "full")
    assert abs(gb["ratio"] - 3.5) < 0.05, gb
    assert gb["balance"] < 0.6, gb
    assert gb["contact"] in ("PERFECT", "GOOD"), gb
    assert abs(gb["power_mul"] - 1.0) < 1e-9, gb

    # Extreme ~6:1 still MISS with low power
    wild = dict(slow)
    wild["t_top"] = 0.90
    wild["t_impact"] = 1.05  # 0.90/0.15 = 6.0
    gw = grade(wild, "full")
    assert abs(gw["ratio"] - 6.0) < 0.05, gw
    assert gw["contact"] == "MISS", gw
    assert abs(gw["power_mul"] - 0.50) < 1e-9, gw

    # Incomplete + off tempo → hard mishit
    incomplete = dict(slow)
    incomplete["incomplete"] = True
    incomplete["t_top"] = 0.90
    incomplete["t_impact"] = 1.05
    incomplete["follow_through_len"] = 0.0
    gi = grade(incomplete, "full")
    assert gi["contact"] == "MISS", gi
    assert abs(gi["power_mul"] - 0.50) < 1e-9, gi

    # Rushed: path left; distance tax only if out of GOOD
    rushed = dict(slow)
    rushed["t_top"] = 0.3
    rushed["t_impact"] = 0.55  # 0.3/0.25 = 1.2
    gr = grade(rushed, "full")
    assert gr["path_error"] < 0.0, "rushed must pull left (negative path)"
    assert abs(gr["path_error"]) > 0.05
    if gr["contact"] in ("PERFECT", "GOOD"):
        assert abs(gr["power_mul"] - 1.0) < 1e-9, gr
    else:
        assert gr["power_mul"] < 1.0, gr

    # Dragged → positive path; distance tax only if out of GOOD
    dragged = dict(slow)
    dragged["t_top"] = 0.85
    dragged["t_impact"] = 1.0  # 0.85/0.15 ≈ 5.67
    gd = grade(dragged, "full")
    assert gd["path_error"] > 0.0, "dragged must push right"
    if gd["contact"] in ("PERFECT", "GOOD"):
        assert abs(gd["power_mul"] - 1.0) < 1e-9, gd
    else:
        assert gd["power_mul"] < 1.0, gd

    # Balance loss tightens, never widens
    calm_s = {"max_accel": 1.0, "max_jerk": 0.1, "backswing_len": 0.4, "follow_through_len": 0.2, "incomplete": False}
    lurch_s = {"max_accel": 40.0, "max_jerk": 2.5, "backswing_len": 0.05, "follow_through_len": 0.0, "incomplete": True}
    calm = balance(calm_s)
    lurch = balance(lurch_s)
    assert calm > lurch
    assert abs(balance(calm_s) - balance_detail(calm_s)["score"]) < 1e-12
    assert abs(balance(lurch_s) - balance_detail(lurch_s)["score"]) < 1e-12
    cast_causes = balance_detail(
        {"max_accel": 60.0, "max_jerk": 0.2, "backswing_len": 0.4, "follow_through_len": 0.2, "incomplete": False}
    )["causes"]
    assert cast_causes["cast"] > 0.18
    mild_cast = balance_detail(
        {"max_accel": 32.0, "max_jerk": 0.2, "backswing_len": 0.4, "follow_through_len": 0.2, "incomplete": False}
    )["causes"]
    assert mild_cast["cast"] < cast_causes["cast"]
    assert "ACCEL_LO_FULL" in GRADE and "ACCEL_SPAN_FULL" in GRADE
    assert "POST_TOP_ACCEL_EXCLUDE_SEC" in GESTURE
    tw_calm = tolerance_width("full", calm)
    tw_lurch = tolerance_width("full", lurch)
    assert tw_lurch < tw_calm, (tw_lurch, tw_calm)
    assert tw_calm <= TOL_FULL * 1.0 + 1e-6

    # Transition check: graded relative to the swing's own peak speed, not a fixed
    # number — paused before reversing (slow vel_at_top vs peak_vel) stays clean;
    # no pause (vel_at_top near peak_vel) gets penalized regardless of raw speed.
    base_stroke = {"max_accel": 1.0, "max_jerk": 0.1, "backswing_len": 0.4, "follow_through_len": 0.2, "incomplete": False}
    paused = dict(base_stroke, peak_vel=10.0, vel_at_top=0.5)  # 5% of peak — clean pause
    no_pause = dict(base_stroke, peak_vel=10.0, vel_at_top=8.0)  # 80% of peak — barrels through
    fast_paused = dict(base_stroke, peak_vel=40.0, vel_at_top=2.0)  # 5% of a much faster peak
    bal_paused = balance(paused)
    bal_no_pause = balance(no_pause)
    bal_fast_paused = balance(fast_paused)
    assert bal_paused > bal_no_pause, (bal_paused, bal_no_pause)
    assert abs(bal_paused - bal_fast_paused) < 1e-6, "graded by ratio to own peak, not raw speed"

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

    # Gesture reads continuous path, not three taps — pad marks only, no word labels
    assert "InputEventScreenDrag" in GESTURE
    assert "moment.emit" in GESTURE
    assert "DEADZONE" in GESTURE
    assert '"FOLLOW"' not in GESTURE
    assert '"GUIDE"' not in GESTURE
    assert '"START"' not in GESTURE
    assert '"MIN"' not in GESTURE
    assert '"FULL"' not in GESTURE
    assert "example pace" not in GESTURE
    assert "_draw_status_chip" not in GESTURE
    assert "var status" not in GESTURE
    assert "live_ratio" in GESTURE
    assert "rushed" not in METER
    assert "too quick" not in METER
    assert '"ideal"' not in METER
    assert "func glance_text" in REPORT
    assert "rushed" in GRADE
    assert "through too quick" in GRADE
    assert "linger" in GRADE or "pull/pause" in GRADE
    assert "on tempo" in GRADE
    assert "backswing too short" in GRADE
    assert "bal_for_tol" in GRADE or "maxf(bal, 0.70)" in GRADE

    # Option A pad: golf shape, no permanent MIN tick, soft follow + address→ball
    pull_lane = GESTURE.split("func _draw_pull_lane")[1].split("func ")[0]
    assert "_min_pull_point" not in GESTURE
    assert "0.95, 0.75, 0.3" not in pull_lane  # amber MIN tick color gone from lane
    assert "func _draw_follow_cue" in GESTURE
    assert "draw_arc(tip" in GESTURE.split("func _draw_follow_cue")[1].split("func ")[0]
    assert "TEX_FOLLOW" not in GESTURE  # slash landmark retired; soft open ring
    assert "func _draw_pad_ball" in GESTURE
    assert "func _draw_address_mark" in GESTURE
    assert 'preload("res://assets/ball/ball.png")' in GESTURE
    assert "IMPACT_CROSS_FRAC := 0.02" in GESTURE
    assert "IMPACT_CROSS_FLOOR_PX := 6.0" in GESTURE
    assert "deadzone() * 0.5" not in GESTURE.split("func _impact_cross")[1].split("func ")[0]

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

    # Ghost guide: through ends at ≈ address (impact at the ball).
    assert "GUIDE_BACK_FULL := 0.75" in GESTURE
    assert "GUIDE_BACK_SHORT := 0.54" in GESTURE
    assert "MIN_BACKSWING_PITCH_LANE" in GESTURE
    assert "func club_guide_duration_scale" in GESTURE
    assert "club_guide_duration_scale(club_max_yards)" in GESTURE
    # Driver longer absolute window than mid than wedge; ratio still 3:1.
    def club_scale(yd: float) -> float:
        if yd >= 245.0:
            return 1.06
        if yd >= 200.0:
            return 1.03
        if yd >= 160.0:
            return 1.0
        if yd >= 130.0:
            return 0.95
        if yd >= 110.0:
            return 0.90
        return 0.88

    assert club_scale(260) > club_scale(160) > club_scale(110)
    assert abs(club_scale(260) - 1.06) < 1e-9
    assert abs((0.75 * club_scale(260)) / (0.75 * club_scale(260) / 3.0) - 3.0) < 1e-6
    # Meter ticks must apply the same full-swing scale (no audio/ghost desync).
    assert "club_guide_duration_scale(tempo_gesture.club_max_yards)" in METER
    # Debug HUD: guide vs actual downswing instrumentation (transition-timing verify).
    assert '"guide_down_ms"' in GRADE or "guide_down_ms" in GRADE
    assert "down_delta_pct" in GRADE
    assert "transition_ratio" in GRADE
    assert "func _impact_cross" in GESTURE
    assert "func _ghost_impact_pos" in GESTURE
    assert "func _ghost_follow_pos" in GESTURE
    ghost_fn = GESTURE.split("func _ideal_ghost_pos")[1].split("func ")[0]
    assert "_ghost_impact_pos" in ghost_fn
    assert "top.lerp(impact_end" in ghost_fn
    # Demo must ease (not constant-speed reverse) and finish past the ball.
    assert "pow(1.0 - t, 3.0)" in ghost_fn or "pow(1.0 - t" in ghost_fn
    assert "follow" in ghost_fn
    assert "_ghost_follow_pos" in ghost_fn
    # Rest / loop origin at address (start here), not parked in follow-through.
    assert '"pos": start' in ghost_fn and '"phase": "done"' in ghost_fn
    assert "_ghost_t0_ms" in GESTURE
    assert "Time.get_ticks_msec() - _ghost_t0_ms" in GESTURE
    assert "TempoGesture.GUIDE_BACK_SHORT" in METER
    assert "TempoGesture.GUIDE_BACK_FULL" in METER
    assert "0.75 / maxf(target" not in METER
    assert "through the ball" in ROUTINE
    assert "address · to the top · through the ball" in ROUTINE
    assert "address on gold" not in ROUTINE
    assert "blue ghost is pace" not in ROUTINE
    assert "match the ratio, not the clock" not in ROUTINE
    # Tick interval equals ghost backswing for both shot types (2:1 uses SHORT).
    GUIDE_BACK_FULL = 0.75
    GUIDE_BACK_SHORT = 0.54
    assert abs(GUIDE_BACK_SHORT / (GUIDE_BACK_SHORT / TARGET_SHORT) - TARGET_SHORT) < 1e-6
    assert abs(GUIDE_BACK_FULL / (GUIDE_BACK_FULL / TARGET_FULL) - TARGET_FULL) < 1e-6
    assert (GUIDE_BACK_SHORT if TARGET_SHORT < 2.5 else GUIDE_BACK_FULL) == 0.54
    assert (GUIDE_BACK_SHORT if TARGET_FULL < 2.5 else GUIDE_BACK_FULL) == 0.75
    # Pitch through slightly longer than full (0.27 vs 0.25) — short path needs the time.
    assert GUIDE_BACK_SHORT / TARGET_SHORT >= GUIDE_BACK_FULL / TARGET_FULL - 1e-9
    # Ghost follow is lane-relative (not fixed pad-height).
    follow_fn = GESTURE.split("func _ghost_follow_pos")[1].split("func ")[0]
    assert "lane_len" in follow_fn and "0.14" in follow_fn
    # Pitch lane is shorter than full (ghost must not race a driver-length path at 2:1).
    assert "_is_pitch()" in GESTURE.split("func address_hint")[1].split("func ")[0]
    assert "_is_pitch()" in GESTURE.split("func top_hint")[1].split("func ")[0]
    # Range wedges land in pitch band (stock 85% max never did).
    range_swing = HOLE.split("func _begin_range_swing")[1].split("func ")[0]
    assert "club_max <= 110.0" in range_swing
    assert "TempoGrade.PITCH_YD" in range_swing
    assert "TempoGrade.CHIP_YD" in range_swing
    assert "0.70" in GESTURE.split("func top_hint")[1].split("func ")[0]
    # Impact ≈ address (small early band); old 12% shortfall is gone
    IMPACT_CROSS_FRAC = 0.02
    IMPACT_CROSS_FLOOR_PX = 6.0
    # Hardcoded down=back: address upper (y=0), top lower (y=100)
    start, top = (0.0, 0.0), (0.0, 100.0)
    lane_len = 100.0
    size_y = 100.0
    cross_px = max(size_y * IMPACT_CROSS_FRAC, IMPACT_CROSS_FLOOR_PX)
    cross_u = min(cross_px, lane_len * 0.45) / lane_len
    impact_y = start[1] + (top[1] - start[1]) * cross_u
    assert abs(impact_y - 6.0) < 1e-6, impact_y
    assert abs(impact_y - start[1]) <= 8.0, "ghost ends at the ball, not 12% early"
    assert IMPACT_CROSS_FRAC < 0.12

    # Down=back locked: address above top on pad; through-dir from lane; no F1 flip toggle.
    assert "FLIP_SWING" not in GESTURE
    assert "FLIP_SWING" not in DEBUG
    assert "func _lane_through_dir" in GESTURE
    assert "_lane_through_dir()" in GESTURE.split("func _draw_putt_follow_cue")[1].split("func ")[0]
    assert "_lane_through_dir()" in GESTURE.split("func _follow_cue_end")[1].split("func ")[0]
    assert "_draw_follow_cue(start" in GESTURE.split("func _draw_idle_coach")[1].split("func ")[0]
    assert "pull DOWN" in GESTURE
    assert "pull UP" not in GESTURE
    assert "finish through the ball" in GRADE or "through the ball" in GRADE
    assert "match the ghost through" not in GRADE
    assert "ghost down" not in GRADE
    assert "%dms back / %dms thru" in GRADE
    addr_fn = GESTURE.split("func address_hint")[1].split("func ")[0]
    top_fn = GESTURE.split("func top_hint")[1].split("func ")[0]
    assert "_is_putt()" in addr_fn and "_is_chip()" in addr_fn and "_is_pitch()" in addr_fn
    assert "_is_putt()" in top_fn and "_is_chip()" in top_fn and "_is_pitch()" in top_fn
    assert "0.80" in top_fn  # pitch shorter top than full 0.92
    # Lane is stroke axis for all shots (marks + progress share x); trail/cursor free.
    assert "func _lane_project" not in GESTURE
    assert "_address = address_hint()" in GESTURE
    assert "top_hint() - address_hint()" in GESTURE
    assert "_axis = delta.normalized()" not in GESTURE, "finger axis desyncs progress from impact mark"
    assert "func _lane_peak_pos" in GESTURE
    assert "floorf(size.x * 0.5) + 0.5" in GESTURE
    active_lm = GESTURE.split("func _draw_active_landmarks")[1].split("func ")[0]
    assert "address_hint() if _axis_locked" in active_lm
    assert "_lane_peak_pos()" in active_lm
    pull = GESTURE.split("func _draw_pull_lane")[1].split("func ")[0]
    assert "draw_line(start, _lane_peak_pos()" in pull
    assert ", false)" in pull, "progress line AA skews the bright spine off the impact mark"
    putt_draw = GESTURE.split("func _draw_putt")[1].split("func _draw_putt_lane_tex")[0]
    assert "_draw_drag_club_head" in putt_draw or "_draw_drag_club_head()" in GESTURE

    for name in (
        "ui_tempo_landmark_start.png",
        "ui_tempo_landmark_top.png",
        "ui_tempo_landmark_through.png",
        "ui_tempo_landmark_follow.png",
        "ui_tempo_lane.png",
        "ui_tempo_coach_idle.png",
        "ui_tempo_meter_track.png",
        "ui_tempo_meter_needle.png",
        "ui_putt_landmark_start.png",
        "ui_putt_landmark_top.png",
        "ui_putt_landmark_through.png",
        "ui_putt_landmark_follow.png",
        "ui_putt_lane.png",
        "ui_putt_coach_idle.png",
        "ui_chip_landmark_start.png",
        "ui_chip_landmark_top.png",
        "ui_chip_landmark_through.png",
        "ui_chip_lane.png",
        "ui_chip_coach_idle.png",
    ):
        assert (DIR.parent.parent / "assets" / "ui" / name).is_file(), name
    assert 'res://assets/ui/ui_tempo_lane.png' in GESTURE
    assert 'res://assets/ui/ui_putt_lane.png' in GESTURE
    assert 'res://assets/ui/ui_putt_landmark_start.png' in GESTURE
    assert 'res://assets/ui/ui_chip_lane.png' in GESTURE
    assert 'res://assets/ui/ui_chip_landmark_start.png' in GESTURE
    assert "func _draw_putt_lane_tex" in GESTURE
    assert "func _draw_putt_arc_edges" in GESTURE
    assert "func _draw_chip" in GESTURE
    assert "func _is_chip" in GESTURE
    assert 'res://assets/ui/ui_tempo_coach_idle.png' in GESTURE
    assert 'res://assets/ui/ui_tempo_meter_track.png' in METER
    assert "func _draw_landmark_tex" in GESTURE
    assert "_draw_landmark(" not in GESTURE  # circles replaced by textures
    assert (DIR.parent.parent / "assets" / "ball" / "fx_pure_burst.png").is_file()
    assert (DIR.parent.parent / "art" / "prompts" / "putt_pad.md").is_file()

    # Pad geometry: address above top; pitch lane shorter so 2:1 ghost is trackable.
    lanes = {
        "putt": (0.22, 0.92),
        "chip": (0.20, 0.85),
        "pitch": (0.30, 0.80),
        "full": (0.30, 0.92),
    }
    for kind, (addr_y, top_y) in lanes.items():
        assert addr_y < top_y, "%s address above top" % kind
        assert addr_y > 0.12, "%s through room on-pad" % kind
    assert (lanes["pitch"][1] - lanes["pitch"][0]) < (lanes["full"][1] - lanes["full"][0])
    assert 0.20 < 0.22 < 0.30
    assert 0.80 < 0.85 < 0.92
    # Pitch playable: mild blast (3.3:1) with rough reverse is GOOD, not Path+1 MISS.
    blast = {
        "t_takeaway": 0.0, "t_top": 0.54, "t_impact": 0.70,
        "max_accel": 22.0, "max_jerk": 0.4, "backswing_len": 0.35,
        "follow_through_len": 0.08, "incomplete": False,
        "peak_vel": 12.0, "vel_at_top": 5.0,
    }
    gb = grade(blast, "pitch")
    assert gb["contact"] in ("PERFECT", "GOOD", "THIN"), gb
    assert abs(gb["path_error"]) < 0.95, gb

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

    # Pad golfer: spatial stroke API + full + putt pose frames + top-left stage
    assert "func live_stroke_u" in GESTURE
    assert "func _draw_golfer" in GESTURE
    assert "func _draw_golfer_stage" in GESTURE
    assert "GOLFER_MARGIN" in GESTURE
    assert "GOLFER_SKY" in GESTURE and "GOLFER_GRASS" in GESTURE
    assert "GOLFER_X_FRAC" not in GESTURE
    golfer_draw = GESTURE.split("func _draw_golfer")[1].split("func ")[0]
    assert "address_hint()" not in golfer_draw  # top-left, not mid-lane
    assert "_draw_golfer()" in GESTURE.split("func _draw()")[1].split("func ")[0]
    # Pose frames branch: putt / chip+pitch / full — pitch shares chip set.
    keyframes = GESTURE.split("func _golfer_keyframes")[1].split("func ")[0]
    assert "_is_putt()" in keyframes
    assert "_uses_chip_golfer()" in keyframes
    assert "func _golfer_pose_pair" in GESTURE
    root = DIR.parents[1]
    for pose in ("address", "mid", "top", "impact", "follow"):
        for prefix in ("ui_golfer_", "ui_golfer_putt_", "ui_golfer_chip_"):
            name = f"{prefix}{pose}.png"
            assert f'preload("res://assets/ui/{name}")' in GESTURE, name
            assert (root / "assets" / "ui" / name).is_file(), name

    print("tempo_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

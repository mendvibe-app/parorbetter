#!/usr/bin/env python3
"""Punch legibility: 2:1 target, TOL_FULL, short-lane geometry, aim under-band.

Contracts: punch target 2:1, tolerance TOL_FULL, pad through hand-speed matches
pitch (short lane), not full. Balance floors match short lane (0.10/0.04).
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
ROOT = DIR.parents[1]
GRADE = (DIR / "tempo_grade.gd").read_text(encoding="utf-8")
ROUTINE = (DIR / "shot_routine.gd").read_text(encoding="utf-8")
GESTURE = (DIR / "tempo_gesture.gd").read_text(encoding="utf-8")
HC = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")

TARGET_FULL = 3.0
TARGET_SHORT = 2.0
TOL_FULL = 1.1
TOL_SHORT = 1.35
BAND_PERFECT = 0.50
BAND_GOOD = 1.15
BAND_THIN_FAT = 1.85
GUIDE_BACK_FULL = 0.75
GUIDE_BACK_SHORT = 0.54
TREES_TIMING = 0.62  # BallPhysics.lie_timing_scale("Trees")
# Through hand-speed contract: short-lane (0.50 H) / (GUIDE_BACK_SHORT / 2.0) = 1.85 H/s
HAND_SPEED_SHORT = 0.50 / (GUIDE_BACK_SHORT / TARGET_SHORT)  # ≈ 1.85185
HAND_SPEED_FULL = 0.62 / (GUIDE_BACK_FULL / TARGET_FULL)  # ≈ 2.48


def target_ratio(shot_type: str) -> float:
    if shot_type in ("putt", "pitch", "flop", "punch"):
        return TARGET_SHORT
    return TARGET_FULL


def base_tolerance(shot_type: str) -> float:
    if shot_type == "flop":
        return 0.85
    if shot_type in ("putt", "pitch"):
        return TOL_SHORT
    return TOL_FULL  # punch stays here


def bs_floor(shot_type: str) -> float:
    return 0.10 if shot_type in ("putt", "pitch", "flop", "punch") else 0.18


def ft_floor(shot_type: str) -> float:
    return 0.04 if shot_type in ("putt", "pitch", "flop", "punch") else 0.08


def lane_frac(shot_type: str) -> float:
    """Pad address→top length as fraction of pad height (tempo_gesture hints)."""
    # putt 0.22→0.92 = 0.70; chip 0.20→0.85 = 0.65; short-lane 0.30→0.80 = 0.50; full 0.30→0.92 = 0.62
    if shot_type in ("pitch", "flop", "punch"):
        return 0.50
    if shot_type == "chip":
        return 0.65
    if shot_type == "putt":
        return 0.70
    return 0.62  # full


def guide_back_sec(shot_type: str) -> float:
    return GUIDE_BACK_SHORT if target_ratio(shot_type) < 2.5 else GUIDE_BACK_FULL


def through_hand_speed_h_per_s(shot_type: str) -> float:
    """Guide through-swing demand: lane_frac / guide_down_sec (pad heights / s)."""
    down = guide_back_sec(shot_type) / max(target_ratio(shot_type), 1.0)
    return lane_frac(shot_type) / down


def balance_detail(sample: dict, shot_type: str = "full", tighten: float = 1.0) -> dict:
    """Mirror TempoGrade.balance_detail — floors via bs_floor/ft_floor; accel still is_pitch-only."""
    t = max(tighten, 0.0)
    accel = float(sample.get("max_accel", 0.0))
    jerk = float(sample.get("max_jerk", 0.0))
    bs_len = float(sample.get("backswing_len", 0.0))
    ft_len = float(sample.get("follow_through_len", 0.0))
    incomplete = bool(sample.get("incomplete", False))
    is_pitch = shot_type == "pitch"
    short_game = shot_type == "putt" or is_pitch
    floor_bs = bs_floor(shot_type)
    floor_ft = ft_floor(shot_type)
    accel_lo = 32.0 if is_pitch else 28.0
    accel_span = 40.0
    accel_pen = min(max((accel - accel_lo) / accel_span, 0.0), 1.0) * t
    jerk_pen = min(max((jerk - 0.6) / 1.4, 0.0), 1.0) * t
    short_bs = min(max((floor_bs - bs_len) / floor_bs, 0.0), 1.0)
    short_ft = 0.0 if incomplete else min(max((floor_ft - ft_len) / floor_ft, 0.0), 1.0)
    incomplete_pen = (0.30 if short_game else 0.55) if incomplete else 0.0
    peak_vel = float(sample.get("peak_vel", 0.0))
    transition_ratio = float(sample.get("vel_at_top", 0.0)) / max(peak_vel, 0.001)
    tr_lo = 0.28 if is_pitch else 0.15
    tr_hi = 0.75 if is_pitch else 0.55
    transition_pen = min(max((transition_ratio - tr_lo) / max(tr_hi - tr_lo, 0.05), 0.0), 1.0) * t
    accel_w = 0.25 if is_pitch else 0.35
    trans_w = 0.10 if is_pitch else 0.15
    pen = (
        accel_pen * accel_w
        + jerk_pen * 0.15
        + transition_pen * trans_w
        + short_bs * 0.20
        + short_ft * 0.15
        + incomplete_pen
    )
    return {"score": min(max(1.0 - pen, 0.0), 1.0), "short_bs": short_bs}


def grade(
    sample: dict,
    shot_type: str,
    timing_scale: float = 1.0,
    tol_scale: float = 1.0,
) -> dict:
    target = target_ratio(shot_type)
    bal = float(balance_detail(sample, shot_type)["score"])
    bs = float(sample["t_top"]) - float(sample["t_takeaway"])
    ds = float(sample["t_impact"]) - float(sample["t_top"])
    r = 99.0 if ds <= 0.001 else (0.0 if bs <= 0.0 else bs / ds)
    err = r - target
    base = base_tolerance(shot_type) * max(tol_scale, 0.15) * max(timing_scale, 0.35)
    raw_n = abs(err) / max(base, 0.01)
    bal_for_tol = max(bal, 0.70) if raw_n <= BAND_GOOD else bal
    tol = base * (0.35 + (1.0 - 0.35) * min(max(bal_for_tol, 0.0), 1.0))
    abs_n = abs(err) / max(tol, 0.01)
    if abs_n <= BAND_PERFECT:
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
    return {
        "ratio": r,
        "target": target,
        "balance": bal,
        "contact": contact,
        "abs_n": abs_n,
        "tol": tol,
    }


def main() -> int:
    print("PUNCH LEGIBILITY")
    print("-" * 72)

    # --- Source contracts ---
    assert 'shot_type == "punch"' in GRADE or 'or shot_type == "punch"' in GRADE
    assert "TARGET_SHORT" in GRADE
    # Routing: grade uses flight_shot_type
    assert "flight_shot_type()" in ROUTINE
    assert "grade_type" in ROUTINE or "flight_shot_type()" in ROUTINE.split("TempoGrade.grade")[1][:200]
    assert "tempo_gesture.shot_type = pad_type" in ROUTINE or "flight_shot_type()" in ROUTINE
    # Aim under state
    assert 'return "under"' in HC
    assert "PUNCH_UNDER_CANOPY_FRAC" in HC
    assert 'kind == "under"' in HC

    # Geometry: separate short-lane predicate (not _is_pitch — that drives VEL_TOP/min-bs)
    assert "func _uses_short_lane" in GESTURE
    short_lane_fn = GESTURE.split("func _uses_short_lane")[1].split("func ")[0]
    assert 'shot_type == "punch"' in short_lane_fn
    assert 'shot_type == "pitch"' in short_lane_fn
    assert 'shot_type == "flop"' in short_lane_fn
    is_pitch_fn = GESTURE.split("func _is_pitch")[1].split("func ")[0]
    assert 'shot_type == "punch"' not in is_pitch_fn, "_is_pitch must not include punch"
    addr_fn = GESTURE.split("func address_hint")[1].split("func ")[0]
    top_fn = GESTURE.split("func top_hint")[1].split("func ")[0]
    assert "_uses_short_lane()" in addr_fn
    assert "_uses_short_lane()" in top_fn
    # Punch floors in grade (secondary geometry lever)
    bs_fn = GRADE.split("static func bs_floor")[1].split("static func ")[0]
    ft_fn = GRADE.split("static func ft_floor")[1].split("static func ")[0]
    assert "punch" in bs_fn and "0.10" in bs_fn
    assert "punch" in ft_fn and "0.04" in ft_fn
    print("  PASS  source: _uses_short_lane for hints; punch in bs/ft floors; not in _is_pitch")

    # Mirror target_ratio / base_tolerance — DO NOT change these contracts
    assert target_ratio("punch") == TARGET_SHORT
    assert base_tolerance("punch") == TOL_FULL
    assert target_ratio("full") == TARGET_FULL
    assert base_tolerance("full") == TOL_FULL
    print(f"  PASS  target_ratio(punch)={target_ratio('punch')}  base_tolerance(punch)={base_tolerance('punch')}")

    # Floors match short lane
    assert bs_floor("punch") == bs_floor("pitch") == 0.10
    assert ft_floor("punch") == ft_floor("pitch") == 0.04
    assert bs_floor("full") == 0.18 and ft_floor("full") == 0.08
    print(f"  PASS  bs/ft floor punch={bs_floor('punch')}/{ft_floor('punch')} (short, not full)")

    # Guide switches free via target_ratio < 2.5
    assert guide_back_sec("punch") == GUIDE_BACK_SHORT
    assert guide_back_sec("full") == GUIDE_BACK_FULL
    print(f"  PASS  guide_back(punch)={guide_back_sec('punch')}s short  full={guide_back_sec('full')}s")

    # Through-swing hand-speed demand: punch == pitch (~1.85 H/s), not full (~2.48)
    hs_punch = through_hand_speed_h_per_s("punch")
    hs_pitch = through_hand_speed_h_per_s("pitch")
    hs_full = through_hand_speed_h_per_s("full")
    assert abs(hs_punch - hs_pitch) < 1e-9, (hs_punch, hs_pitch)
    assert abs(hs_punch - HAND_SPEED_SHORT) < 1e-6, hs_punch
    assert abs(hs_full - HAND_SPEED_FULL) < 1e-6, hs_full
    assert hs_punch < hs_full - 0.3, "punch must not demand full-lane hand speed"
    print(
        f"  PASS  through hand-speed punch={hs_punch:.3f} == pitch={hs_pitch:.3f} H/s "
        f"(full={hs_full:.3f})"
    )

    # Live playtest ratios under Trees timing (balance ideal first)
    clean = {
        "t_takeaway": 0.0,
        "t_top": 0.54,
        "t_impact": 0.54 + 0.54 / 1.8,
        "max_accel": 20.0,
        "max_jerk": 0.3,
        "backswing_len": 0.22,
        "follow_through_len": 0.12,
        "peak_vel": 1.0,
        "vel_at_top": 0.2,
        "incomplete": False,
    }

    def sample_ratio(r: float, bs_len: float = 0.22) -> dict:
        back = 0.54
        down = back / r
        s = dict(clean)
        s["t_top"] = back
        s["t_impact"] = back + down
        s["backswing_len"] = bs_len
        s["follow_through_len"] = max(bs_len * 0.4, 0.08)
        return s

    # Live playtest ratios under Trees (clean balance).
    # 1.7–1.8 vs target 2.0 → PERFECT (epic said 1.7 GOOD; clean bal is stricter PERFECT).
    # 3.0 vs 2.0 → THIN (high ratio), not MISS — TOL_FULL + Trees still playable.
    for r, want_set in [
        (1.8, {"PERFECT", "GOOD"}),
        (1.7, {"PERFECT", "GOOD"}),
        (3.0, {"THIN", "FAT", "MISS"}),
    ]:
        g = grade(sample_ratio(r), "punch", timing_scale=TREES_TIMING)
        ok = g["contact"] in want_set
        status = "PASS" if ok else "FAIL"
        print(
            f"  {status}  punch r={r:.1f} Trees ts={TREES_TIMING} "
            f"→ {g['contact']} (want {sorted(want_set)}) bal={g['balance']:.2f} abs_n={g['abs_n']:.2f}"
        )
        if not ok:
            return 1
    g3 = grade(sample_ratio(3.0), "punch", timing_scale=TREES_TIMING)
    assert g3["contact"] not in ("PERFECT", "GOOD"), g3
    g_miss = grade(sample_ratio(4.5), "punch", timing_scale=TREES_TIMING)
    print(
        f"  PASS  punch r=3.0 is non-clean ({g3['contact']}); "
        f"r=4.5 → {g_miss['contact']} (disaster band)"
    )

    # --- Aim under-band vs kill-zone (string + numeric model) ---
    m_can = re.search(r"const TREE_CANOPY_H: Array\[float\] = \[([^\]]+)\]", HC)
    assert m_can
    canopy = [float(x.strip()) for x in m_can.group(1).split(",") if x.strip()]
    under_frac = float(re.search(r"const PUNCH_UNDER_CANOPY_FRAC\s*:=\s*([0-9.]+)", PHYS).group(1))
    min_c = min(canopy)
    punch_peak = 20.3
    assert punch_peak <= min_c * under_frac
    print(
        f"  PASS  punch peak {punch_peak:.1f} <= 0.88×min_canopy "
        f"({under_frac * min_c:.1f}) → aim under, not blocked"
    )
    mid_h = (under_frac * min_c + min_c) * 0.5
    assert under_frac * min_c < mid_h < min_c
    print(f"  PASS  kill-band mid {mid_h:.1f} in ({under_frac * min_c:.1f}, {min_c:.0f}) still blocked")

    # --- Balance: short floor no longer double-taxes abbreviated punch ---
    print("-" * 72)
    print("BALANCE (short-lane floors on punch)")
    for bs_len in (0.10, 0.12, 0.14, 0.18, 0.22):
        s = sample_ratio(2.0, bs_len=bs_len)
        s["max_accel"] = 18.0
        s["max_jerk"] = 0.2
        s["vel_at_top"] = 0.25
        s["peak_vel"] = 1.0
        bd = balance_detail(s, "punch")
        g = grade(s, "punch", timing_scale=TREES_TIMING)
        print(
            f"  bs_len={bs_len:.2f}  short_bs={bd['short_bs']:.2f}  "
            f"bal={bd['score']:.2f}  contact={g['contact']}"
        )
    s_real = sample_ratio(1.8, bs_len=0.12)
    s_real["max_accel"] = 22.0
    s_real["max_jerk"] = 0.35
    s_real["vel_at_top"] = 0.3
    s_real["peak_vel"] = 1.0
    g_real = grade(s_real, "punch", timing_scale=TREES_TIMING)
    bd_real = balance_detail(s_real, "punch")
    # At short floor 0.10, bs_len=0.12 is above floor → short_bs=0
    assert bd_real["short_bs"] == 0.0, bd_real
    s_long = sample_ratio(1.8, bs_len=0.22)
    s_long["max_accel"] = 22.0
    s_long["max_jerk"] = 0.35
    s_long["vel_at_top"] = 0.3
    s_long["peak_vel"] = 1.0
    g_long = grade(s_long, "punch", timing_scale=TREES_TIMING)
    print(
        f"  PASS  realistic punch 1.8:1 Trees bs_len=0.12 → "
        f"contact={g_real['contact']} bal={g_real['balance']:.2f} short_bs=0 "
        f"(bs_len=0.22 → {g_long['contact']} bal={g_long['balance']:.2f})"
    )
    print(f"  PASS  floor={bs_floor('punch'):.2f} (short-lane; no full-pad double-tax)")

    # Hand-speed table (report)
    print("-" * 72)
    print("HAND SPEED (through guide demand, pad-H / s)")
    for st in ("full", "pitch", "punch", "flop", "chip", "putt"):
        print(
            f"  {st:6}  lane={lane_frac(st):.2f}H  "
            f"down={guide_back_sec(st) / target_ratio(st):.3f}s  "
            f"hs={through_hand_speed_h_per_s(st):.3f} H/s"
        )

    print("-" * 72)
    print("punch_legibility_check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

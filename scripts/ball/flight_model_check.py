#!/usr/bin/env python3
"""Flight model harness — offline port of launch_velocity + apex, constants parsed from .gd.

Follows scripts/**/*_check.py convention (AGENTS.md). Golden expected ranges encode
real golf (frozen backlog), not current pass rate. Stock fulls use power 0.92 (pocket hi).

Usage:
  python scripts/ball/flight_model_check.py
  python scripts/ball/flight_model_check.py --chart
  python scripts/ball/flight_model_check.py --shot Driver 0.88 full Fairway GOOD
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
PHYS = (DIR / "ball_physics.gd").read_text(encoding="utf-8")
BALL = (DIR / "ball.gd").read_text(encoding="utf-8")

STOCK_POWER = 0.92  # POWER_POCKET_HI — stock swing, not double-taxed mash


def _f(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    assert m, f"missing constant / pattern: {pattern}"
    return float(m.group(1))


def _require(src: str, needle: str) -> None:
    assert needle in src, f"missing in source: {needle!r}"


_require(PHYS, "const BAG:")
_require(PHYS, "static func launch_velocity")
_require(PHYS, "static func resolve_distance")
_require(PHYS, "static func estimate_carry_yards")
_require(PHYS, "static func launch_speed_for")
_require(PHYS, "static func roll_friction_for")
_require(PHYS, "static func air_distance_fraction")
_require(PHYS, "static func force_factor")
_require(PHYS, "static func short_shot_hang_scale")  # dead but kept until Phase 6
_require(PHYS, "static func apex_for")
_require(PHYS, "static func hang_time")
_require(PHYS, "const REAL_APEX_FT")
_require(PHYS, "const APEX_SCALE")
_require(PHYS, "const GRAVITY_PX")
_require(PHYS, "const APEX_SCALE_CONTACT")
_require(BALL, 'launch_data.get("apex"')
_require(BALL, "const SPIN_CURVE_COEFF")
_require(BALL, "normalized() * spd")
_m_spin = re.search(r"const SPIN_CURVE_COEFF\s*:=\s*([0-9.]+)\s*/\s*([0-9.]+)", BALL)
assert _m_spin, "SPIN_CURVE_COEFF parse failed"
SPIN_CURVE_COEFF = float(_m_spin.group(1)) / float(_m_spin.group(2))
# Distance owner must keep literal 0.88 for club_bag_check + honesty of mash tax.
_require(PHYS, "lerpf(1.0, 0.88, force)")
_require(PHYS, "lerpf(1.0, 0.94, force)")

PX_PER_YARD = _f(PHYS, r"const PX_PER_YARD\s*:=\s*([0-9.]+)")
CARRY_FRAC_LONG = _f(PHYS, r"const CARRY_FRAC_LONG\s*:=\s*([0-9.]+)")
CARRY_FRAC_SHORT = _f(PHYS, r"const CARRY_FRAC_SHORT\s*:=\s*([0-9.]+)")
POWER_POCKET_LO = _f(PHYS, r"const POWER_POCKET_LO\s*:=\s*([0-9.]+)")
POWER_POCKET_HI = _f(PHYS, r"const POWER_POCKET_HI\s*:=\s*([0-9.]+)")
FLOP_MAX_YD = _f(PHYS, r"const FLOP_MAX_YD\s*:=\s*([0-9.]+)")
PUNCH_LOFT_SCALE = _f(PHYS, r"const PUNCH_LOFT_SCALE\s*:=\s*([0-9.]+)")
PUNCH_AIR_FRAC_SCALE = _f(PHYS, r"const PUNCH_AIR_FRAC_SCALE\s*:=\s*([0-9.]+)")
MASH_POWER_LERP = _f(PHYS, r"power_mul \*= lerpf\(1\.0,\s*([0-9.]+),\s*force\)")
DIST_MUL_LO = _f(PHYS, r"var dist_mul := lerpf\(1\.0,\s*([0-9.]+),\s*force\)")
HANG_LO = _f(PHYS, r"return clampf\(lerpf\(([0-9.]+),\s*1\.0,\s*total_yards / 40\.0\)")
HANG_FULL_YD = _f(PHYS, r"if total_yards >= ([0-9.]+):\s*\n\s*return 1\.0")
assert abs(MASH_POWER_LERP - 0.94) < 1e-9, MASH_POWER_LERP
assert abs(DIST_MUL_LO - 0.88) < 1e-9, DIST_MUL_LO

# Phase 1 apex-primary knobs
APEX_SCALE = _f(PHYS, r"const APEX_SCALE\s*:=\s*([0-9.]+)")
GRAVITY_PX = _f(PHYS, r"const GRAVITY_PX\s*:=\s*([0-9.]+)")
APEX_SCALE_CHIP = _f(PHYS, r"const APEX_SCALE_CHIP\s*:=\s*([0-9.]+)")
APEX_SCALE_PUNCH = _f(PHYS, r"const APEX_SCALE_PUNCH\s*:=\s*([0-9.]+)")
APEX_SCALE_FLOP = _f(PHYS, r"const APEX_SCALE_FLOP\s*:=\s*([0-9.]+)")
_contact_block = PHYS[
    PHYS.find("const APEX_SCALE_CONTACT") : PHYS.find("const APEX_SCALE_CONTACT") + 220
]
_contact_pairs = re.findall(r'"([A-Z]+)":\s*([0-9.]+)', _contact_block)
assert len(_contact_pairs) >= 5, f"APEX_SCALE_CONTACT parse incomplete: {_contact_pairs}"
APEX_SCALE_CONTACT = {k: float(v) for k, v in _contact_pairs}
assert abs(APEX_SCALE_CONTACT.get("GOOD", -1.0) - 1.0) < 1e-9, APEX_SCALE_CONTACT
_real_apex_pairs = re.findall(
    r"(\d+\.0):\s*(\d+\.0)",
    PHYS[PHYS.find("const REAL_APEX_FT") : PHYS.find("const REAL_APEX_FT") + 400],
)
assert len(_real_apex_pairs) >= 12, f"REAL_APEX_FT parse incomplete: {_real_apex_pairs}"
REAL_APEX_FT = {float(k): float(v) for k, v in _real_apex_pairs}

_chip_m = re.search(
    r'shot_type == "chip":[\s\S]*?lerpf\(([0-9.]+),\s*([0-9.]+),[\s\S]*?clampf\([^,]+,\s*([0-9.]+),\s*([0-9.]+)\)',
    PHYS,
)
assert _chip_m, "chip air_distance_fraction lerp/clamp not found"
CHIP_AIR_HI, CHIP_AIR_LO = float(_chip_m.group(1)), float(_chip_m.group(2))
CHIP_CLAMP_LO, CHIP_CLAMP_HI = float(_chip_m.group(3)), float(_chip_m.group(4))

_flop_m = re.search(
    r'shot_type == "flop":[\s\S]*?lerpf\(([0-9.]+),\s*([0-9.]+),[\s\S]*?clampf\([^,]+,\s*([0-9.]+),\s*([0-9.]+)\)',
    PHYS,
)
assert _flop_m, "flop air_distance_fraction not found"
FLOP_AIR_A, FLOP_AIR_B = float(_flop_m.group(1)), float(_flop_m.group(2))
FLOP_CLAMP_LO, FLOP_CLAMP_HI = float(_flop_m.group(3)), float(_flop_m.group(4))

# Pitch is absolute 0.90 (Phase 3); punch clamp hi parsed from source.
_pitch_m = re.search(
    r'shot_type == "pitch":[\s\S]*?return ([0-9.]+)',
    PHYS,
)
assert _pitch_m, "pitch absolute air_distance_fraction not found"
PITCH_AIR_FRAC = float(_pitch_m.group(1))
_punch_clamp_m = re.search(
    r'shot_type == "punch":[\s\S]*?clampf\(full \* PUNCH_AIR_FRAC_SCALE,\s*([0-9.]+),\s*([0-9.]+)\)',
    PHYS,
)
assert _punch_clamp_m, "punch air_frac clamp not found"
PUNCH_CLAMP_LO, PUNCH_CLAMP_HI = float(_punch_clamp_m.group(1)), float(_punch_clamp_m.group(2))
# Sand relative tax: full * (0.55 / 0.68) — keep literals in sync with ball_physics.gd comment.
SAND_AIR_TAX = 0.55 / 0.68

CONTACT_MUL = {
    "PERFECT": _f(PHYS, r"ContactQuality\.PERFECT:\s*\n\s*return ([0-9.]+)"),
    "GOOD": _f(PHYS, r"ContactQuality\.GOOD:\s*\n\s*return ([0-9.]+)"),
    "THIN": _f(PHYS, r"ContactQuality\.THIN:\s*\n\s*return ([0-9.]+)"),
    "FAT": _f(PHYS, r"ContactQuality\.FAT:\s*\n\s*return ([0-9.]+)"),
    "MISS": _f(PHYS, r"ContactQuality\.MISS:\s*\n\s*return ([0-9.]+)"),
}
LIE_MUL = {
    "Tee": 1.0,
    "Fairway": 1.0,
    "Rough": _f(PHYS, r"const ROUGH_MUL_AVERAGE\s*:=\s*([0-9.]+)"),
    "Sand": _f(PHYS, r'"Sand":\s*\n\s*return ([0-9.]+)'),
    "Trees": _f(PHYS, r'"Trees":\s*\n\s*return ([0-9.]+)\s*# punch'),
}

_bag_entries = re.findall(
    r'\{"name":\s*"([^"]+)",\s*"max_yards":\s*([0-9.]+),\s*"loft_mul":\s*([0-9.]+)\}',
    PHYS,
)
assert len(_bag_entries) >= 12, f"BAG parse incomplete: {len(_bag_entries)}"
BAG = [(n, float(m), float(l)) for n, m, l in _bag_entries]
BY_NAME = {n: (m, l) for n, m, l in BAG}
CANOPY = {"short": 25.0, "pine": 38.0, "tall": 42.0}


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def force_factor(power: float, shot_type: str = "full") -> float:
    p = clamp(power, 0.0, 1.0)
    if p > POWER_POCKET_HI:
        return clamp((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0, 1.0)
    if p < POWER_POCKET_LO:
        if shot_type not in ("full", "punch", ""):
            return 0.0
        return clamp((POWER_POCKET_LO - p) / POWER_POCKET_LO, 0.0, 1.0)
    return 0.0


def air_fraction_full(m: float) -> float:
    return lerp(
        CARRY_FRAC_SHORT,
        CARRY_FRAC_LONG,
        clamp((m - 65.0) / (260.0 - 65.0), 0.0, 1.0),
    )


def air_distance_fraction(m: float, shot_type: str = "full") -> float:
    full = air_fraction_full(m)
    if shot_type == "chip":
        return clamp(
            lerp(CHIP_AIR_HI, CHIP_AIR_LO, clamp((m - 85.0) / 50.0, 0.0, 1.0)),
            CHIP_CLAMP_LO,
            CHIP_CLAMP_HI,
        )
    if shot_type == "pitch":
        return PITCH_AIR_FRAC
    if shot_type == "flop":
        return clamp(
            lerp(FLOP_AIR_A, FLOP_AIR_B, clamp((110.0 - m) / 40.0, 0.0, 1.0)),
            FLOP_CLAMP_LO,
            FLOP_CLAMP_HI,
        )
    if shot_type == "punch":
        return clamp(full * PUNCH_AIR_FRAC_SCALE, PUNCH_CLAMP_LO, PUNCH_CLAMP_HI)
    return full


def short_shot_hang_scale(total_yards: float) -> float:
    """Mirror of dead GD func (still in source for Phase 6)."""
    if total_yards >= HANG_FULL_YD:
        return 1.0
    return clamp(lerp(HANG_LO, 1.0, total_yards / 40.0), HANG_LO, 1.0)


def short_shot_line_scale(total_yards: float) -> float:
    return clamp(total_yards / 55.0, 0.10, 1.0)


def sim_roll_out(
    planned_px: float,
    start_along_px: float,
    landing_speed: float,
    friction: float,
    *,
    clamp_remain: bool,
) -> dict:
    """Mirror non-putt _process_roll (no slope/spin/collision)."""
    along = start_along_px
    speed = max(landing_speed, 0.0)
    dt = 1.0 / 60.0
    reason = "timeout"
    for _ in range(60 * 30):
        # decel toward zero
        decel = friction * 60.0 * dt
        speed = max(0.0, speed - decel)
        if clamp_remain:
            remain = planned_px - along
            if remain < 40.0:
                limit = max(remain * 3.5, 8.0)
                if speed > limit:
                    speed = limit
        if along >= planned_px - 1e-9:
            reason = "plan"
            along = planned_px
            break
        if speed < 10.0:
            reason = "speed"
            break
        along += speed * dt
    return {
        "end_yd": along / PX_PER_YARD,
        "end_px": along,
        "reason": reason,
        "speed": speed,
    }


_REAL_APEX_KEYS = sorted(REAL_APEX_FT.keys())


def _real_apex_ft_for(club_max: float) -> float:
    """Piecewise-linear REAL_APEX_FT — mirror of BallPhysics._real_apex_ft_for."""
    keys = _REAL_APEX_KEYS
    if club_max <= keys[0]:
        return REAL_APEX_FT[keys[0]]
    if club_max >= keys[-1]:
        return REAL_APEX_FT[keys[-1]]
    for i in range(len(keys) - 1):
        k0, k1 = keys[i], keys[i + 1]
        if club_max <= k1:
            t = (club_max - k0) / (k1 - k0)
            return lerp(REAL_APEX_FT[k0], REAL_APEX_FT[k1], t)
    return REAL_APEX_FT[keys[-1]]


def apex_for(
    club_max: float,
    power: float,
    shot_type: str = "full",
    contact: str = "GOOD",
) -> float:
    a = APEX_SCALE * _real_apex_ft_for(club_max) * clamp(power, 0.01, 1.0)
    if shot_type == "chip":
        a *= APEX_SCALE_CHIP
    elif shot_type == "punch":
        a *= APEX_SCALE_PUNCH
    elif shot_type == "flop":
        a *= APEX_SCALE_FLOP
    a *= APEX_SCALE_CONTACT.get(contact, 1.0)
    return max(a, 0.01)


def hang_time(
    club_max: float,
    power: float,
    shot_type: str = "full",
    contact: str = "GOOD",
) -> float:
    return math.sqrt(8.0 * apex_for(club_max, power, shot_type, contact) / GRAVITY_PX)


def resolve_distance(
    club_max: float,
    power: float,
    lie: str = "Fairway",
    contact: str = "GOOD",
    shot_type: str = "full",
    path_error: float = 0.0,
    force_power: float | None = None,
) -> float:
    """Mirror BallPhysics.resolve_distance (Fairway-style force_factor; no shortest-club baby exempt)."""
    is_putt = lie == "Green"
    force_p = power if force_power is None else force_power
    force = 0.0 if is_putt else force_factor(force_p, shot_type)
    power_mul = power * LIE_MUL.get(lie, 1.0)
    if not is_putt:
        power_mul *= CONTACT_MUL[contact]
    if force > 0.0 and power > POWER_POCKET_HI:
        power_mul *= lerp(1.0, MASH_POWER_LERP, force)
    total_yards = club_max * power_mul
    if force > 0.0 and not is_putt:
        dist_mul = lerp(1.0, DIST_MUL_LO, force)
        dist_mul *= 1.0 + clamp(path_error, -1.0, 1.0) * force * 0.04
        total_yards *= dist_mul
    if shot_type == "flop":
        total_yards = min(total_yards, FLOP_MAX_YD)
    return total_yards


def estimate_carry_yards(
    power: float,
    club_max: float,
    lie: str = "Fairway",
    shot_type: str = "full",
) -> float:
    return resolve_distance(club_max, clamp(power, 0.0, 1.0), lie, "GOOD", shot_type, 0.0)


def launch_speed_for(air_px: float, air_time: float) -> float:
    """Mirror BallPhysics.launch_speed_for — thin pass-through, not resolve_distance."""
    return air_px / max(air_time, 0.05)


def roll_friction_for(lie: str) -> float:
    """Mirror BallPhysics.roll_friction_for — single owner for landing_speed + roll."""
    if lie == "Green":
        return 1.8
    if lie in ("Fairway", "Tee"):
        return 2.4
    if lie == "Rough":
        return 4.5
    if lie == "Sand":
        return 7.0
    return 3.0


def sim_flight_land(
    air_px: float,
    air_time: float,
    spin: float,
    *,
    mode: str = "new",
    wind: tuple[float, float] = (0.0, 0.0),
    reverse_guard: bool = True,
    exit_mode: str = "all",
) -> dict:
    """Integrate _process_flight (wind * 6, spin, optional reverse-guard).

    exit_mode:
      all — current: t>=1 or along or path_len
      path — CP5 candidate: path_len only (hang detect via time cap)
    """
    base_speed = launch_speed_for(air_px, air_time)
    vx, vy = 0.0, -base_speed
    launch = (0.0, -1.0)
    fr = (1.0, 0.0)
    dt = 1.0 / 60.0
    t = 0.0
    x = y = 0.0
    guard_trips = 0
    min_along_v = base_speed
    max_lat_frac = 0.0  # |lat| / spd after spin+wind, before guard
    time_cap = air_time * 3.0 + 0.5  # hang detector for path-only mode
    first_exit = ""
    while t < time_cap:
        # ball.gd: velocity += wind * delta * 6.0
        vx += wind[0] * dt * 6.0
        vy += wind[1] * dt * 6.0
        spd = math.hypot(vx, vy)
        along_spd = max(vx * launch[0] + vy * launch[1], 0.0)
        if spd > 0.01 and abs(spin) > 1e-6:
            if mode == "new":
                kick = spin * SPIN_CURVE_COEFF * along_spd * dt
            else:
                ss = max(0.08, min(1.0, along_spd / 180.0))
                kick = spin * 28.0 * dt * ss
            vx += fr[0] * kick
            vy += fr[1] * kick
            n = math.hypot(vx, vy)
            if n > 1e-6:
                vx = vx / n * spd
                vy = vy / n * spd
        along_after = vx * launch[0] + vy * launch[1]
        lat_v = vx * fr[0] + vy * fr[1]
        spd2 = math.hypot(vx, vy)
        if spd2 > 1e-6:
            max_lat_frac = max(max_lat_frac, abs(lat_v) / spd2)
        min_along_v = min(min_along_v, along_after)
        if along_after < along_spd * 0.15:
            guard_trips += 1
            if reverse_guard:
                along_spd2 = max(along_spd * 0.35, 12.0)
                vx = launch[0] * along_spd2 + fr[0] * lat_v * 0.55
                vy = launch[1] * along_spd2 + fr[1] * lat_v * 0.55
        x += vx * dt
        y += vy * dt
        t += dt
        along = max(x * launch[0] + y * launch[1], 0.0)
        path_len = math.hypot(x, y)
        t_done = t + 1e-12 >= air_time
        along_done = along >= air_px
        path_done = path_len >= air_px
        if exit_mode == "path":
            if path_done:
                first_exit = "path_len"
                break
        else:
            # Mirror OR order: t, along, path_len (collision N/A offline).
            if t_done or along_done or path_done:
                if t_done and not along_done and not path_done:
                    first_exit = "t"
                elif along_done and not path_done and not t_done:
                    first_exit = "along"
                elif path_done and not along_done and not t_done:
                    first_exit = "path_len"
                elif path_done and along_done and not t_done:
                    first_exit = "path+along"
                elif t_done and (along_done or path_done):
                    first_exit = "t+dist"  # simultaneous — timer not alone
                else:
                    first_exit = "t"
                break
    else:
        first_exit = "HANG"
    along = max(x * launch[0] + y * launch[1], 0.0)
    lat = abs(x * fr[0] + y * fr[1])
    path_len = math.hypot(x, y)
    return {
        "along_px": along,
        "lat_px": lat,
        "path_px": path_len,
        "t": t,
        "air_time": air_time,
        "guard_trips": guard_trips,
        "min_along_v": min_along_v,
        "max_lat_frac": max_lat_frac,
        "reversed": min_along_v < -1.0,
        "first_exit": first_exit,
        "t_alone": first_exit == "t",
        "hung": first_exit == "HANG",
    }


def recommended_power(remaining_yd: float, club_max: float, lie: str = "Fairway") -> float:
    if lie == "Green":
        effective = club_max * LIE_MUL.get(lie, 1.0)
        if effective <= 0.01:
            return 1.0
        return clamp(max(remaining_yd, 0.667) / effective, 0.0267, 1.0)
    max_yd = resolve_distance(club_max, POWER_POCKET_HI, lie, "GOOD", "full", 0.0)
    need = max(remaining_yd, 2.0)
    if need >= max_yd:
        return POWER_POCKET_HI
    effective = club_max * LIE_MUL.get(lie, 1.0)
    if effective <= 0.01:
        return POWER_POCKET_HI
    return clamp(need / effective, 0.05, POWER_POCKET_HI)


def launch(
    club_max: float,
    loft_mul: float,
    power: float,
    shot_type: str = "full",
    lie: str = "Fairway",
    contact: str = "GOOD",
    path_error: float = 0.0,
) -> dict:
    total_yards = resolve_distance(club_max, power, lie, contact, shot_type, path_error)
    total_px = total_yards * PX_PER_YARD

    # loft still used for thin/fat return parity only (not hang/apex)
    loft = 0.9 * loft_mul
    if contact == "THIN":
        loft = 0.55 * loft_mul
    elif contact == "FAT":
        loft = 1.05 * loft_mul
    if shot_type == "punch":
        loft *= PUNCH_LOFT_SCALE
    elif shot_type == "flop":
        loft *= 1.35
    loft = clamp(loft, 0.35, 1.55)

    air_time = hang_time(club_max, power, shot_type, contact)
    apex_px = apex_for(club_max, power, shot_type, contact)
    air_frac = air_distance_fraction(club_max, shot_type)
    if lie == "Sand" and shot_type == "full":
        air_frac = air_fraction_full(club_max) * SAND_AIR_TAX

    air_px = total_px * air_frac
    base_speed = launch_speed_for(air_px, air_time)
    roll_px = total_px * (1.0 - air_frac)
    decel = roll_friction_for(lie) * 60.0
    landing_speed = math.sqrt(2.0 * decel * roll_px) if roll_px > 1.0 else 0.0
    return {
        "total_yd": total_yards,
        "carry_yd": air_px / PX_PER_YARD,
        "roll_yd": roll_px / PX_PER_YARD,
        "air_time": air_time,
        "speed_px_s": base_speed,
        "apex_px": apex_px,
        "apex_yd": apex_px / PX_PER_YARD,
        "landing_speed": landing_speed,
        "air_frac": air_frac,
        "loft": loft,
    }


GOLDEN = [
    # Phase 3: carry/total ratio. total_yd ranges are ~10-hcp amateur (Arccos/Shot Scope),
    # not Tour — Tour was the wrong player model for this bag (see epic-bag-calibration).
    ("Driver stock", "Driver", STOCK_POWER, "full", "air_frac", 0.89, 0.93),
    ("Driver stock", "Driver", STOCK_POWER, "full", "total_yd", 230.0, 250.0),
    ("Driver stock", "Driver", STOCK_POWER, "full", "apex_yd", 28.0, 40.0),
    ("7-iron stock", "7-Iron", STOCK_POWER, "full", "air_frac", 0.93, 0.97),
    ("7-iron stock", "7-Iron", STOCK_POWER, "full", "total_yd", 140.0, 160.0),
    ("7-iron stock", "7-Iron", STOCK_POWER, "full", "apex_yd", 28.0, 36.0),
    ("PW stock", "Pitching Wedge", STOCK_POWER, "full", "apex_yd", 26.0, 34.0),
    ("SW 50yd pitch", "Sand Wedge", 50.0 / 80.0, "pitch", "apex_yd", 12.0, 22.0),
    ("SW 20yd pitch", "Sand Wedge", 20.0 / 80.0, "pitch", "apex_yd", 5.0, 12.0),
    ("SW 8yd chip", "Sand Wedge", 8.0 / 80.0, "chip", "apex_yd", 1.0, 5.0),
    ("SW 3yd chip", "Sand Wedge", 3.0 / 80.0, "chip", "apex_yd", 0.5, 3.0),
    ("Driver > pine", "Driver", STOCK_POWER, "full", "apex_px", 45.0, 200.0),
    ("7i > pine", "7-Iron", STOCK_POWER, "full", "apex_px", 45.0, 200.0),
    ("Punch < short", "7-Iron", 0.80, "punch", "apex_px", 0.0, 22.0),
]


def run_golden() -> int:
    print("GOLDEN SHOTS  (expected = real-golf target, not current behaviour)")
    print(f"  stock power for fulls = {STOCK_POWER} (POWER_POCKET_HI={POWER_POCKET_HI})")
    print("-" * 74)
    fails = 0
    total = len(GOLDEN)
    for label, club, power, st, metric, lo, hi in GOLDEN:
        m, lm = BY_NAME[club]
        # Frozen range goldens assume GOOD contact (APEX_SCALE_CONTACT["GOOD"] == 1.0).
        val = launch(m, lm, power, st, contact="GOOD")[metric]
        ok = lo <= val <= hi
        if not ok:
            fails += 1
        print(
            f"  {'PASS' if ok else 'FAIL'}  {label:16} {metric:10} "
            f"{val:8.1f}   want {lo:.1f}-{hi:.1f}"
        )
    # Relative golden: THIN must cut apex shape, not only carry yards.
    total += 1
    m7, lm7 = BY_NAME["7-Iron"]
    good_apex = launch(m7, lm7, STOCK_POWER, "full", contact="GOOD")["apex_px"]
    thin_apex = launch(m7, lm7, STOCK_POWER, "full", contact="THIN")["apex_px"]
    thin_ok = thin_apex < 0.60 * good_apex
    if not thin_ok:
        fails += 1
    print(
        f"  {'PASS' if thin_ok else 'FAIL'}  {'7i THIN apex':16} {'ratio':10} "
        f"{thin_apex:8.1f}   want <60% of GOOD {good_apex:.1f} "
        f"({100.0 * thin_apex / good_apex if good_apex else 0:.0f}%)"
    )
    print("-" * 74)
    print(f"  {total - fails}/{total} passing\n")
    return fails


def run_table() -> None:
    print(f"FULL BAG — {STOCK_POWER:.0%} power (stock), fairway, GOOD contact")
    print("-" * 74)
    print(
        f"{'club':16}{'total':>7}{'carry':>7}{'roll':>7}{'airF':>7}"
        f"{'airT':>7}{'speed':>8}{'apex px':>9}{'apex yd':>9}"
    )
    carries: list[float] = []
    for name, m, lm in BAG:
        r = launch(m, lm, STOCK_POWER)
        carries.append(r["carry_yd"])
        print(
            f"{name:16}{r['total_yd']:7.0f}{r['carry_yd']:7.0f}{r['roll_yd']:7.0f}"
            f"{r['air_frac']:7.3f}{r['air_time']:7.2f}{r['speed_px_s']:8.0f}"
            f"{r['apex_px']:9.1f}{r['apex_yd']:9.1f}"
        )
    print("\nADJACENT CARRY GAPS")
    print("-" * 74)
    for i in range(len(BAG) - 1):
        gap = carries[i] - carries[i + 1]
        n0, n1 = BAG[i][0], BAG[i + 1][0]
        ok = "OK" if gap >= 8.0 - 1e-9 else "LOW"
        print(f"  {ok}  {n0:16} -> {n1:16}  {gap:5.1f} yd")
    print("\nSHORT GAME — Sand Wedge, fairway, GOOD contact")
    print("-" * 74)
    print(
        f"{'shot':16}{'total':>7}{'carry':>7}{'roll':>7}{'airT':>7}"
        f"{'speed':>8}{'apex px':>9}{'apex yd':>9}"
    )
    m, lm = BY_NAME["Sand Wedge"]
    for label, yd, st in [
        ("3 yd chip", 3, "chip"),
        ("8 yd chip", 8, "chip"),
        ("15 yd chip", 15, "chip"),
        ("20 yd pitch", 20, "pitch"),
        ("40 yd pitch", 40, "pitch"),
        ("full stock", m * STOCK_POWER, "full"),
    ]:
        pwr = STOCK_POWER if st == "full" else yd / m
        r = launch(m, lm, pwr, st)
        print(
            f"{label:16}{r['total_yd']:7.1f}{r['carry_yd']:7.1f}{r['roll_yd']:7.1f}"
            f"{r['air_time']:7.2f}{r['speed_px_s']:8.0f}"
            f"{r['apex_px']:9.1f}{r['apex_yd']:9.1f}"
        )
    print("\nCANOPY CLEARANCE — stock power")
    print("-" * 74)
    for name, m, lm in BAG:
        a = launch(m, lm, STOCK_POWER)["apex_px"]
        marks = "  ".join(
            f"{k}({v:.0f}) {'OK ' if a > v else 'NO '}" for k, v in CANOPY.items()
        )
        print(f"{name:16} apex {a:6.1f}px   {marks}")
    print()


def make_chart() -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(11, 5.5))
    shots = [
        ("Driver stock", "Driver", STOCK_POWER, "full", "#2b6cb0"),
        ("7-Iron stock", "7-Iron", STOCK_POWER, "full", "#2f855a"),
        ("PW stock", "Pitching Wedge", STOCK_POWER, "full", "#b7791f"),
        ("SW 3yd chip", "Sand Wedge", 3 / 80.0, "chip", "#c53030"),
    ]
    for label, club, power, st, color in shots:
        m, lm = BY_NAME[club]
        r = launch(m, lm, power, st)
        carry_px = r["carry_yd"] * PX_PER_YARD
        xs = [carry_px * i / 200 for i in range(201)]
        ys = [math.sin((x / max(carry_px, 0.01)) * math.pi) * r["apex_px"] for x in xs]
        ax.plot(xs, ys, color=color, lw=2.2,
                label=f"{label} — carry {r['carry_yd']:.0f} yd, apex {r['apex_px']:.0f} px")
    for k, v in CANOPY.items():
        ax.axhline(v, ls="--", lw=1, color="#888")
        ax.text(2, v + 0.8, f"{k} canopy ({v:.0f})", fontsize=8, color="#666")
    ax.set_xlabel("distance downrange (px)")
    ax.set_ylabel("height (px)")
    ax.set_title("Current model — trajectory profiles (flight_model_check)")
    ax.set_xlim(0, 120)
    ax.legend(fontsize=9, loc="upper right")
    ax.grid(alpha=0.2)
    fig.tight_layout()
    out = DIR / "trajectory_current.png"
    fig.savefig(out, dpi=130)
    print(f"chart written: {out}")


def verify_live_constants_reflected() -> None:
    assert abs(PX_PER_YARD - 2.25) < 1e-9
    assert abs(POWER_POCKET_HI - 0.92) < 1e-9
    assert abs(CONTACT_MUL["PERFECT"] - 1.06) < 1e-9
    assert abs(CARRY_FRAC_LONG - 0.91) < 1e-9
    assert abs(CARRY_FRAC_SHORT - 0.98) < 1e-9
    assert abs(PITCH_AIR_FRAC - 0.90) < 1e-9
    assert abs(PUNCH_AIR_FRAC_SCALE - 0.88) < 1e-9
    assert abs(PUNCH_CLAMP_HI - 0.90) < 1e-9
    assert "AIR_DISTANCE_FRACTION" not in PHYS
    assert any(n == "Lob Wedge" for n, _, _ in BAG)
    assert any(n == "Sand Wedge" and abs(m - 80.0) < 0.01 for n, m, _ in BAG)
    chip_sw = air_distance_fraction(80.0, "chip")
    assert 0.20 <= chip_sw <= 0.33, chip_sw
    assert abs(chip_sw - 0.28) < 1e-9, chip_sw  # byte-identical chip branch
    assert abs(air_distance_fraction(80.0, "pitch") - 0.90) < 1e-9
    assert force_factor(STOCK_POWER, "full") == 0.0
    assert force_factor(1.0, "full") > 0.99
    assert short_shot_hang_scale(13.0) < 0.75  # dead func still present
    assert short_shot_hang_scale(50.0) == 1.0
    r = launch(80.0, 1.55, 0.3, "flop")
    assert r["total_yd"] <= FLOP_MAX_YD + 1e-6
    # Phase 1: apex primary — chip << driver; mono bag; linear power
    dr = launch(260.0, 0.62, STOCK_POWER, "full")
    chip = launch(80.0, 1.55, 3.0 / 80.0, "chip")
    assert chip["apex_px"] < dr["apex_px"] * 0.1, (chip["apex_px"], dr["apex_px"])
    assert abs(apex_for(260.0, 0.46, "full") / apex_for(260.0, 0.92, "full") - 0.5) < 1e-6
    prev = 0.0
    for _n, m, _lm in reversed(BAG):  # short → long
        a = apex_for(m, STOCK_POWER, "full")
        assert a + 1e-6 >= prev, f"non-mono apex at {_n}: {a} < {prev}"
        prev = a
    punch = launch(160.0, 1.05, 0.80, "punch")
    assert punch["apex_px"] <= 22.0, punch["apex_px"]
    # Contact scales apex shape; GOOD is identity so bag calibration holds.
    assert abs(APEX_SCALE_CONTACT["GOOD"] - 1.0) < 1e-9
    assert abs(apex_for(160.0, STOCK_POWER, "full", "THIN") / apex_for(160.0, STOCK_POWER, "full", "GOOD") - 0.55) < 1e-6
    assert apex_for(160.0, STOCK_POWER, "full", "FAT") > apex_for(160.0, STOCK_POWER, "full", "GOOD")

    # Piecewise-linear REAL_APEX_FT: exact at keys; midpoints strictly between unequal neighbors.
    # Proves a bag max_yards nudge can no longer jump apex to a neighbor key.
    assert "lerpf(float(REAL_APEX_FT[k0])" in PHYS or "lerpf(float(REAL_APEX_FT[" in PHYS
    for k in _REAL_APEX_KEYS:
        assert abs(_real_apex_ft_for(k) - REAL_APEX_FT[k]) < 1e-12, (k, _real_apex_ft_for(k))
        expect_apex = APEX_SCALE * REAL_APEX_FT[k] * STOCK_POWER
        assert abs(apex_for(k, STOCK_POWER, "full") - expect_apex) < 1e-9, (k, apex_for(k, STOCK_POWER))
    for i in range(len(_REAL_APEX_KEYS) - 1):
        k0, k1 = _REAL_APEX_KEYS[i], _REAL_APEX_KEYS[i + 1]
        v0, v1 = REAL_APEX_FT[k0], REAL_APEX_FT[k1]
        mid = 0.5 * (k0 + k1)
        vm = _real_apex_ft_for(mid)
        if abs(v0 - v1) < 1e-12:
            assert abs(vm - v0) < 1e-12, (mid, vm, v0)  # plateau
        else:
            lo, hi = (v0, v1) if v0 < v1 else (v1, v0)
            assert lo < vm < hi, (mid, vm, v0, v1)
    assert abs(_real_apex_ft_for(50.0) - REAL_APEX_FT[_REAL_APEX_KEYS[0]]) < 1e-12
    assert abs(_real_apex_ft_for(300.0) - REAL_APEX_FT[_REAL_APEX_KEYS[-1]]) < 1e-12

    # Phase 3: continuous carry ramp — ratio, gaps, monotonic air_frac (Driver low → LW high).
    prev_af = 0.0
    for name, m, lm in BAG:
        rr = launch(m, lm, STOCK_POWER)
        expect = air_fraction_full(m)
        assert abs(rr["air_frac"] - expect) < 1e-9, (name, rr["air_frac"], expect)
        assert rr["air_frac"] + 1e-9 >= prev_af, (name, rr["air_frac"], prev_af)
        prev_af = rr["air_frac"]
    carries = [launch(m, lm, STOCK_POWER)["carry_yd"] for _n, m, lm in BAG]
    for i in range(len(carries) - 1):
        gap = carries[i] - carries[i + 1]
        assert gap >= 8.0 - 1e-6, (BAG[i][0], BAG[i + 1][0], gap)

    # Sand relative tax
    sand = launch(260.0, 0.62, STOCK_POWER, "full", lie="Sand")
    assert abs(sand["air_frac"] - air_fraction_full(260.0) * SAND_AIR_TAX) < 1e-9

    # Phase 4: estimate_carry == launch total (GOOD, path_error 0) across bag × powers.
    print("ESTIMATE == LAUNCH (GOOD, path_error=0)")
    print("-" * 74)
    powers = (0.5, 0.8, 0.92, 0.96, 1.0)
    hdr = f"{'club':16}" + "".join(f"{p:>10.2f}" for p in powers)
    print(hdr)
    for name, m, lm in BAG:
        cells = []
        for p in powers:
            est = estimate_carry_yards(p, m, "Fairway", "full")
            launched = launch(m, lm, p, "full", "Fairway", "GOOD", 0.0)["total_yd"]
            assert abs(est - launched) < 1e-9, (name, p, est, launched)
            cells.append(f"{est:10.1f}")
        print(f"{name:16}" + "".join(cells))
    # Phase 5 CP1: launch_speed_for == air_px/air_time identity across bag × powers.
    print("LAUNCH_SPEED_FOR == air_px/air_time")
    print("-" * 74)
    for name, m, lm in BAG:
        for p in powers:
            r = launch(m, lm, p, "full", "Fairway", "GOOD", 0.0)
            air_px = r["carry_yd"] * PX_PER_YARD
            inline = air_px / max(r["air_time"], 0.05)
            owned = launch_speed_for(air_px, r["air_time"])
            assert abs(owned - inline) < 1e-12, (name, p, owned, inline)
            assert abs(r["speed_px_s"] - owned) < 1e-12, (name, p, r["speed_px_s"], owned)
    assert "launch_speed_for(air_px, air_time)" in PHYS
    # recommended_power never recommends above the distance-maximising pocket hi.
    for rem in (200.0, 230.0, 250.0, 300.0):
        rp = recommended_power(rem, 260.0, "Fairway")
        assert rp <= POWER_POCKET_HI + 1e-12, (rem, rp)
    assert abs(recommended_power(300.0, 260.0) - POWER_POCKET_HI) < 1e-12
    assert recommended_power(100.0, 260.0) < POWER_POCKET_HI  # short of max → in-pocket
    assert resolve_distance(260.0, POWER_POCKET_HI) > resolve_distance(260.0, 1.0)
    # launch_velocity must call the owner (no parallel total_yards *= outside it).
    launch_body = PHYS.split("static func launch_velocity")[1].split("static func ")[0]
    assert "resolve_distance(" in launch_body
    assert "total_yards *= dist_mul" not in launch_body
    assert "resolve_distance(" in (
        Path(__file__).resolve().parents[1] / "systems" / "shot_report.gd"
    ).read_text(encoding="utf-8")

    # Phase 5 CP2: shaped-shot along/lateral — old spin_scale vs new coeff (report only).
    print("SHAPED FLIGHT old-vs-new (path=±0.5, GOOD, preserve spd + reverse-guard)")
    print("-" * 74)
    print(f"{'club':16}{'path':>6}{'along_old':>10}{'along_new':>10}{'lat_old':>9}{'lat_new':>9}{'lat×':>7}")
    for name, m, lm in (("Driver", 260.0, 0.62), ("7-Iron", 160.0, 1.05)):
        r = launch(m, lm, STOCK_POWER, "full", "Fairway", "GOOD", 0.0)
        air_px = r["carry_yd"] * PX_PER_YARD
        # Mirror launch_velocity spin for intended_shape ≈ path (stab~1, force=0, GOOD).
        grip = 0.78 if m >= 245 else 0.88 if m >= 180 else 1.0 if m >= 150 else 1.10
        spin0 = 0.5 * 0.95 * grip
        for path, spin in ((0.5, spin0), (-0.5, -spin0)):
            old = sim_flight_land(air_px, r["air_time"], spin, mode="old")
            new = sim_flight_land(air_px, r["air_time"], spin, mode="new")
            ao, lo = old["along_px"], old["lat_px"]
            an, ln = new["along_px"], new["lat_px"]
            ratio = (ln / lo) if lo > 1e-6 else float("inf")
            print(
                f"{name:16}{path:+6.1f}{ao/PX_PER_YARD:10.1f}{an/PX_PER_YARD:10.1f}"
                f"{lo/PX_PER_YARD:9.1f}{ln/PX_PER_YARD:9.1f}{ratio:7.2f}"
            )

    # Phase 5 CP3: reverse-guard trip / reverse sweep (report-first; do not delete here).
    print("REVERSE-GUARD SWEEP (new coeff, guard ON vs OFF)")
    print("-" * 74)
    winds = {
        "calm": (0.0, 0.0),
        "head60": (0.0, 60.0),  # against launch -Y
        "tail60": (0.0, -60.0),
        "cross60": (60.0, 0.0),
        "head+cross": (40.0, 40.0),
    }
    cases = [
        ("LW pitch", 80.0, 1.55, 0.20, "pitch", [0.0, -0.22, -0.55, -1.0, 1.0]),
        ("Driver", 260.0, 0.62, STOCK_POWER, "full", [0.0, 0.5, -0.5, 1.0, -1.0]),
        ("7i soft", 160.0, 1.05, 0.50, "full", [0.0, 0.5, -1.0]),
    ]
    trips_any = 0
    reverse_off_any = 0
    print(
        f"{'case':10}{'wind':12}{'path':>5}{'trips':>6}"
        f"{'along_on':>9}{'along_off':>10}{'minV_off':>9}{'rev?':>5}"
    )
    for cname, m, lm, power, stype, paths in cases:
        r = launch(m, lm, power, stype, "Fairway", "GOOD", 0.0)
        air_px = r["carry_yd"] * PX_PER_YARD
        grip = (
            0.78
            if m >= 245
            else 0.88
            if m >= 180
            else 1.0
            if m >= 150
            else 1.10
            if m >= 120
            else 1.22
        )
        for wname, wind in winds.items():
            for path in paths:
                # CP4: no short_shot_line_scale on launch spin.
                spin = path * 0.95 * grip
                on = sim_flight_land(
                    air_px, r["air_time"], spin, mode="new", wind=wind, reverse_guard=True
                )
                off = sim_flight_land(
                    air_px, r["air_time"], spin, mode="new", wind=wind, reverse_guard=False
                )
                trips_any += on["guard_trips"]
                if off["reversed"]:
                    reverse_off_any += 1
                if on["guard_trips"] or off["reversed"] or abs(path) >= 0.55:
                    print(
                        f"{cname:10}{wname:12}{path:+5.2f}{on['guard_trips']:6d}"
                        f"{on['along_px']/PX_PER_YARD:9.1f}{off['along_px']/PX_PER_YARD:10.1f}"
                        f"{off['min_along_v']:9.1f}{'YES' if off['reversed'] else 'no':>5}"
                    )
    print(
        f"  summary: guard_trips_total={trips_any}  "
        f"reversed_without_guard={reverse_off_any}"
    )
    if trips_any == 0 and reverse_off_any == 0:
        print("  CP3: guard never tripped and no reverse without it — safe to delete.")
    else:
        print("  CP3: STOP — guard still load-bearing; keep reverse-guard in ball.gd.")

    # Phase 5 CP5: which exit predicate fires first (report before deleting t/along).
    print("FLIGHT EXIT SWEEP (which predicate lands first)")
    print("-" * 74)
    exit_cases: list[tuple] = []
    for name, m, lm in BAG:
        exit_cases.append((f"{name[:10]} stk", m, lm, STOCK_POWER, "full", "Fairway", 0.0))
    exit_cases.extend(
        [
            ("LW pit -0.22", 80.0, 1.55, 0.20, "pitch", "Fairway", -0.22),
            ("LW pit -0.55", 80.0, 1.55, 0.20, "pitch", "Fairway", -0.55),
            ("LW pit +1.0", 80.0, 1.55, 0.20, "pitch", "Fairway", 1.0),
            ("punch 7i", 160.0, 1.05, 0.80, "punch", "Fairway", 0.0),
            ("punch path", 160.0, 1.05, 0.80, "punch", "Fairway", -0.5),
            ("flop SW", 80.0, 1.55, 0.30, "flop", "Fairway", 0.0),
            ("flop path", 80.0, 1.55, 0.30, "flop", "Fairway", -0.55),
            ("sand Dr", 260.0, 0.62, STOCK_POWER, "full", "Sand", 0.0),
            ("sand 7i", 160.0, 1.05, STOCK_POWER, "full", "Sand", 0.0),
        ]
    )
    exit_winds = {
        "calm": (0.0, 0.0),
        "head60": (0.0, 60.0),
        "cross60": (60.0, 0.0),
        "tail60": (0.0, -60.0),
    }
    counts: dict[str, int] = {}
    t_alone = 0
    hangs = 0
    path_only_hangs = 0
    print(f"{'case':14}{'wind':10}{'exit':>10}{'t/T':>7}{'path%':>7}{'pathOnly':>10}")
    for cname, m, lm, power, stype, lie, path in exit_cases:
        r = launch(m, lm, power, stype, lie, "GOOD", 0.0)
        air_px = r["carry_yd"] * PX_PER_YARD
        grip = (
            0.78
            if m >= 245
            else 0.88
            if m >= 180
            else 1.0
            if m >= 150
            else 1.10
            if m >= 120
            else 1.15
            if m >= 95
            else 1.18
            if m >= 75
            else 1.22
        )
        spin = path * 0.95 * grip
        if stype == "punch":
            spin *= 0.55  # rough stand-in; punch scales spin in launch_velocity
        for wname, wind in exit_winds.items():
            cur = sim_flight_land(
                air_px, r["air_time"], spin, mode="new", wind=wind, reverse_guard=True
            )
            only = sim_flight_land(
                air_px,
                r["air_time"],
                spin,
                mode="new",
                wind=wind,
                reverse_guard=True,
                exit_mode="path",
            )
            fe = cur["first_exit"]
            counts[fe] = counts.get(fe, 0) + 1
            if cur["t_alone"]:
                t_alone += 1
            if cur["hung"]:
                hangs += 1
            if only["hung"]:
                path_only_hangs += 1
            interesting = (
                cur["t_alone"]
                or only["hung"]
                or fe not in ("path_len", "path+along", "t+dist")
                or wname != "calm"
                and abs(path) > 0.01
            )
            if interesting or wname == "calm" and path == 0.0 and "stk" in cname and m in (
                260.0,
                160.0,
                80.0,
            ):
                print(
                    f"{cname:14}{wname:10}{fe:>10}"
                    f"{cur['t']/max(r['air_time'],1e-9):7.2f}"
                    f"{100*cur['path_px']/max(air_px,1e-9):7.1f}"
                    f"{'HANG' if only['hung'] else only['first_exit']:>10}"
                )
    print(f"  exit histogram: {counts}")
    print(
        f"  t_alone={t_alone}  hung_current={hangs}  "
        f"hung_path_only={path_only_hangs}"
    )
    if t_alone > 0 or path_only_hangs > 0 or hangs > 0:
        print("  CP5: STOP — keep t>=1.0 / along; timer-alone or hang detected.")
    else:
        print("  CP5: timer never alone; path_len-only never hangs — safe to collapse.")

    # Landing-speed lie owner: friction identity + Fairway/Sand/Rough settle.
    print("LANDING SPEED BY LIE (Driver stock; Fairway kinematics for roll_px)")
    print("-" * 74)
    expected_fric = {
        "Green": 1.8,
        "Fairway": 2.4,
        "Tee": 2.4,
        "Rough": 4.5,
        "Sand": 7.0,
        "Unknown": 3.0,
    }
    for lie, want in expected_fric.items():
        assert abs(roll_friction_for(lie) - want) < 1e-12, (lie, roll_friction_for(lie), want)
    # ball.gd must not keep a parallel table — only roll_friction_for.
    roll_body = BALL.split("func _process_roll")[1].split("func ")[0]
    assert "roll_friction_for" in roll_body
    assert "friction = 1.8" not in roll_body
    assert "friction = 4.5" not in roll_body
    assert "friction = 7.0" not in roll_body
    assert "roll_friction_for(lie)" in PHYS or 'roll_friction_for(lie)' in PHYS
    assert "roll_friction_for(lie) * 60.0" in PHYS

    r_fw = launch(260.0, 0.62, STOCK_POWER, "full", "Fairway", "GOOD", 0.0)
    roll_px = r_fw["roll_yd"] * PX_PER_YARD
    old_fairway_spd = math.sqrt(2.0 * 144.0 * roll_px)
    assert abs(r_fw["landing_speed"] - old_fairway_spd) < 1e-9, (
        r_fw["landing_speed"],
        old_fairway_spd,
    )
    r_tee = launch(260.0, 0.62, STOCK_POWER, "full", "Tee", "GOOD", 0.0)
    # Tee uses Fairway kinematics for air_frac (no sand tax) + same friction 2.4.
    assert abs(r_tee["landing_speed"] - old_fairway_spd) < 1e-9, (
        r_tee["landing_speed"],
        old_fairway_spd,
    )
    print(
        f"{'lie':10}{'fric':>6}{'decel':>8}{'land_spd':>10}{'settle_err':>11}"
    )
    for lie in ("Fairway", "Tee", "Rough", "Sand", "Green"):
        f = roll_friction_for(lie)
        spd = math.sqrt(2.0 * f * 60.0 * roll_px)
        # Old bug: always Fairway landing energy into this lie's friction.
        old_spd = old_fairway_spd
        settled_old = sim_roll_out(
            r_fw["total_yd"] * PX_PER_YARD,
            r_fw["carry_yd"] * PX_PER_YARD,
            old_spd,
            f,
            clamp_remain=False,
        )
        settled_new = sim_roll_out(
            r_fw["total_yd"] * PX_PER_YARD,
            r_fw["carry_yd"] * PX_PER_YARD,
            spd,
            f,
            clamp_remain=False,
        )
        err_old = settled_old["end_yd"] - r_fw["total_yd"]
        err_new = settled_new["end_yd"] - r_fw["total_yd"]
        print(
            f"{lie:10}{f:6.1f}{f*60.0:8.1f}{spd:10.1f}"
            f"{err_new:+11.1f}  (was {err_old:+.1f})"
        )
        if lie == "Sand":
            assert abs(err_new) < 2.0, f"Driver→Sand settle still bad: {err_new:.1f} yd"
            assert err_old < -8.0, "precondition: old Sand shortfall missing"

    print(
        f"flight_model_check: constants ok bag={len(BAG)} "
        f"chip_air_sw={chip_sw:.2f} APEX_SCALE={APEX_SCALE} G={GRAVITY_PX} "
        f"dr_apex={dr['apex_px']:.1f} chip3_apex={chip['apex_px']:.1f} "
        f"CARRY={CARRY_FRAC_LONG}-{CARRY_FRAC_SHORT} "
        f"contact_thin={APEX_SCALE_CONTACT['THIN']}"
    )


def resolve_club(name: str) -> str:
    """Exact BAG name, case-insensitive match, or common short aliases."""
    if name in BY_NAME:
        return name
    lower = {n.lower(): n for n in BY_NAME}
    if name.lower() in lower:
        return lower[name.lower()]
    aliases = {
        "pw": "Pitching Wedge",
        "gw": "Gap Wedge",
        "sw": "Sand Wedge",
        "lw": "Lob Wedge",
        "dr": "Driver",
        "3w": "3-Wood",
        "hy": "Hybrid",
        "5i": "5-Iron",
        "6i": "6-Iron",
        "7i": "7-Iron",
        "8i": "8-Iron",
        "9i": "9-Iron",
    }
    key = name.lower().replace(" ", "")
    if key in aliases and aliases[key] in BY_NAME:
        return aliases[key]
    raise SystemExit(
        f"unknown club {name!r}; use a BAG name e.g. Driver, 7-Iron, Pitching Wedge, Sand Wedge"
    )


def run_shot_lookup(argv: list[str]) -> int:
    """One-shot lookup: --shot <club> <power> <type> <lie> <contact>"""
    # argv is args after --shot
    if len(argv) < 5:
        print(
            "usage: python scripts/ball/flight_model_check.py --shot "
            "<club> <power 0-1> <type> <lie> <contact>\n"
            "  e.g. --shot Driver 0.88 full Fairway GOOD"
        )
        return 1
    club_s, power_s, shot_type, lie, contact = (
        argv[0],
        argv[1],
        argv[2],
        argv[3],
        argv[4],
    )
    club = resolve_club(club_s)
    try:
        power = float(power_s)
    except ValueError:
        print(f"power must be a float 0-1, got {power_s!r}")
        return 1
    if not (0.0 <= power <= 1.0):
        print(f"power out of range [0,1]: {power}")
        return 1
    if contact not in CONTACT_MUL:
        print(f"contact must be one of {sorted(CONTACT_MUL)}; got {contact!r}")
        return 1
    if lie not in LIE_MUL:
        print(f"lie must be one of {sorted(LIE_MUL)}; got {lie!r}")
        return 1
    m, lm = BY_NAME[club]
    r = launch(m, lm, power, shot_type, lie, contact)
    print(
        f"SHOT  {club}  power={power:.3f}  type={shot_type}  lie={lie}  contact={contact}"
    )
    print("-" * 74)
    print(
        f"{'club':16}{'total':>7}{'carry':>7}{'roll':>7}{'airT':>7}"
        f"{'speed':>8}{'apex px':>9}{'apex yd':>9}"
    )
    print(
        f"{club:16}{r['total_yd']:7.1f}{r['carry_yd']:7.1f}{r['roll_yd']:7.1f}"
        f"{r['air_time']:7.2f}{r['speed_px_s']:8.0f}"
        f"{r['apex_px']:9.1f}{r['apex_yd']:9.1f}"
    )
    print(
        f"  hang={r['air_time']:.3f}s  launch={r['speed_px_s']:.1f} px/s  "
        f"air_frac={r['air_frac']:.3f}"
    )
    return 0


def main() -> int:
    # One-shot lookup: skip tables/goldens (parsing still loads at import).
    if "--shot" in sys.argv:
        i = sys.argv.index("--shot")
        return run_shot_lookup(sys.argv[i + 1 :])

    verify_live_constants_reflected()
    run_table()
    fails = run_golden()
    if "--chart" in sys.argv:
        try:
            make_chart()
        except ImportError:
            print("matplotlib not installed — skip --chart")
    # 14 frozen ranges + 1 THIN-relative golden
    total_g = len(GOLDEN) + 1
    print(
        f"flight_model_check: ok (goldens {total_g - fails}/{total_g} PASS)"
    )
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

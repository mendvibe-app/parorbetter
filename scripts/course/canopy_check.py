#!/usr/bin/env python3
"""Canopy rebalance (Phase 2): TREE_CANOPY_H vs Phase 1 height-at-along clearance.

Parses canopy table from hole_controller.gd and apex/air-frac constants from
ball_physics.gd. Does not hardcode canopy numbers as the source of truth.

HEIGHT MODEL (must match BallPhysics.estimate_height_at_along):
  along = total_frac * total_px
  air_px = total_px * air_frac
  if along >= air_px: height = 0  (landed / rolling)
  else: t = along / air_px; height = sin(t * pi) * apex

Do NOT use sin(total_frac * pi) * apex — that ignores the air/roll split and
fails the check against correct game code. total_frac is fraction of planned
total distance ("down the hole"); t is progress along the airborne segment only.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HC = (ROOT / "scripts" / "course" / "hole_controller.gd").read_text(encoding="utf-8")
PHYS = (ROOT / "scripts" / "ball" / "ball_physics.gd").read_text(encoding="utf-8")

STOCK_POWER = 0.92


def _f(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    assert m, f"missing: {pattern}"
    return float(m.group(1))


def main() -> int:
    # --- Parse TREE_CANOPY_H + TREE_TEXTURES length ---
    m_can = re.search(
        r"const TREE_CANOPY_H: Array\[float\] = \[([^\]]+)\]",
        HC,
    )
    assert m_can, "TREE_CANOPY_H array not found"
    canopy = [float(x.strip()) for x in m_can.group(1).split(",") if x.strip()]
    n_tex = len(re.findall(r"preload\(\"res://assets/background/tree_", HC))
    assert len(canopy) == n_tex, f"canopy len {len(canopy)} != TREE_TEXTURES {n_tex}"
    assert len(canopy) == 8, canopy

    # --- Phase 1 apex knobs (read-only) ---
    apex_scale = _f(PHYS, r"const APEX_SCALE\s*:=\s*([0-9.]+)")
    punch_scale = _f(PHYS, r"const APEX_SCALE_PUNCH\s*:=\s*([0-9.]+)")
    pairs = re.findall(
        r"(\d+\.0):\s*(\d+\.0)",
        PHYS[PHYS.find("const REAL_APEX_FT") : PHYS.find("const REAL_APEX_FT") + 400],
    )
    real_ft = {float(k): float(v) for k, v in pairs}
    assert len(real_ft) >= 12

    def real_apex_ft(club_max: float) -> float:
        best_ft, best_d = 80.0, 1e9
        for k, v in real_ft.items():
            d = abs(k - club_max)
            if d < best_d:
                best_d = d
                best_ft = v
        return best_ft

    def apex_for(club_max: float, power: float, shot_type: str = "full") -> float:
        a = apex_scale * real_apex_ft(club_max) * max(0.01, min(1.0, power))
        if shot_type == "punch":
            a *= punch_scale
        return max(a, 0.01)

    # Phase 3 carry ramp (read-only mirror of ball_physics._air_fraction_full)
    carry_long = _f(PHYS, r"const CARRY_FRAC_LONG\s*:=\s*([0-9.]+)")
    carry_short = _f(PHYS, r"const CARRY_FRAC_SHORT\s*:=\s*([0-9.]+)")

    def air_frac_full(m: float) -> float:
        t = max(0.0, min(1.0, (m - 65.0) / (260.0 - 65.0)))
        return carry_short + (carry_long - carry_short) * t

    def height_at_total_frac(
        total_frac: float, apex: float, club_max: float, shot_type: str = "full"
    ) -> float:
        """Mirror estimate_height_at_along with along = total_frac * total_px.

        t = along / air_px, air_px = total_px * air_frac — NOT sin(total_frac * pi) * apex.
        """
        # total_px cancels: along/air_px = total_frac / air_frac
        af = air_frac_full(club_max)
        if af <= 0.0:
            return 0.0
        t = total_frac / af
        if t >= 1.0:
            return 0.0  # past first bounce — on ground under canopy
        return math.sin(t * math.pi) * apex

    def clears_count(height: float) -> int:
        return sum(1 for c in canopy if height >= c)

    results: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        results.append((name, ok, detail))
        status = "PASS" if ok else "FAIL"
        print(f"  {status}  {name}: {detail}")

    print("CANOPY ACCEPTANCE  (height-at-along = sin((total_frac/air_frac)*pi)*apex)")
    print(f"  TREE_CANOPY_H = {canopy}")
    print(f"  APEX_SCALE={apex_scale} PUNCH={punch_scale}")
    print("-" * 72)

    # 1. Stock driver at 20% total — at most 2 canopy types
    dr_apex = apex_for(260.0, STOCK_POWER, "full")
    h20 = height_at_total_frac(0.20, dr_apex, 260.0)
    n20 = clears_count(h20)
    check(
        "driver 20% clears <=2",
        n20 <= 2,
        f"h={h20:.1f} apex={dr_apex:.1f} clears={n20}",
    )

    # 2. Stock driver at 35% total — at least 4 canopy types
    h35 = height_at_total_frac(0.35, dr_apex, 260.0)
    n35 = clears_count(h35)
    check(
        "driver 35% clears >=4",
        n35 >= 4,
        f"h={h35:.1f} apex={dr_apex:.1f} clears={n35}",
    )

    # 3. 7-iron punch clears nothing at 20% and 35%
    punch_apex = apex_for(160.0, 0.80, "punch")
    hp20 = height_at_total_frac(0.20, punch_apex, 160.0)
    hp35 = height_at_total_frac(0.35, punch_apex, 160.0)
    check(
        "7i punch clears 0 @20%",
        clears_count(hp20) == 0,
        f"h={hp20:.1f} apex={punch_apex:.1f} min_canopy={min(canopy):.0f}",
    )
    check(
        "7i punch clears 0 @35%",
        clears_count(hp35) == 0,
        f"h={hp35:.1f} apex={punch_apex:.1f} min_canopy={min(canopy):.0f}",
    )

    # 4. Tallest canopy above stock driver apex (unclearable wall)
    tall = max(canopy)
    check(
        "tall > driver apex",
        tall > dr_apex,
        f"tall={tall:.0f} driver_apex={dr_apex:.1f}",
    )

    # 5. Half-power driver clears nothing at 20%
    half_apex = apex_for(260.0, 0.46, "full")
    hh20 = height_at_total_frac(0.20, half_apex, 260.0)
    check(
        "half driver 20% clears 0",
        clears_count(hh20) == 0,
        f"h={hh20:.1f} apex={half_apex:.1f}",
    )

    # 6. Array length already asserted; ordering: tall is max (index 7)
    check(
        "tall is max canopy",
        canopy[-1] == tall and tall == max(canopy),
        f"last={canopy[-1]:.0f} max={tall:.0f}",
    )

    fails = sum(1 for _n, ok, _d in results if not ok)
    print("-" * 72)
    print(f"canopy_check: {len(results) - fails}/{len(results)} assertions PASS")
    if fails:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

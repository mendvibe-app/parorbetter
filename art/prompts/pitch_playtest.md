# Playtest todo: Pitching feel / bugs

**Status**: In progress — 2026-07-30 pass (ghost + range unlock)  
**Code**: `TempoGrade.shot_type_for`, `ShotRoutine`, `TempoGesture`, `hole_controller._begin_range_swing`

## How pitch is wired today

| Aim distance | Type | Pad | Grade | Golfer |
|--------------|------|-----|-------|--------|
| Green | putt | amplitude | PuttStroke | putt |
| **&lt; 20 yd** (`CHIP_YD`) | **chip** | amplitude (chip chrome) | PuttStroke | chip |
| **20 → gate** | **pitch** | **full tempo pad** | TempoGrade **2:1** | chip |
| ≥ gate | full | full tempo pad | TempoGrade 3:1 | full |

Pitch gate = `min(50, club_max * 0.42)` when a club is known.

## Fixes applied

1. **Contract drift** — chip gate mirrored in `tempo_check.py`.
2. **Shorter pitch lane** — `top` 0.70 vs full 0.92; one mid pip for 2:1.
3. **Shared ghost pedagogy (with full)** — ease into top, through, follow, rest/start at address, pad-local clock.
4. **Ghost through no longer mushier than full (2026-07-30)** — `GUIDE_BACK_SHORT` **0.50** → through **0.25** (exact 2:1). Was 0.64/0.32 (slower clock through than full 3:1 on a shorter path).
5. **Lane-relative ghost follow** — was `0.10 × pad H` (~26% of pitch stroke); now ~14% of lane.
6. **Pitch min backswing** — `0.22 × lane` (same stroke fraction as full), not `0.14 × pad H` (~37% of short lane).
7. **Range pitch unlock** — PW / Gap (`club_max ≤ 110`) aim a short target inside the pitch band so range can practice 2:1. Irons+ stay stock ~85% full.

## 2026-07-30 playtest dump (debug PNGs)

- Contact **MISS**, Bal **19–35%**, Path **+1.00**, Pwr ~30%, actual ~11–12 yd.
- Pattern: short lane + fast through → ratio ~4–6:1 (high) while accel/transition crushed balance.
- Phase 3 applied: `TOL_SHORT` 0.85→**1.35**, pitch-soft balance, pitch top **0.80**, ghost back **0.54**.

## Still watch in playtest

- Range: **Pitching Wedge** or **Gap/Sand** → hint `PITCH ~2:1`, F1 shows `[pitch]` + ratio ms.
- Copy ghost → contact GOOD/PERFECT more often; Path not glued at +1.
- Full driver/iron path still feels like the post-fix 3:1.
- Gap@40yd still maps **full** on course (gate quirk) — separate from pad feel.

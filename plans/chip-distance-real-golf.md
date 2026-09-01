# Plan — Chip distance vs real golf

**Status:** CODE COMPLETE — Phase 1 pad, Phase 2 lie-change remain, Phase 3 chip PERFECT = 1.0.  
**Origin:** Playtest dump (LW chip, Fairway, GOOD, ~48 yd to pin). Overpull felt like a full lob wedge.  
**Scope lock:** Chip pad power map + chip lie-change roll speed + chip PERFECT contact mul. Putt log map, pitch/full plan-clamp, camera, `CHIP_YD` gate — untouched.  
**User lock:** A bit past the tick = a bit long, not almost a full LW. Grass slower than green; once on the green the runner runs; downhill can still run past. Pure chip = committed yards.

---

## The shot (what happened)

F1, one swing:

```text
Club LW  chip  Fairway  GOOD  path 0
Amp 0.87 vs tgt 0.83    commit 73% → rolled 97%    bal 22%
Target 144 ft → 191     (47 ft long)
Plan 63 yd → Actual 88 yd
Carry 18 yd (matched)   roll +71 yd (plan 46)
Note: Quit on it before the finish
```

Two stacked inflations. Neither is the follow-camera PR. Quit/short finish biases **short** (`tempo_grade.gd` `"short_finish"`); it did not add yards. Contact GOOD mul = 1.0.

---

## Phase 0 — Findings

### A. Pad smash (48 yd commit → 63 yd plan)

Chip reuses the **putt log map** (`PuttStroke.power_from_frac` / `POWER_FLOOR` 0.0267, built for 2 ft–75 ft putts). `grade()` does:

```text
rolled     = power_from_frac(actual_frac)     # absolute yards-as-power on the log
power_mul  = rolled / committed_power         # may smash past commit
result     = committed_power * power_mul      # = rolled, clamped
```

LW `max_yards` 65. Commit 73% ≈ 48 yd. Marker sits at pad frac **~0.83** (near the top — the log bunches long shots). Actual 0.87 vs 0.83 is a small overpull. On that log, 0.87 inverts to **~97% of the club** → 63 yd. Linear pad math on the same pull: `0.87 / 0.83 ≈ 1.05` → **~50 yd** (a bit long).

Chip scale ticks only go to 20 yd (`CHIP_SCALE_*`); `CHIP_YD` is 20. Player can still pick chip at 48 yd (bump-and-run). That gate is **out of scope**. Chip air fraction is ~28% by design (“long putt with a wedge”) — carry 18 of 63 is that split working, not a bug.

`putt_stroke_check.py` still asserts smash-long for a big chip overpull (`yd_big > yd_on`). That is the putt-log identity leaking into chip.

### B. Roll skate (46 yd plan roll → 71 actual)

Carry matched. Chip is **exempt from plan-distance clamp** in `ball.gd` `_process_roll` (`_shot_type != "chip"`). Chips coast on speed + slope like putts. Pitch/full hard-stop at plan so a PW doesn’t skate. Keep that split.

Bounce speed is `sqrt(2 * a * remain)` at **current** lie. Chip on Fairway uses `CHIP_PACE_SCALE` (0.38) × fairway decel. Chip on Green uses **putt stimp** (`landing_roll_decel_px`: `shot_type == "chip" and lie == "Green"` → `putt_decel_px()`).

Plan distance is a **single-lie** rollout (fairway `a` for the whole 46 yd). Mid-roll, `_sync_ground_lie` → `set_lie` changes friction **and keeps speed**. Leftover ~5 yd of fairway energy on stimp is ~6× (`a_fw / a_stimp`) → the 46→71. Downhill `green_slope_accel` can add more.

Pitch already uses fairway-class friction on green for this reason. Chip keeps stimp on purpose (runner once on). The bug is the **speed/friction invariant break**, not stimp itself.

Real golf we want:

| Situation | Feel |
|-----------|------|
| A bit past the tick | A bit long |
| Bounce on grass, run onto green | Pace you asked for (plan remain), not a 6× leftover gift |
| Bounce already on the green | Stimp from the first hop (already true) |
| Downhill once on | Extra run-out (no hard stop at plan) |
| Uphill once on | Dies short |

Rescale **speed** on chip lie change so leftover **yards** match the new `a`. Slope still integrates after that. Do **not** fold chips into the pitch/full clamp.

---

## Phase 1 — Chip pad: pull error = distance error (separate PR)

**Files:** `scripts/shot/putt_stroke.gd` `grade()`, `scripts/shot/putt_stroke_check.py`.  
`ShotRoutine` already passes `shot_type == "chip"` via `chip_tol_scale` / `chip_arc_scale` — both are 1.0 today, so they cannot gate. One new flag or `shot_type` arg is the smallest honest branch. Do **not** key off `club_max_yd > PUTTER_MAX_YD` (`grade()` default `club_max_yd` is 40).

In `grade()`, putt path unchanged:

```text
rolled = power_from_frac(actual)
power_mul = rolled / maxf(committed_power, POWER_FLOOR)
```

Chip path — ratio of pad fractions, same as “thumb error = % distance error” the log map *claims* for putts:

```text
power_mul = actual_frac / maxf(target_frac, MARKER_MIN_FRAC)
```

Tempo bias, THIN-overpull tax drop (`lie != "Green" and frac_err > 0.0`), contact bands, path — stay. `marker_frac` / ticks stay log for putts; chip ticks stay yards. Chip marker **position** can keep `marker_frac(committed_power)` so the tick does not jump. Only the **grade** of a miss goes linear.

**Check** (`putt_stroke_check.py`): dump identity.

```text
commit 0.73, tgt ≈ 0.83, actual 0.87
chip power_mul ≈ 0.87/0.83  (± a few %)   # ~50 yd on LW 65, not ~63
putt power_from_frac(0.87) still smashes   # putt log untouched
chip overpull THIN still ≥ GOOD-edge yards # Phase 4 cliff must not return
```

Replace the chip `yd_big > yd_on` smash-from-log assert with “overpull is longer, and 0.87 vs 0.83 is not 33% long.”

**Playtest:** Practice Range, LW chip, ~48 yd. Hit the tick → ~48. A hair past → a few yards long, not a full LW.

---

## Phase 2 — Chip roll: lie change keeps remaining yards (separate PR)

**Files:** `scripts/ball/ball.gd` (`_sync_ground_lie` / roll), `scripts/ball/rollout_check.py`.  
Physics helpers `landing_roll_decel_px` / `CHIP_PACE_SCALE` / chip-on-green stimp — **no formula change**.

On chip, when lie changes during `ROLL` and remaining plan `remain = max(_planned_distance_px - along, 0)`:

```text
a_new = landing_roll_decel_px(new_lie, "chip", ...)
# keep heading; size speed for leftover yards at the new a (flat identity)
v = sqrt(2 * a_new * remain)     # remain ~0 → let it die, don't re-launch
```

Gate: `_shot_type == "chip"` and `state == ROLL`. Not putt (already stimp the whole way). Not pitch/full (plan clamp + fairway-class green friction already own that skate).

`ponytail:` this ignores leftover *speed* in favor of leftover *plan yards*. Ceiling: a hot chip that hops onto a downslope still runs past because slope accel is applied every frame after the remap. Upgrade if playtest wants a true energy carry (cap the friction ratio instead of remapping).

**Check** (`rollout_check.py`):

```text
fairway bounce speed for remain R, then enter Green
after remap, rest at stimp ≈ R (flat)
without remap, rest ≫ R   # keep the old skate identity as a comment/assert on the unfixed formula
chip-on-green stimp identity stays
'_shot_type != "chip"' still in the plan-clamp skip
```

**Playtest:** same 48 yd chip, land short of the green, watch roll. Flat: dies near the plan rest, not 25 yd past. Downhill: can still run by.

---

## Phase 3 — Chip PERFECT is committed yards

Logged leftover from swing-input Phase 4: full-swing `contact_multiplier` PERFECT = 1.06 leaked onto chips (~3 yd on a 48 yd chip, stacked on the pad smash). Putt already identity on Green.

**Diff:** `contact_multiplier(..., shot_type)` returns 1.0 for chip PERFECT. Full/pitch/flop/punch stay 1.06. `resolve_distance` + `PuttStroke.grade` + `ShotReport.from_shot` pass shot type so F1 Plan matches launch.

---

## Out of scope

- Putt log map / `POWER_FLOOR` / `BAND_HALF`
- Pitch/full plan-distance clamp
- Camera / tracer (shipped `#56`)
- `CHIP_YD` 20 gate (48 yd bump-and-run still legal)
- Logged PERFECT chip +6% `contact_multiplier` — **shipped Phase 3**
- Chip execute-panel ticks past 20 yd (cosmetic; pad already accepts the pull)

---

## Order

1. Approve this doc.  
2. Phase 1 pad — shipped this PR.  
3. Phase 2 roll — shipped this PR (dump was both stacked).
4. Phase 3 chip PERFECT = 1.0 — shipped this PR (logged leftover, still long).

# Epic 1 — Hang Time and Apex From One Source

**Phase:** 1 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/flight-hang-time-apex`, from main after Phase 0 merges
**Prerequisite:** Phase 0 merged; harness verified faithful (deltas under 1.5% on device)
**Gameplay change:** large and intentional. Every ball in the game will fly visibly higher
and hang visibly longer.

---

## Why this phase exists

Three quantities that must be related are currently invented independently:

- `air_time` — a lerp between 0.55 and 1.15 multiplied by loft (`ball_physics.gd:632`)
- `apex` — a flat constant plus a speed term (`ball.gd:290`)
- `speed` — carry divided by air_time (`ball_physics.gd:~640`)

Because they are independent, they contradict each other. Measured on device: a full driver
apexes at **22.4 px** while a 3-yard chip apexes at **~39 px**. The shortest shot in the game
flies nearly twice as high as the longest. Hang time is inverted the same way — driver
**0.60 s**, sand wedge **1.57 s** — where real golf is nearly flat across the bag at 5–7 s
and falls slightly toward the wedges.

The `28.0` constant in the apex formula is the direct cause: it dominates the speed term
(which contributes 12 px on a driver and 0.1 px on a chip), so apex reduces to
*constant × loft_mul*. Since wedges carry the highest loft_mul, short shots fly highest.

This phase makes the three quantities one relationship instead of three guesses.

---

## The model

**Apex is the primary quantity. Hang time derives from it.**

This is a change from an earlier draft, which set hang time first — that produced a
non-monotonic bag (3-Wood apexing above Driver) because real *hang times* are noisy and
nearly identical across clubs, while real *apex heights* are cleanly ordered and are the
thing that actually matters here: apex is what determines tree clearance and what the player
sees on screen. Apex and hang are locked together by one equation, so only one can be
matched to real golf directly. We match apex.

```
apex = APEX_SCALE × REAL_APEX_FT[club] × power × SHOT_TYPE_SCALE
hang = sqrt(8 × apex / GRAVITY_PX)
speed = carry_px / hang
```

`apex ∝ power` is the physical relation: carry scales with the square of launch velocity and
so does apex, so a half-distance shot apexes at half height. Hang time then falls out as a
square root, which is why `short_shot_hang_scale` becomes redundant — the correct
relationship produces short-shot hang compression for free.

### Starting values (all playtest targets, not final)

```gdscript
## Real PGA Tour average max height in FEET, by club max_yards. Monotonic by construction —
## apex is the measured quantity we match; hang time derives from it. PLAYTEST TARGET.
const REAL_APEX_FT := {
	260: 102.0, 235: 95.0, 210: 94.0, 190: 93.0, 175: 92.0, 160: 92.0,
	145: 91.0, 130: 89.0, 110: 87.0, 95: 84.0, 80: 80.0, 65: 76.0,
}
## Game pixels per real foot of height. Sets how tall the bag flies. PLAYTEST TARGET.
const APEX_SCALE := 0.788
## apex = GRAVITY_PX * hang^2 / 8, inverted to get hang. THE master pacing knob —
## raising it shortens every flight coherently without touching a single club. PLAYTEST TARGET.
const GRAVITY_PX := 535.0
## Shot-type apex multipliers. PLAYTEST TARGETS.
const APEX_SCALE_CHIP := 0.70
const APEX_SCALE_PUNCH := 0.35
const APEX_SCALE_FLOP := 1.80
```

`GRAVITY_PX` is deliberately a single global. If a 1.05 s driver reads slow on a phone,
raising that one number recompresses the entire bag while preserving every relationship
between clubs. Do not introduce per-club pacing overrides — that reintroduces the coupling
this phase removes.

### Resulting table @ power 0.92

| Club | Apex px | Apex yd | Hang | Real apex yd |
|---|---|---|---|---|
| Driver | 73.9 | 32.9 | 1.05 | ~34 |
| 3-Wood | 68.9 | 30.6 | 1.01 | ~32 |
| 7-Iron | 66.7 | 29.6 | 1.00 | ~31 |
| PW | 63.1 | 28.0 | 0.97 | ~29 |
| Sand Wedge | 58.0 | 25.8 | 0.93 | ~27 |
| Lob Wedge | 55.1 | 24.5 | 0.91 | ~25 |

Monotonic across the full bag. Verified.

### Shot-type separation @ 20 yd, Lob Wedge

| Type | Apex px | Apex yd | Hang |
|---|---|---|---|
| chip | 12.9 | 5.7 | 0.44 |
| pitch | 18.4 | 8.2 | 0.52 |
| flop | 33.2 | 14.7 | 0.70 |

Chip runs, pitch flies, flop stops. Three distinct shots from one relationship.

## Changes

### 1. `scripts/ball/ball_physics.gd`

Add the constants above near the other tuning blocks.

Add one function that owns hang time:

```gdscript
## Hang time in seconds. THE single source — apex and launch speed both derive from this.
## Nothing else in the codebase may compute or scale air time.
static func apex_for(club_max_yards: float, power: float, shot_type: String = "full") -> float:
	var a := APEX_SCALE * _real_apex_ft_for(club_max_yards) * clampf(power, 0.01, 1.0)
	match shot_type:
		"chip": a *= APEX_SCALE_CHIP
		"punch": a *= APEX_SCALE_PUNCH
		"flop": a *= APEX_SCALE_FLOP
		_: pass
	return maxf(a, 0.01)


## Hang time in seconds, derived from apex. Nothing else may compute or scale air time.
static func hang_time(club_max_yards: float, power: float, shot_type: String = "full") -> float:
	return sqrt(8.0 * apex_for(club_max_yards, power, shot_type) / GRAVITY_PX)
```

`_real_apex_ft_for()` should look up `REAL_APEX_FT` by nearest `max_yards`, mirroring how
`club_loft_mul()` already does nearest-match at lines 28–38. **Reuse that pattern, don't
invent a second lookup.**

**Line 632** — replace the invented air_time:
```gdscript
var air_time := lerpf(0.55, 1.15, clampf(result.power, 0.0, 1.0)) * loft
```
with:
```gdscript
var air_time := hang_time(club_max_yards, result.power, shot_type)
```

**Line 634** — `air_time *= short_shot_hang_scale(total_yards)` is now redundant; `sqrt(power)`
handles short-shot hang natively and more correctly. **Delete the call.** Leave
`short_shot_hang_scale()` itself in place, unused, with a comment marking it dead — Phase 6
removes it after the harness confirms nothing regressed.

**Line 57** — `estimate_height_peak()` must use the same functions so UI previews match
flight. Replace its air_time lerp and its return expression with `hang_time()` and `apex_for()`.
Use the same power clamp as `apex_for()` (0.01–1.0), not the current 0.05 floor, so UI and
launch agree exactly. This function currently duplicates the launch math; after this change it
should call into it rather than mirror it.

Add `"apex"` to the dictionary returned by `launch_velocity()` so the ball no longer computes
its own.

### 2. `scripts/ball/ball.gd`

**Line 290** — this is the line that causes the inversion:
```gdscript
_height_peak = (28.0 + velocity.length() * 0.02) * loft_h
```
Replace with a read from launch data:
```gdscript
_height_peak = float(launch_data.get("apex", 0.0))
```
Keep the `_is_putt` override that zeroes it (lines ~294–296).

`loft_h` may become unused here — if so remove it, but check other references first.

### 3. `scripts/ball/flight_model_check.py`

Update the parser for the new constants and functions. It must parse `REAL_APEX_FT`,
`APEX_SCALE`, `GRAVITY_PX`, and the shot-type scales out of the `.gd` rather than
hardcoding them. Golden ranges are **unchanged and still frozen**.

---

## What this phase does NOT fix

State this plainly in the PR description so the playtest isn't misread:

- **Carry stays wrong.** Driver carry remains ~163 yd against a real ~250. Carry is
  `total × air_frac`, and `air_frac` is Phase 3's job. The `carry_yd` goldens for Driver and
  7-iron will still FAIL after this phase. That is correct and expected.
- **Total distance is unchanged.** Nothing in this phase touches `total_yards`.
- **Trees become trivially clearable.** Apex roughly triples while canopy heights stay at
  25/38/42. Phase 2 rebalances them. Expect this and don't tune around it.

---

## Expected feel change

Launch speed drops sharply on long clubs and barely moves on short ones:

| | Hang before → after | Speed before → after |
|---|---|---|
| Driver | 0.60 → 1.05 s | 603 → 344 px/s |
| 7-Iron | 1.09 → 1.00 s | 232 → 253 px/s |

**The pacing change is concentrated almost entirely in the long clubs.** A driver will feel
roughly half as fast; a 7-iron will feel the same. Judge the pacing question from the tee,
not from the fairway.

---

## Acceptance criteria

1. **Apex goldens PASS:** Driver, 7-iron, PW full; SW 20yd and 50yd pitch; SW 8yd and 3yd
   chip; `Driver > pine`; `7i > pine`; `Punch < short`.
2. **`carry_yd` goldens still FAIL** for Driver and 7-iron. If they pass, something outside
   this phase's scope was changed — investigate before merging.
3. **Apex ordering is correct bag-wide:** every full swing apexes higher than every chip, and
   apex rises monotonically from Lob Wedge to Driver at equal power. This is now guaranteed
   by construction — `REAL_APEX_FT` is monotonic — so a failure here means a lookup bug.
4. **Apex scales linearly with power.** At 0.46 power a driver apexes at half its 0.92 value.
   Today it barely moves — that is the `28.0` constant, and it must be gone.
5. **UI matches flight.** `estimate_height_peak()` and the actual `_height_max` agree within
   5% on a clean shot. They are the same functions now.
6. All `scripts/**/*_check.py` pass.
7. **On-device verification:** hit a driver and a greenside chip, screenshot both sparklines.
   The driver must peak above the pine line; the chip must sit near the floor. Compare to the
   Phase 0 before-images.

---

## Playtest verification order

1. Driver from the tee. Read hang and apex off F1. Confirm ~1.05 s and ~74 px.
2. **Answer the pacing question:** does a 1.05 s driver read slow on a phone? This is the
   whole reason `HANG_COMPRESS` is a single knob. If it drags, raise it and re-run — do not
   touch individual clubs.
3. Greenside chip with LW. Apex should be visually flat, near 1–2 px. The sparkline should
   look nothing like the driver's.
4. Punch under a short canopy. Must still duck under 25 px.
5. Flop with LW. Must apex clearly above a pitch of the same distance.
6. Half-power driver (~0.50). Apex should be roughly half the full-swing value.
7. Play three holes. Expect trees to feel too easy — that is Phase 2, not a bug.

---

## Notes for the agent

- Read this document and confirm your understanding before writing code.
- Touch only: `scripts/ball/ball_physics.gd`, `scripts/ball/ball.gd`,
  `scripts/ball/flight_model_check.py`. Nothing else.
- Do **not** adjust canopy heights, `air_distance_fraction`, `total_yards`, or any distance
  multiplier. Those are Phases 2 and 3.
- Report line-number drift as you did in Phase 0 — that was useful.
- If any constant needs to move from the starting values above to pass a golden, **report the
  proposed value and why rather than changing it silently.** Calibration is a design decision.

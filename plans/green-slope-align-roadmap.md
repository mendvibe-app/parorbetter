# Green slope align — Roadmap

**Status:** Phase 1–3 in tree. Device playtest skipped — Phase 2 book + Phase 3 variety shipped on the Phase 1 field. Spec: `plans/green-slope-align-phase1.md`.
**Owner:** Matt (playtest) → coding agent (one phase per PR)
**Origin:** Recon 2026-08-30. True-scale greens made stored slope look like ski slopes; break/pace still from the giant-ball era. Short-game roll on the green uses a third, unrelated constant.
**Board:** `plans/README.md`

Guardrails match putting/flight rebuilds: **one phase = one PR = one playtest.** Tuning constants are PLAYTEST TARGETS. Do not split field-shrink from gravity (putts go straight). Do not retune `PUTT_BREAK_*` without shrinking the field (banana putts).

---

## The decision

`HoleData.green_slope_at` is already **percent grade** (dimensionless rise/run: `0.02` = 2%). Treat it that way everywhere.

Real putting greens at our stimp-10 friction (`roll_friction_for("Green") = 1.8 ft/s²`):

| | Real (USGA / Pelz / AimPoint) | Game today (p50, 200-green probe) |
|---|---|---|
| Typical grade | 1–3%; ≥3% too steep for a **pin** at stimp 10 | **12.8%** median |
| Pin shelf | ≤3%, uniform 2–3 ft around cup | **18%** (`PIN_MAX_LOCAL_SLOPE = 0.18`) |
| Elevation across ~80 ft green | ~1–3 ft | **9.1 ft** |
| 20-ft 2% break | ~20 in | ~2 in at 2%; ~8 in on a *typical* green because the field is 8–18% |
| Downhill pace | 2% plays like stimp ~15.6 | almost a no-op (`PUTT_BREAK_ALONG` vs pin, ~5% of `g·sinθ`) |

The playable 8-inch break on a typical 20-footer is an accident: an 18% field fed into ~5% gravity. After true-scale, you can **see** the 9-ft hill. That is the “scale feels off” report.

**Short game is the same surface.** Chip/pitch/flop/full that land on the green already use `putt_decel_px()` for friction, then a **different** slope model (`velocity += slope * 16`). Off-green short-game roll ignores the green field. Anti-backup on non-putts (`velocity.dot(_pin_dir) < -20` → shove toward pin) fights false-front trickles.

One gravity owner for every ball on the green. Profiles stay (bowl / ridge / false front / bi-tier) — those are the fun. Intensity and physics change.

---

## Locked targets (playtest)

Grade = `green_slope_at(local).length()`.

| Knob | Target | Notes |
|---|---|---|
| Typical plane | **1–3%** | AimPoint 1 subtle / 2 standard / 3 severe |
| Rare architecture | **4–6%** local | ridge spine, tier step — not the whole green |
| False-front **face** | may exceed 6% in a **band** toward the tee | putting surface behind it back in 1–3% |
| Pin shelf | **≤ 3%**, uniform over ~3 ft | USGA holing-out area; `PIN_MAX_LOCAL_SLOPE ≈ 0.03` |
| Tap-in ceremony skip | **1 ft**, distance only | `tap_in_yd = 1/3` yd. No slope gate (`tap_in_break` removed). |
| Elevation span | **~1–3 ft** typical on an 80-ft green | 4–5 ft ok on bi-tier / false-front |
| Break | ~**1 in per foot per 2%** at stimp 10 | Pelz: `grade% × feet / 2` |
| Pace | downhill runs on; uphill dies | player reads it; **do not** auto-shift the putt/chip pad marker |
| Practice Green | known **~2% SIDE_SLOPE** demo | not mag `0.28` (today ~12% plane + 14 ft of fall) |
| Short Game station hole | **FLAT or ~2%**, not mag `0.18` + FLAT (today a 7.6% ramp) | |

Stored `green_slope` mag → plane grade via `GREEN_PLANE_WEIGHT` (0.42): **1% ≈ mag 0.024, 3% ≈ 0.071, 4% ≈ 0.095**. Generator range today is `0.08–0.30` (3.4–12.6% plane **before** contours).

Physics: delete pin-relative 90/55 split. Isotropic

```text
a_px = 32.174 ft/s² × grade × FT_TO_PX / ROLL_DURATION_FRAC² × pace_k²
```

`pace_k = PUTT_PACE_SCALE` whenever friction is `putt_decel_px()` (putt **and** any lie==Green roll). Same k² already keeps bend yard-correct when FRAC/pace move — replaces `PUTT_BREAK_CAL_DECEL`.

---

## Why putt + chip + pitch + flop share Phase 1 physics

Roll on green, current fork in `GolfBall._process_roll`:

```
if putt:    slope · right × 90, slope · pin × 55,  × putt_decel/108
elif Green: slope × 16
# then everyone on Green uses putt_decel_px()
```

`16` is ~18× putt lateral at today’s `break_scale`. Chips that hop onto the green get yanked sideways; putts on the same slope barely curve; downhill chips do not run out like downhill putts.

Real chip is a putt that hops. Pitch/flop are carry then a short green roll. Approach rollout is the same green. **One `BallPhysics.green_slope_accel(slope)`.** Wiring all on-green rolls in the physics PR means we do not retune `16.0` after the field shrinks.

Out of scope for this epic: fairway/rough slope fields (we do not have them). Off-green, slope accel stays 0.

---

## What else fights a real read

1. **Green book wash min–max normalizes per green** — 2-ft tilt and 12-ft canyon both paint full blue→red. Arrow min `0.04` hides 1–2% fall lines.
2. **`ContourProfile.FLAT` still applies the plane** unless mag is 0. Generator zeros mag; `_make_short_game_hole` does not (`green_slope = (0.18,0)` + FLAT).
3. **Non-putt anti-backup** kills trickle-back on false fronts / down-tiers.
4. **`green_slope_field_check.py` is stale** (still asserts mag `0.10–0.48`) and does not apply plane weight / contour boost — it is not testing the live field.
5. **Putt/chip pad marker is pin-distance only.** After pace becomes real, downhill with a flat marker runs long — that is the skill. Do not “fix” the marker in this epic.

---

## Phases

### Phase 0 — this doc — LOCKED when Matt signs off

No code. Confirms: grade units, gravity formula, one on-green owner, short game in the physics PR, pin/book as a later phase.

### Phase 1 — Honest field + gravity on every green roll

**The coupled pair. Do not split.**

Field (`hole_generator.gd`, `hole_data.gd`):

- Non-flat mag into the 1–3% plane band (rare up to ~4% via theme `slope_mult` / jitter). PLAYTEST: `lerpf(0.024, 0.08, rng.randf())` as the starting range.
- Cut `GREEN_CONTOUR_AMP_SCALE` toward **1.0** (was 1.55) so bumps follow mag down into 1–3 ft spans. False-front / bi-tier amps may stay relatively stronger than side-slope — still not 10+ ft across.
- `PIN_MAX_LOCAL_SLOPE := 0.03`. `tap_in_break := 0.01`.
- Practice Green: ~2% SIDE_SLOPE (stored mag ~`0.048`). Short Game hole: FLAT with **zero** mag (or the same 2% SIDE_SLOPE if we want a read there).
- Keep the six profiles. Do not ramp mag with `t` yet (Phase 3).

Physics (`ball_physics.gd`, `ball.gd`):

- Add `green_gravity_px(pace_k)` + `green_slope_accel(slope, pace_k) -> Vector2`.
- `_process_roll`: if `_is_putt or _lie == "Green"`: `velocity += green_slope_accel(slope) * delta`. Delete `PUTT_BREAK_LATERAL` / `ALONG` / `PUTT_BREAK_CAL_DECEL` / `slope * 16`.
- On green, skip the non-putt anti-backup shove. Off-green, keep it.
- Launch / air / `air_distance_fraction` untouched (chip still ~20–33% air, pitch ~0.90, flop ~0.92+).

Checks (ponytail: one new file for the non-trivial physics, plus patch the stale ones):

- New `scripts/ball/green_slope_physics_check.py`: 2% 20-ft dying putt breaks in a Pelz band (~15–25 in, not 2 in); downhill 2% 20-ft runs past a flat-sized launch; chip-on-green and putt call the same helper; `slope * 16` gone.
- `green_slope_field_check.py`: mag range, plane weight, contour scale, elevation-span ceiling, pin grade ≤ 3% on the probe.
- `pin_placement_check.py` / `putt_pace_check.py`: new literals.

**Playtest:** Practice Green 20-ft sidehill should need a cup-or-two of aim and a real pace change uphill vs downhill. Chip from the collar onto the same slope should **release like that putt**, not get yanked. False-front pitch that lands short of the ridge can trickle back.

**Expected:** early-round SIDE_SLOPE still dominates mix (Phase 3). Book still stretches contrast (Phase 2).

### Phase 2 — Read: book, arrows, pin shelf honesty — SHIPPED

Device playtest skipped; shipped on the Phase 1 field.

Only after Phase 1 feel is signed off (otherwise we paint a field we are about to retune).

- Green book wash: **fixed height span** (PLAYTEST ±2 ft) or grade-based color — not per-green min–max.
- `GREEN_BOOK_ARROW_MIN_SLOPE := 0.01` (show 1% fall lines). Arrow length still scales with mag.
- Pin picker: keep 5-pace edge margin; make the 3% shelf a hard-enough reject that mid/high contours still find a holeable cup (today almost everything scores ~0.18).
- AGENTS.md constant table + `decisions.md` line once numbers stick.

**Playtest:** a 1% green looks calm; a 3% + ridge looks like a book. Pins are holeable without looking like they sit in a drain.

### Phase 3 — Variety without fake steepness — SHIPPED

False-front face localization **SHIPPED** (narrow tee-side bump, no pin dip). Mag hi capped at `PIN_MAX / GREEN_PLANE_WEIGHT` so the plane cannot exceed the cup shelf. Pin-following dips removed on SIDE_SLOPE / BI_TIER / FALSE_FRONT.

Intensity was `randf()` every hole; FLAT was cut so break would “show up.” After physics is real, 1–2% is visible.

- Restore early FLAT / gentle side-slope weight; keep false-front / bi-tier as late unlocks.
- Ramp **mag** with `difficulty_t` (easy 1–2%, late 2–3% with rare 4%). Theme `slope_mult` stays.
- Optional: localize false-front amp so the **face** is the steep band, pin-side shelf stays ≤3%. **Done** — face at `+Y·0.55`, σ=`rmin·0.18`, amp=`base·rmin·0.45`; pin dips deleted.

**Playtest:** hole 1 can be a straight putt; hole 18 can be a 3% bi-tier with a back pin. Chip/pitch into a late false front is the hard short-game exam.

---

## Out of scope

- Putt line / contact / camera / cup capture (putting rework + true-scale, shipped).
- Pad marker slope compensation (player reads pace).
- Rest-circle slope rundown — **SHIPPED** (`BallPhysics.preview_green_roll`; yellow rest walks on-green grade). White carry ring stays first-bounce.
- Fairway/rough contour fields.
- Stimp as a player-facing setting (friction stays 1.8).
- New contour profiles, designer meshes (existing `ponytail:` on `_green_slope_influences`).
- Flight / apex / hang.
- Handicap `course_slope` (different word).

---

## Files (Phase 1)

| File | Why |
|---|---|
| `scripts/ball/ball_physics.gd` | gravity helper; delete `PUTT_BREAK_CAL_DECEL` |
| `scripts/ball/ball.gd` | one on-green accel; drop 90/55 and `* 16`; green anti-backup |
| `scripts/course/hole_data.gd` | contour amp; comment that `slope_at` is grade |
| `scripts/course/hole_generator.gd` | mag range; `PIN_MAX_LOCAL_SLOPE` |
| `scripts/course/hole_controller.gd` | practice / short-game hole slopes |
| `scripts/autoload/game_state.gd` | `tap_in_break` |
| `scripts/ball/green_slope_physics_check.py` | **new** |
| `scripts/course/green_slope_field_check.py` | un-stale |
| `scripts/course/pin_placement_check.py` | 0.03 |
| `scripts/ball/putt_pace_check.py` | break-const asserts |

Phase 2 adds `hole_controller.gd` book constants only. Phase 3 is generator weights.

---

## Acceptance (epic, after Phase 3)

- Median generated green grade in 1–3%; pin grade ≤ 3% on a 200-hole probe.
- 20-ft 2% putt breaks on the order of a cup-and-a-half to two cups, not two inches and not ten feet.
- Uphill 20-ft needs a clearly longer stroke than downhill.
- Chip/pitch/flop that land on the green use the same accel as a putt on that lie.
- Practice Green is a readable 2% classroom, not a 14-ft mound.
- `for f in scripts/*/*_check.py; do python3 "$f" || break; done` green.

---

## Pickup

Next agent: write `plans/green-slope-align-phase1.md` with exact literals, then implement. Do not start Phase 2 book work in that PR.

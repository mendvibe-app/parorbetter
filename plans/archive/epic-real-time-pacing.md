# Epic: Real-time pacing

**Status: SHIPPED 2026-08-15** (`feature/rough-pacing-greens-stack`).
**Playtest dial:** started `FLIGHT_DURATION_FRAC=0.65` (too slow on device) → **0.45**
(~2.25 s driver hang; ~45% model-real / ~36% Tour avg ~6.2 s).
**Scope:** Timing constants in `ball_physics.gd` / `ball.gd`. No distance, dispersion, or
apex changes.
**Risk:** Phase 1 low (verified isolated). Phases 2–3 medium (friction values need
re-derivation, not just a unit fix).

---

## 1. Answer: flight runs at 22% of real duration

This is not "we tuned it snappy." It's a units bug, and the same bug appears twice more.

### 1a. Gravity

**`scripts/ball/ball_physics.gd:263`**
```gdscript
const GRAVITY_PX := 535.0
```

Apex is stored in game px via `APEX_SCALE := 0.788` — px per **real foot** of height.
So gravity in those same units must be:

```
32.174 ft/s²  ×  0.788 px/ft  =  25.35 px/s²
```

We use **535**. That's **21.1× too strong**. Hang scales as `1/√g`, so flight runs
**4.59× too fast**, i.e. at **22% of real duration**.

| Club | Apex | Current hang | Real hang |
|---|---|---|---|
| Driver | 102 ft | 1.10 s | **5.04 s** |
| 5-Iron | 93 ft | 1.05 s | 4.81 s |
| 7-Iron | 92 ft | 1.04 s | 4.78 s |
| PW | 87 ft | 1.01 s | 4.65 s |
| SW | 80 ft | 0.97 s | 4.46 s |

Broadcast reference: a Tour driver is in the air 5–6 s. Our parabolic model gives 5.04 s
at true gravity, which is right (real is slightly longer because drag makes descent
steeper than ascent — we don't model drag, and shouldn't start here).

### 1b. Roll — same error, twice as bad

**`ball_physics.gd:895`** and **`ball.gd:603`**
```gdscript
landing_speed = sqrt(2.0 * roll_friction_for(lie) * 60.0 * roll_px)
velocity = velocity.move_toward(Vector2.ZERO, friction * 60.0 * delta)
```

`roll_friction_for()` returns 1.8 (Green) / 2.4 (Fairway) / 4.5 (Rough) / 7.0 (Sand).
**Green = 1.8 ft/s² is exactly the real stimpmeter deceleration for a stimp-10 green**
— a 6.0 ft/s ball rolling 10 ft gives `a = 36/20 = 1.8`. Whoever wrote these knew the
real number. They're ft/s².

To convert ft/s² → px/s² the multiplier is `PX_PER_YARD / 3 = 0.75`, not `60.0`.
We're **80× too strong** → roll runs **8.94× too fast**, at **11% of real duration**.

### 1c. Putting

**`ball_physics.gd:818`**
```gdscript
# Green roll decel ≈ 1.8 * 60 = 108
var putt_speed := sqrt(2.0 * 108.0 * maxf(total_px, 1.0))
```

The comment shows the arithmetic and the wrong conversion in one line. A 30-ft putt:

| | Decel | Time to stop |
|---|---|---|
| Current | 108.0 px/s² | 0.65 s |
| Correct | 1.35 px/s² | 5.77 s |

## 2. Why it feels wrong in a specific way

Flight is at 22% of real. Roll is at 11%. **Roll is roughly twice as compressed as
flight.** So the ball doesn't just fly fast — it flies fast and then *skitters*, at
double the relative speed of the flight that preceded it.

That internal inconsistency is likely doing more damage to the feel than either number
alone. A world can be stylized-fast and still feel coherent; it cannot feel coherent
when its two halves run on different clocks.

## 3. Verified: `GRAVITY_PX` is a safe, isolated knob

Traced before proposing anything. Changing it does **not** touch:

- **Carry/total distance** — `total_px` comes from `resolve_distance()`, which never
  reads gravity.
- **Roll distance** — `roll_px = total_px * (1.0 - air_frac)`; no gravity term.
- **Landing speed** — `sqrt(2 * roll_friction_for(lie) * 60.0 * roll_px)`; derived from
  roll distance and lie friction only. **Independent of hang.**
- **Dispersion / shape / spin** — all derived from `intended_shape`, `force`, contact.
- **Apex** — `apex_for()` is upstream of `hang_time()`, not downstream.

The only coupled value is `base_speed = air_px / air_time`, which falls proportionally
as hang rises. That is correct: same carry, more time, slower horizontal speed.

The code comment at `:261` already claims this ("THE master pacing knob — raise to
shorten hang without changing apex ordering"). **Confirmed accurate.**

## 4. The fix

### Phase 1 — Flight only

Stop hardcoding gravity. Derive it from a named duration target so the realism fraction
is explicit and reviewable:

```gdscript
## Real gravity expressed in apex px: 32.174 ft/s² × APEX_SCALE.
const GRAVITY_REAL_PX := 25.35
## Fraction of real-world flight duration. 1.0 = broadcast-accurate.
## PLAYTEST TARGET — start 0.65, walk toward 1.0 if it reads well on device.
const FLIGHT_DURATION_FRAC := 0.65
const GRAVITY_PX := GRAVITY_REAL_PX / (FLIGHT_DURATION_FRAC * FLIGHT_DURATION_FRAC)
```

| `FLIGHT_DURATION_FRAC` | `GRAVITY_PX` | Driver hang |
|---|---|---|
| 0.22 | 535 | 1.10 s — current |
| 0.35 | 207 | 1.76 s |
| 0.50 | 101 | 2.52 s |
| **0.65** | **60** | **3.27 s** |
| 0.80 | 40 | 4.03 s |
| 1.00 | 25.4 | 5.04 s |

**Recommend starting at 0.65, not 1.0.** Real is 5 s of airtime per full shot, and with
~40 full shots a round that's ~2.6 min of added watching. 0.65 buys most of the
weight — a 3× slowdown from today is enormous perceptually — without committing to
broadcast length before we've felt it on a phone. Walking up is cheap; walking back
after retuning the camera around 1.0 is not.

Because hang derives from `apex_for()`, which already carries shot-type multipliers
(chip 0.70, punch 0.35, flop 1.80), **this one constant slows every shot type
proportionally.** Matt's "all shot types feel fast" is one knob.

### Phase 2 — Roll unit fix + friction re-derivation

⚠ **Do not just change 60.0 → 0.75.** That would be the correct unit and the wrong
result, because this model folds *bounce* into "roll." Real roll-out after a drive sheds
most of its energy in the first two bounces; our model has no bounce, so it must use a
higher effective deceleration than pure rolling friction.

At a true 0.75 multiplier, a 30-yd fairway roll-out would take **8.7 s**. Real is 4–6 s.

So Phase 2 is two changes that must land together:
1. Replace `60.0` with a named `FT_TO_PX := PX_PER_YARD / 3.0` in both call sites.
2. Re-derive non-green friction values as *effective* decelerations including bounce
   loss. Fairway is probably 8–12 ft/s², not 2.4. **Green stays 1.8 — it's verified
   real and there is no bounce on a putt.**

Roll duration should end up on the same `_DURATION_FRAC` as flight. That coherence is
the point of the epic.

### Phase 3 — Putt pace

Pure unit fix; green friction 1.8 is already correct. Replace the literal `108.0` with
`1.8 * FT_TO_PX` scaled by the shared duration fraction.

At full real, a 30-ft putt takes 5.77 s (real ≈ 4–5 s; ours runs slightly long because
real greens decelerate non-linearly). Acceptable. If it drags, that's an argument for a
duration fraction below 1.0 globally, not for reintroducing a wrong constant.

---

## 5. Out of scope — do not touch

- `APEX_SCALE`, `REAL_APEX_FT`, and every apex multiplier. Apex is correct and was hard
  won in the flight-model rebuild. **This epic changes how long the ball is in the air,
  never how high it goes.**
- `resolve_distance()`, `air_distance_fraction()`, carry/roll split.
- Dispersion, spin, `force_factor`, contact quality.
- Camera work. See risk below.
- The green-sizing and rough-layering epics. Different PRs.

## 6. Risks

- **Camera is tuned around 1.1 s flights.** `FLIGHT_LAUNCH_FRAC` / `FLIGHT_APEX_FRAC` /
  `FLIGHT_LAND_FRAC` interpolate across the flight; at 3× duration those transitions
  will feel slow and may need their own easing pass. **Do not fix that inside this
  epic** — land the pacing, playtest, then write a camera correction if needed. It also
  overlaps the pending approach-camera-zoom doc.
- **Tracer / trail length** may look sparse or over-long at 3× duration.
- **Contact-quality haptics** (epic pending) fire on strike, not landing — should be
  unaffected, but confirm if both land near each other.
- **Wind.** Longer hang means wind acts for longer if wind is applied per-frame. Check
  whether wind is a launch-time offset or an integrated force. If integrated, drift will
  scale with duration and effective wind strength will silently triple.

## 7. Acceptance criteria

**Phase 1**
- Driver at full power, GOOD contact: hang matches the table for the chosen
  `FLIGHT_DURATION_FRAC` within 5%.
- **Carry and total distance are byte-identical to pre-change for a fixed seed.** This is
  the critical regression — if distance moved, gravity leaked somewhere it shouldn't.
- Apex height in px unchanged for every club and shot type.
- Landing speed and roll-out distance unchanged.
- Chip, pitch, flop, and punch all slow by the same factor as full. Verify flop (1.80
  apex mult) and punch (0.35) specifically — they bracket the range.
- Wind drift per shot unchanged (see §6).

**Phase 2**
- 30-yd fairway roll-out lands in the 4–6 s range.
- Roll and flight duration fractions match.
- Total distances unchanged — friction affects *how long* roll takes, and `roll_px` is
  already owned by `resolve_distance()`. If roll distance moves, the change is wrong.

**Phase 3**
- 30-ft putt stops in ~5 s at full real.
- Putt distances unchanged. Amplitude still owns pace.

## 8. Handoff notes

- Agent reads this doc and confirms understanding before writing code.
- **Three phases, three PRs, three device playtests.** Pacing is pure feel; bundling
  makes it impossible to attribute. This is exactly the failure mode from the short-game
  roadmap.
- Phase 1 alone will make the game feel dramatically different. Playtest it on its own
  before deciding whether Phases 2–3 need different duration fractions.
- Matt confirms `FLIGHT_DURATION_FRAC` before handoff.
- Every new constant gets a `## PLAYTEST TARGET` comment.

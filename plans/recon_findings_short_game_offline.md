# Recon Findings: Short-Game Shots Land Offline From Aim

**Status:** Phase 1 implemented — see `plans/short-game-wind-offline-phase1.md`.  
**Method:** Cloned `mendvibe-app/parorbetter`, read source directly. All line numbers below are from the current HEAD. Nothing here is inferred from design docs.

**Verdict:** Root cause found and confirmed. It is **wind**, applied as an unscaled acceleration during flight and then renormalized in a way that turns it into a pure heading rotation. On a chip it rotates the ball roughly **60 degrees off the aim line**.

My earlier hypotheses from the telemetry — fixed-amplitude curve visual, carry/roll heading mismatch, hidden RNG — are all **wrong**. Discard them. The shape system is behaving correctly and is not involved.

---

## Finding 1 — PRIMARY: wind rotates slow shots off-line

### The mechanism

`scripts/ball/ball.gd:622-634`, in `_process_flight()`:

```gdscript
var wind_force := 6.0 * sqrt(BallPhysics.GRAVITY_PX / 535.0)
velocity += wind * delta * wind_force
...
if velocity.length_squared() > 0.0001:
    velocity = velocity.normalized() * minf(target_spd, peak_spd * 1.02)
```

Two lines, two problems, and they compound:

1. **Wind is an absolute acceleration.** It adds the same lateral velocity per second regardless of how fast the ball is moving. A drive at 300 px/s and a chip at 32 px/s receive an identical push.
2. **The result is then renormalized back to target speed.** Magnitude is restored, direction is kept. So wind costs the ball nothing in distance — **it only steers.** And because the steering effect is a *ratio* of lateral push to forward speed, its angular impact scales inversely with ball speed.

Slow shot, same wind, vastly more rotation. Chips are the slowest shots in the game.

### The numbers, from your own readout

Your captured shot: `launch 32 px/s · hang 0.93s`. Hole 5 of 18.

Wind for that hole (`scripts/course/hole_generator.gd:362-368`) is `lerpf(4.0, 52.0, t)` where `t` is hole progress, times a 0.85–1.15 roll, at a **fully random angle** (`randf_range(0.0, TAU)`) with no attenuation toward crosswind. Hole 5 lands around **15 px/s**.

With `GRAVITY_PX` at its current derived value of 150.8, `wind_force` computes to **3.19**. Simulating the actual per-frame loop at 60fps for the full 0.93s hang:

| Wind (px/s) | Heading rotation off aim |
|---|---|
| 13.0 | **56 degrees** |
| 15.3 | **62 degrees** |
| 17.6 | **67 degrees** |

That is on hole 5, where wind is still mild. By hole 18 the magnitude reaches ~52 px/s and the ball is steered essentially straight downwind.

### Why it looks like an arc, then a straight roll

`scripts/ball/ball.gd:365`:

```gdscript
wind = Vector2.ZERO if _is_putt else p_wind
```

Putts are exempt from wind. **Chips are not.** And wind is applied only in `_process_flight()` — I checked `_process_roll()` (lines 700-740) and there is no wind term there at all.

So: the 6 yd carry curves progressively as the heading rotates, then the ball lands and the 19 yd roll proceeds dead straight along whatever heading wind left it with. That is exactly the shape you described, and it is the single most diagnostic detail in your report.

Rough finish position for your captured shot: with roll of 19 yd running out at ~62 degrees off line, the ball ends up somewhere around **17 yd offline** on a 25 yd chip. Wildly offline is the correct description.

Secondary effect: the settle check at `ball.gd:733` uses `along >= _planned_distance_px`, where `along` is the projection onto the *original* launch direction (`_traveled_along()`, line 604). A deflected ball has to travel further before its projection reaches plan, which is part of why you saw `Plan 25 yd → Actual 27 yd`.

### Why it hits the short game hardest

Real golf grounding: a 6-yard chip that never gets more than a couple feet off the ground is **effectively immune to wind**. There is no air time and no exposure. A 250-yard drive with 6 seconds of hang and an 80-foot apex is where wind actually lives. The current model has this exactly inverted in effect — not by intent, but because absolute acceleration divided by a tiny forward speed produces enormous angular change.

Note also that apex is not an input to the wind term at all. A flop that climbs and a punch that stays under the branches get identical wind treatment. That is worth fixing in the same pass.

---

## Finding 2 — The aim preview promises a straight shot it cannot deliver

`scripts/course/hole_controller.gd:2658-2678`:

```gdscript
func _aim_rest_point(...) -> Vector2:
    var bearing := to - from
    return from + bearing.normalized() * BallPhysics.yards_to_pixels(total_yd)
```

`_aim_carry_land_point()` is the same shape. Both project **purely along the aim bearing.** There is no lateral wind term in either.

Power solving does account for wind (`solve_committed_power` takes it), so the *distance* preview is wind-aware. The *line* preview is not. The game draws a target where the ball would go in still air, then applies a 60 degree rotation to the actual shot.

This is why "ball didn't land anywhere near where it showed it might" — the preview isn't lying about the physics it knows, it just doesn't model the term that dominates the outcome.

Incidentally, this also identifies the two circles in your screenshot: the small white one near the ball is `_aim_carry_land_point` (first bounce) and the large yellow one at the pin is `_aim_rest_point` (where it finishes). That distinction is correct design for a chip and worth keeping — carry and finish genuinely are far apart on a 6-yd-carry, 19-yd-roll shot.

---

## Finding 3 — Your telemetry cannot see line error at all

This is why the bug survived this long, and I'd argue it's the most important thing to fix first.

`scripts/debug/debug_controls.gd:358` renders `Aim ○ %d yd` from `m.get("aim_radius_yd", ...)`.

**That is the aim circle radius, not aim error.** The `○` is literally a circle glyph. "Aim ○ 1 yd" means "the aim circle has a 1 yard radius." It says nothing about whether the shot went where you aimed.

And `aim_offset` — the `long 3 yd` in your readout — comes from `AimControl.aim_offset_label()` (`scripts/shot/aim_control.gd:178-195`), which measures **where you aimed relative to the pin**, before the shot. Also pre-shot intent.

So every directional number in the readout — `Path`, `Shape lat`, `swipe`, `pull`, `blend`, `Aim ○`, `aim_offset` — describes **inputs and intent**. Not one of them measures the resting position against the aim point. The readout showing all zeros was accurate: your swing was clean. It simply has no field that could have reported the ball ending up 17 yards sideways.

**Fix this before fixing the physics**, or you have no instrument to verify the physics fix with.

---

## Finding 4 — The landing-circle sizing epic appears already shipped

`BallPhysics.short_game_aim_radius_yards()` (`scripts/ball/ball_physics.gd:243-264`) already exists, with a distance-lerped per-shot-type table matching the benchmarks from yesterday's epic: chip 0.67→1.33 yd (2–4 ft), pitch 1.67→3.33 yd (5–10 ft), flop 2.0→4.0 yd (6–12 ft). The comment references `epic_short_game_landing_circle` by name. `GameState.get_aim_radius_yards()` (line 341) branches correctly on chip/pitch/flop.

So the sizing epic is done. **Archive the version I wrote yesterday** before it reaches an agent — per your own rule about conflicting instructions on the same constant.

Two things it does not resolve, though:

- The header comment on line 240-241 states plainly: **"Display only; does not drive launch dispersion."** The circle is a promise the physics never made. Given Finding 1, it's a promise the physics actively breaks.
- Your reported `aim_radius_yd` of 1 yd is *correct* for a chip under this table — 3 ft radius. But the circle in your screenshot reads far larger than 6 ft across. Either the drawn circle isn't bound to this value, or camera zoom and the known oversized-green issue are distorting the read. **I could not resolve this from source alone; it needs a live measurement.** Print `_aim_radius_yd` on screen during a chip aim and compare against the drawn circle. Don't let anyone "fix" the table until that measurement exists — the table matches real golf and may be innocent.

---

## Proposed fix — one phase, one PR

**Phase 1: exempt or scale wind by exposure.**

The principle: wind authority should be a function of **air time and apex**, not a flat acceleration. Options in order of preference:

1. Scale the wind term by hang time and apex relative to a full-swing reference, so a 0.93s / 17px-apex chip receives near-zero and a driver is unchanged.
2. Simpler interim: exempt chip and putt entirely, scale pitch and flop down hard. Less principled, ships faster, and is defensible — a chip really is close to wind-immune.

Whichever you pick, **do not renormalize the velocity back to target speed after applying wind.** That step is what converts a drift into a rotation. Real crosswind displaces a ball and costs it a little distance; it does not swivel the velocity vector and hand back full speed.

**Phase 2 (separate PR): make the preview honest.** Once wind authority is sane, add the residual lateral drift to `_aim_rest_point` and `_aim_carry_land_point` so the drawn target reflects the shot the game will actually hit. Do not attempt this before Phase 1 — you'd be modeling a bug.

**Phase 0 (do first, tiny): add a real line-error readout.** Resting position vs aim point, signed left/right, in yards. Rename the existing `Aim ○` field so it can't be misread as error again.

---

## Do not touch

- `scripts/shot/tempo_gesture.gd`, `tempo_grade.gd`, `putt_stroke.gd` — the shape and path systems are correct and not implicated
- `short_game_aim_radius_yards()` and the radius table — pending the live measurement in Finding 4
- `GRAVITY_PX`, `FLIGHT_DURATION_FRAC`, roll friction — pacing epic owns these, and `wind_force` is already scaled off `GRAVITY_PX` so the two will interact; sequence carefully
- Putt break, cup capture, lip-in
- Green sizing / generation

---

## Acceptance criteria

1. A chip struck with `blend +0.00` finishes within ~1–2 yd lateral of the aim point **in any wind on any hole**. Test on hole 18 where wind magnitude peaks, not just hole 5.
2. Full-swing wind behavior is visibly unchanged — a driver in crosswind still drifts meaningfully. This fix must not neuter wind as a mechanic.
3. Flop drifts more than chip at equal distance; punch drifts less than full. Apex earns its wind exposure.
4. New line-error readout reports non-zero when the ball misses the aim line, verified by deliberately hitting a shaped shot.
5. Regression record: the hole 5 lob wedge chip, screenshot plus debug readout, before and after.

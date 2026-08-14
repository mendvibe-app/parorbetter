# Epic 5 — Speed as an Input; Delete the Disagreement

**Phase:** 5 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/speed-as-input`, from main after Phase 4 + bag-calibration corrections
**Gameplay change:** curved shots cost distance honestly. Short pitches with sidespin stop
losing half their planned distance. Flight and roll end for one reason each, not several.

---

## What's still standing after Phases 1–4

The apex/hang/carry work fixed *how far and how high* the ball goes. It never touched *how
the ball gets there*, and the code that decides that still has the exact shape the roadmap
described at the start of this project — verified against current `main`:

**Speed is still an output, computed by dividing a distance by a time:**

```gdscript
// ball_physics.gd:739
var base_speed := air_px / maxf(air_time, 0.05)
```

`air_px` and `air_time` are both already decided before this line runs. Speed doesn't cause
the flight — it's back-calculated to make a pre-planned distance and a pre-planned hang time
agree. Nothing about the ball's actual forward motion determines how fast it launches.

**Flight ends for up to three different reasons, simultaneously:**

```gdscript
// ball.gd:534
if collision or t >= 1.0 or along >= air_limit or path_len >= air_limit:
    _begin_roll()
```

A timer, a straight-line distance check, and a curved-path-length check are all watching for
the same event. Whichever fires first wins, and which one that is depends on wind and spin —
not on anything the player did.

**Three separate systems compensate for the same problem — sidespin eating forward
progress on slow shots:**

1. `spin_scale` (`ball.gd:513`) — clamps spin's effect by forward speed, 0.08 to 1.0
2. `short_shot_line_scale()` (`ball_physics.gd:633`) — a second, independent dampener on the
   same lateral/spin effect, scaled by total distance instead of speed
3. The reverse-guard (`ball.gd:517-520`) — a hard floor that stops the ball going backward or
   sideways past 85% of its forward speed, papering over whatever the first two didn't catch

All three exist because the same underlying cause — spin curvature applied as a fixed
per-frame velocity addition, undamped by how fast the ball is actually moving — was patched
three times instead of fixed once. This is the exact "don't double-penalize" failure named in
the project's own principles: one fault taxed through multiple independent paths.

**Roll has its own version of the same pattern:**

```gdscript
// ball.gd:624-626
var remain := _planned_distance_px - along
if remain < 40.0 and not _is_putt:
    var limit := maxf(remain * 3.5, 8.0)
    if velocity.length() > limit:
        velocity = velocity.normalized() * limit
```

A hard speed clamp inside the last 40 px of the planned roll, unrelated to friction, whose
only job is forcing the ball to stop near where the plan said it would — regardless of how
fast it's actually still moving.

---

## The model

**Launch speed becomes a real input, computed once, from club and power — not from dividing
carry by hang time.**

```gdscript
## Launch speed in px/s. THE single source — carry and hang time are consequences of this,
## not the other way around. Nothing else may compute or scale launch speed.
static func launch_speed_for(
	club_max_yards: float, power: float, shot_type: String = "full", contact: String = "GOOD"
) -> float:
	var hang := hang_time(club_max_yards, power, shot_type, contact)
	var apex := apex_for(club_max_yards, power, shot_type, contact)
	# Forward speed such that a symmetric parabola of this hang time and apex covers
	# exactly the planned carry — same physical relationship as today, computed once,
	# in the direction that makes it an input rather than a division.
	return (planned_carry_px(club_max_yards, power, shot_type)) / maxf(hang, 0.05)
```

This looks similar to the current `air_px / air_time` line — deliberately. **The formula
doesn't need to change; its role does.** Today it's the last step of a chain that starts from
a planned distance. After this phase, it's step one: speed is decided first, and *everything
downstream* — where the ball actually ends up, including the effect of spin — falls out of
integrating that speed forward, rather than being forced to match a pre-decided distance.

**Spin curvature must be genuinely speed-proportional, not clamped.** Real aerodynamic
sidespin force scales with the square of airspeed. The current per-frame addition
(`spin * 28.0 * delta`) is a fixed lateral acceleration regardless of how fast the ball is
moving — which is *why* it needed three separate patches to behave reasonably at low speed.
Replace it with a force that is naturally small when the ball is slow, because the ball is
genuinely moving slowly, not because something clamped it:

```gdscript
velocity += flight_right * spin * SPIN_CURVE_COEFF * along_spd * delta
```

Multiplying by `along_spd` instead of a flat constant means a soft 20-yard pitch curves
gently because it's moving gently — the same physical reason a real ball barely curves off a
delicate shot. No clamp required; the physics produces the damping.

**Flight ends for exactly one reason: reaching planned carry, measured along the actual
curved path.** Drop the timer and the straight-line distance check; keep only the path-length
condition, since it already correctly handles curved flight:

```gdscript
if collision or path_len >= air_limit:
    _begin_roll()
```

`t >= 1.0` is now redundant — with speed and apex both correctly derived from the same hang
time, the ball reaching its planned distance and the timer expiring should coincide. If they
don't, that's a real bug to find, not something to paper over with a second exit condition.

**Roll ends from friction alone.** Remove the `remain < 40` clamp. If friction values are
tuned correctly, the ball should naturally settle near its planned distance without a hard
override. If it doesn't, that's a friction-tuning finding, not a reason to keep forcing it.

---

## Why this fixes the low-speed sidespin bug without a special case

The original finding: a slow short pitch with sidespin lost roughly half its planned
distance, because the curvature force consumed a disproportionate share of the ball's total
velocity budget. That happened because curvature was a **fixed** addition regardless of
speed — slow ball, same sideways kick, so the kick was a bigger fraction of the total.

Once curvature scales with `along_spd`, a slow ball gets a proportionally small kick for the
same reason a slow ball has a proportionally small kick in real aerodynamics. The bug and its
three patches share one root cause; fixing the cause should retire all three at once.

---

## Sequencing within this phase

Order matters — each step should be independently verifiable before the next:

1. Add `launch_speed_for()`. Wire it into `launch_velocity()` alongside the existing
   `base_speed` line, but **do not yet remove the old line or change any termination logic.**
   Assert the two produce the same value for every current golden shot. If they don't
   diverge, the refactor is a no-op so far and safe to build on.
2. Replace the spin curvature formula with the speed-proportional version. Verify the
   documented low-speed pitch case (~13 yd, path ~-0.22) no longer loses half its distance,
   **before** touching termination logic — isolate whether the curvature fix alone resolves
   it.
3. Remove the reverse-guard (`ball.gd:517-520`). Confirm the speed-proportional curvature
   makes it unnecessary — if the ball still reverses past the launch line under any tested
   spin/power combination, the guard was catching something real and this step reports back
   rather than deleting it.
4. Delete the call to `short_shot_line_scale()`. Leave the function itself with a dead-code
   comment, same convention as `short_shot_hang_scale()` after Phase 1 — Phase 6 removes the
   body once confirmed unused.
5. Collapse flight termination to path-length only. Confirm `t >= 1.0` genuinely never fires
   first once 1–4 are in place; if it does, stop and report before deleting it.
6. Remove the roll clamp. Playtest roll-out across all lie/friction combinations before
   calling this step done — this is the one most likely to need a friction retune rather than
   a clean deletion.

**Each of these six is a checkpoint, not a single commit.** If a later step reveals an
earlier one was wrong, that's expected — report it rather than reordering silently.

---

## Out of scope

- Apex, hang time, carry fraction, canopies, the bag. All settled by prior phases.
- Friction values themselves (`2.4` fairway, `4.5` rough, `7.0` sand, etc.) — touched only if
  step 6 reveals they need retuning, and if so, reported before changed.
- `resolve_distance()` and anything upstream of `launch_velocity`. Phase 4's owner is correct
  and untouched; this phase changes what happens *inside* flight, not what total distance is
  decided to be.
- The swing-input rework (separate track). This phase does not depend on it and should not
  wait for it.

---

## Acceptance criteria

1. All flight goldens unchanged — this phase does not touch apex, hang, or carry.
2. The documented low-speed sidespin case (short pitch, meaningful path error) loses distance
   proportional to its curvature, not catastrophically — quantify before/after.
3. Flight terminates via exactly one condition. Confirm by instrumenting which branch fires
   across a representative sweep of shots; report if more than one condition is ever
   simultaneously true at exit.
4. Roll settles within a small, reported tolerance of planned distance under normal
   conditions **without** the hard clamp, across all lie types.
5. `short_shot_line_scale()` has no call sites. `short_shot_hang_scale()` remains dead as
   established in Phase 1.
6. All `*_check.py` pass.

---

## Playtest verification order

1. A soft, short pitch with visible sidespin (the case that started this investigation).
   Should now cover close to its planned distance, bent, not truncated.
2. A full driver with a strong swipe-direction error. Should curve visibly and lose distance
   proportional to the curve — not reverse, not stop dead.
3. Chip and flop shots at various lengths — confirm nothing in the short game regressed from
   the curvature formula change.
4. Roll-out on fairway, rough, and sand — confirm the ball settles near plan without feeling
   snapped into place at the end.
5. Play several holes. The target feeling: **"plan says X, ball goes somewhere sensible near
   X"** — not exactly X every time (that would be suspicious), but no more wild swings between
   plan and reality on ordinary shots.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `scripts/ball/ball.gd`, `scripts/ball/ball_physics.gd`, and
  `scripts/ball/flight_model_check.py`.
- This phase is sequenced internally (six checkpoints above) — do not implement it as one
  undifferentiated diff. Report results at each checkpoint.
- If any step's assumption doesn't hold — the reverse-guard still needed, `t >= 1.0` still
  firing first, roll not settling without the clamp — **stop and report rather than pushing
  through.** This phase is explicitly about removing band-aids once their root cause is gone;
  if a band-aid turns out to still be load-bearing, that's a real finding, not a failure to
  fix quietly.

# Correction — Landing Speed Lie Awareness

**Track:** correction following Phase 5. Not a numbered phase.
**Branch:** `fix/landing-speed-lie`, from main after Phase 6 cleanup
**Found by:** Phase 5 CP6's roll-clamp-removal sweep
**Size:** one formula, keyed off data that already exists.

---

## The bug

`launch_velocity()` computes `landing_speed` — how fast the ball is moving the instant it
transitions from flight to roll — using a hardcoded constant:

```gdscript
// ball_physics.gd:837
landing_speed = sqrt(2.0 * 144.0 * roll_px)
```

`144.0` is `2.4 * 60`, i.e. **fairway's** roll deceleration, baked in regardless of what the
ball is actually about to land on. The real per-lie friction table already exists, one file
away, in `ball.gd`'s `_process_roll`:

```gdscript
var friction := 2.4
match _lie:
	"Green":   friction = 1.8
	"Fairway": friction = 2.4
	"Rough":   friction = 4.5
	"Sand":    friction = 7.0
	_:         friction = 3.0
```

So a ball landing on sand is given **fairway-speed** landing energy, then decelerated at
**sand's** (much higher) rate. Too much speed converted too fast — the ball settles well short
of plan. Measured during Phase 5 CP6: **10–15 yards short on Driver → Sand/Rough**, while
Fairway settling *improved* once the unrelated roll clamp was removed (−2.6 → −0.6 yd error).
Fairway happens to be correct because `144` is fairway's own constant — every other lie
inherits fairway's landing energy by accident.

---

## The fix

`landing_speed()` needs to know the landing lie before the ball lands. It already receives
`lie` as a parameter — `launch_velocity(result, target_dir, club_max_yards, lie, severity, ...)`
— it just never used it for this calculation.

```gdscript
## Roll deceleration by lie, px/s². Single source — ball.gd's _process_roll uses the
## same values keyed the same way. If these tables diverge, landing speed and roll
## deceleration disagree and the ball's speed jumps unnaturally at the flight->roll
## transition.
static func roll_friction_for(lie: String) -> float:
	match lie:
		"Green":   return 1.8
		"Fairway": return 2.4
		"Rough":   return 4.5
		"Sand":    return 7.0
		_:         return 3.0
```

Replace the hardcoded `144.0` with `roll_friction_for(lie) * 60.0`, and have `ball.gd`'s
`_process_roll` read from the same function instead of its own inline `match`.

**This creates the single owner this table never had.** Right now the values are duplicated
in two files by coincidence, not by design — exactly the pattern that caused this bug. Fixing
only the formula and leaving two copies of the friction table would reintroduce the same
class of bug the moment either one is retuned in isolation.

---

## What this does and does not change

**Changes:** landing speed on Rough, Sand, and Green. Fairway is unaffected — `144.0` already
equaled `2.4 * 60`, so this is a no-op for the lie that was accidentally correct.

**Does not change:** flight, apex, hang time, carry, or anything before the ball lands. This
is purely the instant of the flight → roll handoff.

---

## Changes

### `scripts/ball/ball_physics.gd`
Add `roll_friction_for(lie)`. Replace the `144.0` literal in `launch_velocity()`'s
`landing_speed` calculation with `roll_friction_for(lie) * 60.0`.

### `scripts/ball/ball.gd`
Replace the inline `match _lie: ... friction = ...` block in `_process_roll` with a call to
`BallPhysics.roll_friction_for(_lie)`. Confirm the default arm (today's bare `_: friction = 3.0`)
matches exactly — do not let the two subtly diverge again.

### `scripts/ball/flight_model_check.py`
Parse `roll_friction_for` and assert the two consumers (`landing_speed` and `_process_roll`)
resolve to identical values for every lie. Add the specific regression case: Driver landing on
Sand should settle within a small reported tolerance of plan, not 10–15 yards short.

---

## Out of scope

- Retuning any friction value. `1.8 / 2.4 / 4.5 / 7.0` stay as they are — this fixes which
  value gets used, not what the values are.
- Anything upstream of the flight→roll transition.
- The hard settle-at-plan line (`along >= _planned_distance_px`), left alone by Phase 5 CP6
  and still out of scope here.

---

## Acceptance criteria

1. `landing_speed` for a Fairway landing is numerically unchanged (144.0 was already correct
   for this lie — this is the regression guard for the fix itself).
2. `landing_speed` for Sand and Rough now reflects those lies' actual friction, not
   fairway's.
3. Driver → Sand settle error is small and reported, not 10–15 yards short as measured in
   Phase 5.
4. `roll_friction_for()` is the only place lie friction values are defined. `ball.gd` reads
   from it rather than keeping its own copy.
5. All `*_check.py` pass. Flight goldens unchanged — this touches roll, not flight.

---

## Playtest verification

1. Land a full shot on sand (bunker approach or a sandy lie). Roll-out should feel like sand —
   short, checking up — not like it stalled to a stop 15 yards early.
2. Land on rough. Same check.
3. Land on fairway. Should feel identical to before — this is the no-op case.
4. Compare a few shots' `Plan X → Actual Y` in the debug panel across lie types. The gap
   should be small and consistent, not lie-dependent in the way it was before.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `ball_physics.gd`, `ball.gd`, `flight_model_check.py`.
- This is small and mechanical — the risk is entirely in making sure the two consumers stay
  identical, which is why criterion 4 exists. Don't skip the identity assertion.

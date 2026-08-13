# Correction — recommended_power Launch-Relative Wind

**Track:** correction, outside the numbered phase tracks
**Branch:** `fix/recommended-power-wind`, from main
**Found by:** flagged during the reverse-guard investigation as a same-class, separate bug.
**Size:** one function signature, one caller update, confirmed by tracing all three call
sites before writing this.

---

## The bug

```gdscript
// ball_physics.gd:634-636
var wind_yards := 0.0
if lie != "Green":
	wind_yards = -wind.y * 0.35 + absf(wind.x) * 0.08
```

This treats `wind.y` as "the headwind component" unconditionally — as if every hole plays
down the world's fixed −Y axis. It doesn't. Wind is a random world-space vector
(`hole_generator.gd`), and so is a hole's bearing from tee to pin. The actual headwind a shot
experiences is wind projected onto **launch direction**, not onto world Y — exactly the axis
mismatch the reverse-guard investigation found in flight integration, in a second, separate
place: club/power recommendation.

Practical effect: on any hole whose bearing isn't close to world −Y, `recommended_power`
computes "wind adjustment" using the wrong component of the wind vector. It might recommend
extra power for what it thinks is a headwind when the shot is actually crosswind or even
downwind, or vice versa. The player gets a club/power suggestion that doesn't match the
conditions their own shot will actually fly through.

**This is not the same bug the reverse-guard fix addressed.** That was wind's effect on
in-flight velocity. This is wind's effect on the *suggestion* given before the swing even
starts. Both stem from the same root cause (wind stored/consumed in world space without
being reprojected onto shot-relative axes) but they're independent code paths and this one
was explicitly left as a follow-up rather than folded into that fix.

---

## Why the caller already has what's needed

```gdscript
// hole_controller.gd:1519-1521
var recommend := BallPhysics.recommended_power(target_yd, club_max, lie, wind)
var est := BallPhysics.estimate_carry_yards(recommend, club_max, lie)
var bearing := _cup_pos - _tee_pos
```

`bearing` is computed one line **after** the call that needs it. No new data has to be
sourced — this is purely a matter of computing bearing before the call instead of after, and
passing it through.

---

## The fix

Add a launch-direction parameter to `recommended_power`, and project wind onto it instead of
reading `wind.y`/`wind.x` as fixed axes:

```gdscript
static func recommended_power(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = "",
	launch_dir: Vector2 = Vector2.UP   # world -Y default preserves today's behavior
                                        # when no direction is supplied
) -> float:
	var wind_yards := 0.0
	if lie != "Green":
		var dir := launch_dir.normalized() if launch_dir.length_squared() > 0.001 else Vector2.UP
		var head := -wind.dot(dir)          # positive = headwind, negative = tailwind
		var cross := absf(wind.dot(dir.orthogonal()))
		wind_yards = head * 0.35 + cross * 0.08
```

**The default (`Vector2.UP`) preserves exact current behavior for any caller that doesn't
pass a direction** — this is what keeps existing call sites from silently changing behavior
mid-fix. Only the caller that has a real bearing available needs to change.

### Caller update

```gdscript
// hole_controller.gd — compute bearing before the call, pass it through
var bearing := (_cup_pos - _tee_pos).normalized()
var recommend := BallPhysics.recommended_power(target_yd, club_max, lie, wind, "", bearing)
```

The other two call sites (`ball_physics.gd:518` and `:678`) — check whether launch direction
is available to them. If it is, thread it through the same way. If it isn't (report which and
why), leave them on the default and note it as further follow-up rather than inventing a
bearing that isn't legitimately known at that call site.

---

## Out of scope

- The reverse-guard / in-flight wind application. Already fixed, separate code path.
- Any change to how wind is generated (`hole_generator.gd`). Still fully random, still fine.
- Any change to the wind coefficients themselves (`0.35`, `0.08`). This fixes which
  component of wind they're applied to, not their magnitude.

---

## Acceptance criteria

1. With `launch_dir = Vector2.UP` (the default), output is byte-identical to current
   behavior for every existing test case. This is the regression guard for the fix itself.
2. With a launch direction rotated 90° from world −Y and a pure world −Y wind, the function
   now correctly reads that as a pure crosswind (`wind_yards` from the `0.08` term only, not
   the `0.35` term) rather than as a headwind.
3. `hole_controller.gd`'s call site passes a real bearing and the recommendation changes
   accordingly on non-north-south holes — verify with a specific example hole/wind
   combination, not just the unit math.
4. All `*_check.py` pass.

---

## Notes for the agent

- Confirm the other two `recommended_power` call sites' access to launch direction before
  deciding whether to update them or leave them on the default — report which.
- This should be small. If it turns out to need more than the signature change and one
  caller update, stop and report before expanding scope.
- No playtest strictly required for correctness (it's directional math), but a quick
  in-game check on an east-west-ish hole with strong wind is worth doing if convenient —
  confirm the recommended club/power actually shifts sensibly.

# Flight Phase 6 — Delete Dead Functions

**Track:** flight-model-rebuild-roadmap.md, Phase 6 of 8
**Branch:** `feature/flight-phase6-cleanup`, from main
**Size:** two function bodies, zero callers, confirmed by grep before writing this.

---

## What's actually left

Phase 5 already removed everything this phase was originally scoped to remove — the
sidespin-scale patches, the reverse-guard's flat floor, the roll clamp. What remains is
exactly what both dead functions' own comments say is left:

```gdscript
## DEAD after Phase 5 CP4 — launch no longer calls this. Speed-proportional spin
## + airspeed preserve own short-shot curve. Left for checks; Phase 6 deletes body.
static func short_shot_line_scale(total_yards: float) -> float:
	return clampf(total_yards / 55.0, 0.10, 1.0)


## DEAD after Phase 1 — hang is derived from apex_for (∝ power → hang ∝ sqrt(power)).
## Left for club_identity / short_pitch checks; Phase 6 removes after harness confirms.
static func short_shot_hang_scale(total_yards: float) -> float:
	if total_yards >= 40.0:
		return 1.0
	return clampf(lerpf(0.42, 1.0, total_yards / 40.0), 0.42, 1.0)
```

Confirmed via grep: zero call sites for either function anywhere in `scripts/`. Both were
kept alive only so the check files that referenced them by name wouldn't need updating in the
same PR as the phase that made them dead. That deferral is over.

---

## Changes

### `scripts/ball/ball_physics.gd`
Delete both function bodies and their comments.

### Check files (confirmed referencing these functions by name)
- `scripts/ball/club_identity_check.py`
- `scripts/ball/flight_model_check.py`
- `scripts/ball/short_pitch_distance_check.py`

Update each to stop asserting the functions exist. If any of them was using the functions'
*return values* as part of a live regression model (rather than just asserting the symbol is
present), report that before deleting — it would mean the function isn't actually as dead as
its comment claims, which would be a real finding, not just cleanup.

---

## Acceptance criteria

1. Both functions deleted from `ball_physics.gd`.
2. Zero references to either name anywhere in `scripts/`.
3. All `*_check.py` pass.
4. Flight goldens unchanged — this touches no live code path, only dead code and test
   assertions about it.

---

## Notes for the agent

- This should be mechanical. If it isn't — if either function turns out to have a live
  caller you find that grep didn't, or a check file depends on its actual behavior rather
  than its existence — stop and report rather than working around it.
- No playtest needed. Nothing reachable in play changes.

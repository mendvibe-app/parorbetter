# Epic 1 — Manual Shot-Type Picker + Club Eligibility Gate + Landing/Rollout Visualization

Repo: `mendvibe-app/parorbetter` · Branch off `main` at the commit this spec was written
against (`672d534`). One PR for this whole epic, one playtest pass before Phase 2 starts.

Parent doc: `short-game-roadmap.md` (this is Phase 1). Reference: `shot-type-ground-truth.md`.

---

## What this epic does, in plain terms

Right now the game picks Chip vs. Pitch vs. Full for you, silently, based on how far your aim
marker is from the ball — and you can't see the difference between where a shot lands and where
it stops rolling. This epic makes shot type a real choice, limits that choice to clubs where it
makes golf sense, and shows the player enough to actually judge whether a shot clears a hazard.

Three pieces, shipped together because the picker isn't useful without the visualization, and the
visualization needs a real shot type to draw against:

1. **Club eligibility gate** — which shot types a club can hit
2. **Manual shot-type picker** — player chooses, game recommends
3. **Landing vs. rollout visualization** — two markers instead of one generic circle

---

## Current behavior (as-built, for grounding — already confirmed in repo, no need to re-verify)

**Shot type is decided automatically**, not chosen. `TempoGrade.shot_type_for()`
(`scripts/shot/tempo_grade.gd` lines 49–59) takes lie + aim distance + club max and returns one of
`"putt" / "chip" / "pitch" / "full"` — pure function, no player input:

```gdscript
static func shot_type_for(lie: String, remaining_yd: float, club_max_yards: float = 0.0) -> String:
	if lie == "Green":
		return "putt"
	if remaining_yd < CHIP_YD:
		return "chip"
	var gate := PITCH_YD
	if club_max_yards > 1.0:
		gate = minf(PITCH_YD, club_max_yards * PITCH_POWER_CAP)
	if remaining_yd < gate:
		return "pitch"
	return "full"
```

This gets called from `shot_routine.configure()` (`scripts/shot/shot_routine.gd` line 159):

```gdscript
shot_type = TempoGrade.shot_type_for(lie, aim_distance_yd, club_max_yards)
```

`configure()` is called from `hole_controller._start_power_swing()`
(`scripts/course/hole_controller.gd` lines 1731–1744) — this is the call site that will need a
new parameter.

**Club choice already has a real picker.** `ClubSelect` (`scripts/shot/club_select.gd`) is a
working popup — `_begin_club_select()` in hole_controller.gd (line 1377) opens it,
`_on_club_chosen(club)` (line 1400) receives the pick and stores it in `_chosen_club`. This is the
pattern the shot-type picker should follow, not something to build from scratch.

**There's already a toggle-button precedent for a shot-modifier control.** `_punch_btn`
(hole_controller.gd lines 1604–1617) is a `toggle_mode` Button shown/hidden during aim, wired to
`_on_punch_toggled`. The shot-type picker's UI should follow this same shape (shown/hidden during
aim phase, positioned via a `_park_*` helper like `_park_punch_btn`), just as a 3-way segmented
control instead of a boolean toggle.

**Landing marker exists but only appears mid-flight, not at address.** `ball._show_land_mark()`
(`scripts/ball/ball.gd` line 211) and `_planned_land_pos()` (line 191–192) already compute and
draw a carry-landing marker — but only once the ball is actually in the air
(`_process_flight()` line 345 calls it), not during aim. The aim-phase circle
(`hole_controller._refresh_aim_visuals()`, lines 1977–2032) draws a single `_aim_circle` at the
full target distance — no carry/rest distinction pre-swing.

**Tree/hazard clearance check already exists and already computes carry.**
`_aim_tree_clearance()` (hole_controller.gd lines 1893–1932) already solves committed power,
estimates carry yards, and checks whether that carry clears a tree canopy — this is the exact
"does my carry clear the hazard" logic Matt asked about. It's currently only used to tint the aim
cone's color (yellow/green/red), not to show the player the actual carry distance as a marker.
This epic reuses this function's math, it does not duplicate it.

---

## Part 1 — Club eligibility gate

### Add an eligibility table

New function in `scripts/ball/ball_physics.gd`, near `clubs_for_lie()` (line 219):

```gdscript
## Which shot types this club can hit, by bag rank. Full is always available.
## Flop deferred to Phase 5 — do not add "flop" here yet.
static func eligible_shot_types(club_max_yards: float) -> Array[String]:
	var types: Array[String] = ["full"]
	if club_max_yards <= 0.0:
		return types
	if club_max_yards <= 160.0:   # 7-Iron and shorter (160 = 7I max_yards, BAG constant)
		types.append("chip")
	if club_max_yards <= 110.0:   # PW and shorter (110 = PW max_yards, BAG constant)
		types.append("pitch")
	return types
```

**Note for the agent:** `club_bag_rank()` (line 100) currently ranks by club *name*, not yardage.
Since eligibility needs to work off `club_max_yards` (what `configure()` and the picker actually
have on hand), gate on the yardage thresholds directly against the `BAG` constant (lines 13–24)
rather than adding a parallel name-based lookup. Confirm the exact `BAG` max_yards values for 7I
and PW before hardcoding — use the constant, don't retype the numbers if `BAG` changes.

### Where this plugs in

`ClubSelect` needs each club row to know its eligible shot types so the picker (Part 2) can filter
correctly. Pass `eligible_shot_types(max_yards)` alongside each club's data when `_rebuild_list()`
(`club_select.gd` line 226) builds rows — store it on the row/dictionary rather than recomputing
it later.

### Explicitly out of scope here
- Flop is not part of this table yet (Phase 5).
- Do not change `BAG` yardages or club names.

---

## Part 2 — Manual shot-type picker

### The core change: `shot_type_for()` becomes a recommendation, not an assignment

Rename-in-place is risky (many call sites) — instead, add a new function alongside it and leave
`shot_type_for()` as the fallback/default:

```gdscript
## Same signature and logic as shot_type_for() — this IS the recommendation.
## Kept as a separate name so call sites are explicit about intent: recommending
## vs. (old callers that still want a hard default, e.g. range mode) assigning.
static func recommend_shot_type(lie: String, remaining_yd: float, club_max_yards: float = 0.0) -> String:
	return shot_type_for(lie, remaining_yd, club_max_yards)
```

Then `shot_routine.configure()` gets a new parameter:

```gdscript
func configure(
	lie: String,
	aim_distance_yd: float,
	pin_distance_yd: float,
	wind: Vector2,
	_shape_label: String,
	p_timing: float,
	p_shape: float = 0.0,
	p_aim_radius_yd: float = 22.0,
	p_club_name: String = "",
	p_club_max_yards: float = -1.0,
	p_severity: String = "",
	p_punch: bool = false,
	p_shot_type_override: String = ""   # NEW — "" means "use recommendation" (old behavior)
) -> void:
	...
	shot_type = p_shot_type_override if not p_shot_type_override.is_empty() \
		else TempoGrade.recommend_shot_type(lie, aim_distance_yd, club_max_yards)
```

This is additive — every existing call site that doesn't pass the new param keeps behaving exactly
as it does today. Only `hole_controller._start_power_swing()` needs to pass the player's actual
choice.

### UI: shot-type picker shown during aim

Follow the `_punch_btn` pattern (hole_controller.gd lines 1604–1629), not a new popup:
- New control, e.g. `_shot_type_row` — a small segmented control (2 or 3 buttons depending on
  eligibility) shown during `_begin_aim_phase()`, hidden in `_end_aim_phase()`, positioned via a
  `_park_shot_type_row()` helper the same way `_park_punch_btn()` works.
- Populate its options from `BallPhysics.eligible_shot_types(club_max)` (Part 1) — if only `full`
  is eligible (Driver–6-Iron), don't show the control at all, same way `_punch_btn` only shows in
  Trees.
- Default selection = `TempoGrade.recommend_shot_type(...)` result, pre-selected but changeable —
  this is the "recommend, don't force" behavior.
- Store the player's live selection in a new `_chosen_shot_type: String` on `hole_controller`,
  reset it to `""` (meaning "use recommendation") on `_begin_club_select()` and whenever the club
  changes, so switching clubs doesn't carry over a now-ineligible shot type.
- `_start_power_swing()` passes `_chosen_shot_type` as the new `configure()` param.

### Recommendation logic — reuse existing hazard math, don't invent new logic

`_aim_tree_clearance()` (hole_controller.gd line 1893) already returns `"none" / "clear" /
"blocked"` for the current aim line. When it returns `"blocked"` and Pitch is eligible for the
current club, the picker's default should be Pitch instead of whatever `recommend_shot_type()`
alone would pick by distance. When `"clear"` or `"none"`, keep the distance-based recommendation
(Chip if under 20 yd and eligible). This is a small override layer on top of the existing
recommendation, not a rewrite of it:

```gdscript
func _recommended_shot_type(lie: String, aim_yd: float, club_max: float, from: Vector2, to: Vector2) -> String:
	var base := TempoGrade.recommend_shot_type(lie, aim_yd, club_max)
	var eligible := BallPhysics.eligible_shot_types(club_max)
	if base == "chip" and _aim_tree_clearance(from, to, club_max) == "blocked" and "pitch" in eligible:
		return "pitch"
	return base
```

### Explicitly out of scope here
- Flop as a selectable option (Phase 5) — the picker's option set never includes it yet.
- Changing how `TempoGrade.shot_type_for()` itself computes CHIP_YD/PITCH_YD thresholds — those
  constants are untouched.

---

## Part 3 — Landing vs. rollout visualization

### The problem, concretely

`_aim_circle` (hole_controller.gd line 2025) is drawn at `to` (`_aim_target`, the *total* distance
point, carry+roll combined) with one radius. A player aiming a Chip (mostly roll) and a Pitch
(mostly carry) see the identical circle shape today, with no way to tell where the ball first
touches down.

### The fix: compute and draw a second marker at the carry-only distance

Reuse the exact math `_aim_tree_clearance()` already does (lines 1902–1911) — don't duplicate a
second formula:

```gdscript
func _aim_carry_land_point(from: Vector2, to: Vector2, club_max: float, lie: String, shot_type: String) -> Vector2:
	var aim_yd := BallPhysics.pixels_to_yards(from.distance_to(to))
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector) if course_root else Vector2.ZERO
	var severity := ball.get_lie_severity()
	var solved := BallPhysics.solve_committed_power(aim_yd, club_max, lie, wind, severity)
	var carry_yd := BallPhysics.estimate_carry_yards(float(solved["power"]), club_max, lie, severity)
	var air_frac := BallPhysics.air_distance_fraction(club_max, shot_type)
	var bearing := to - from
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	return from + bearing.normalized() * BallPhysics.yards_to_pixels(carry_yd * air_frac)
```

In `_refresh_aim_visuals()` (around line 2025, alongside where `_aim_circle` is set):
- Add a new `_land_preview_mark: Line2D` (or reuse the ring/fill pattern from
  `ball._build_land_mark()`, lines 112–126, for visual consistency with the in-flight marker) —
  smaller radius than `_aim_circle`, positioned at `_aim_carry_land_point(...)`.
- Draw a thin connecting line or fading trail between the carry-land marker and `_aim_circle`
  (the rest position) so the gap is visually obvious — this is the "how far does it roll after
  landing" read Matt asked for.
- Skip this entirely for Putt (`lie == "Green"`) — putts don't carry, the existing putt line stays
  as-is (lines 1956–1976, untouched).
- Shot types with a small air fraction (Chip) will show the two markers close together; Pitch and
  Full will show them further apart — this should read as correct without any per-shot-type
  special-casing, since it falls out of `air_distance_fraction()` naturally.

### Explicitly out of scope here
- The in-flight land marker (`ball._show_land_mark()`) itself — that already works correctly
  post-swing and is not being touched.
- Any change to `air_distance_fraction()`'s actual chip/pitch ratios (Phase 2).

---

## Files touched (summary)

| File | Change |
|---|---|
| `scripts/ball/ball_physics.gd` | Add `eligible_shot_types()` |
| `scripts/shot/tempo_grade.gd` | Add `recommend_shot_type()` (thin wrapper) |
| `scripts/shot/shot_routine.gd` | Add `p_shot_type_override` param to `configure()` |
| `scripts/shot/club_select.gd` | Attach eligible shot types to each club row's data |
| `scripts/course/hole_controller.gd` | New shot-type picker control + park/sync helpers; `_recommended_shot_type()`; `_aim_carry_land_point()`; new marker drawn in `_refresh_aim_visuals()`; pass override into `_start_power_swing()`'s `configure()` call |

**Do not touch:** `scripts/shot/putt_stroke.gd`, `scripts/shot/tempo_gesture.gd`'s grading logic,
anything under Full swing's `contact_multiplier`/`force_factor` math, `ball.gd`'s flight/roll
physics. This epic changes *which* shot type gets chosen and *what the player sees before
swinging* — it does not change how any shot type is graded or simulated.

---

## Acceptance criteria

- Driver through 6-Iron: no shot-type picker shown, always Full — matches today's behavior
  exactly (regression check, not a new feature for these clubs).
- 7i/8i/9i: picker shows Full + Chip only. PW/Gap/Sand: picker shows Full + Chip + Pitch.
- Default selection matches the recommendation logic (distance-based, overridden to Pitch when
  `_aim_tree_clearance()` returns `"blocked"` and Pitch is eligible).
- Changing the picker selection actually changes graded shot type — verify via debug panel that
  `shot_type` passed to `TempoGrade.grade()`/`PuttStroke.grade()` matches the player's pick, not
  just the recommendation.
- Switching clubs mid-aim resets the picker to that club's recommendation, never leaves a
  now-ineligible shot type selected.
- Two distinct markers render during aim for every non-putt shot: carry-land point and rest point,
  visibly separated by a margin that scales with shot type's air fraction (Chip: close together,
  Pitch: further apart).
- Putt aim visuals are pixel-identical to before this epic (no regression).
- No change to Full or Putt's grading, physics, or contact-quality math anywhere in the diff.

## Tuning flags (playtest targets, not final)
- The `"blocked"` → force-Pitch override in `_recommended_shot_type()` is a first guess at
  matching player intuition — may need to also consider `"clear"` cases where Pitch still reads
  better to a real golfer (e.g. very tight lies). Note as an open tuning question in the PR, don't
  treat the current logic as final.
- Carry-marker visual size/opacity is a first pass — expect a follow-up visual tuning pass after
  playtesting, not part of this epic's acceptance bar.

## Playtest verification order
1. Regression pass: Driver–6-Iron shots behave identically to pre-epic (no picker, Full only).
2. 7i–9i: confirm Chip becomes genuinely selectable and produces a visibly different landing/rest
   marker gap than Full.
3. PW/Gap-Sand: confirm all three types selectable, Pitch recommended over trees/blocked lines.
4. Full 9- or 18-hole round: does the picker feel like it's in the way, or does it disappear when
   not needed (Driver tee shots)?
5. Confirm the original motivating case: standing above the hole with an obstacle between ball and
   pin — can the player now tell, before swinging, whether their carry clears it?

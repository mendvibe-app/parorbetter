# Epic 0 — Harness and Observability

**Phase:** 0 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/flight-harness-observability`
**Gameplay change:** none. Zero physics or tuning edits in this epic.

---

## Why this phase exists

We are about to rebuild the flight model. Right now we have no way to measure what a change
did, and — because the game is top-down — no way to *see* height at all. Height has been
tuned blind for months. This epic builds the instrument before the surgery.

Two deliverables: a regression harness that runs outside the engine, and an in-game
elevation readout so a playtester can see trajectory shape without reading a number.

**Do not change any physics constant, tuning value, or gameplay behaviour in this epic.**
If the harness reveals something tempting, write it down for Phase 1 and move on.

---

## Task 1 — Land the harness

Create `tools/harness.py` from the provided file (attached separately; do not rewrite it).

- `tools/` is new. Godot ignores non-resource directories, so no import config is needed.
- Do **not** add `tools/` to `.gitignore` — the harness is source, not build output.
- The harness header carries source line references back into `ball_physics.gd` and
  `ball.gd`. **Keep those references accurate.** Any later phase that moves the referenced
  code updates the header in the same PR.

Add a short section to `README.md` under the existing dev notes: how to run it
(`python3 tools/harness.py`, optional `--chart`), and the rule that its before/after
golden-shot output goes in every physics PR description.

**Note on golden shots:** the expected ranges encode *real golf*, not current behaviour.
The current 2/12 pass rate is the backlog. Do not "fix" the harness by loosening ranges to
match what the game does today — that is the entire point of the file.

---

## Task 2 — Capture real flight metrics on the ball

`scripts/ball/ball.gd` currently exposes planned apex and observed max height only
(`flight_height_peak()` at line 358, `flight_height_max()` at line 363). We need actual
hang time and the actual carry/roll split so the harness's predictions can be checked
against a live shot.

Add three tracking vars near the existing flight state (`_air_timer` line 34, `_height`
line 36, `_height_peak` line 38):

```gdscript
var _hang_time_actual: float = 0.0   ## seconds in FLIGHT, set at _begin_roll
var _carry_px_actual: float = 0.0    ## along-launch distance at first bounce
var _launch_speed: float = 0.0       ## |velocity| at launch, for harness comparison
```

Reset all three in `reset_at()` (line 238, alongside the existing `_height_peak = 0.0`).

Set `_launch_speed = velocity.length()` in `launch()`, immediately after
`velocity = launch_data["velocity"]` (line 283).

In `_begin_roll()` (line 508), capture before the state flips:

```gdscript
_hang_time_actual = _air_timer
_carry_px_actual = _traveled_along()
```

Add one accessor returning everything together, next to the existing `flight_height_*`
getters:

```gdscript
func flight_metrics() -> Dictionary:
	## Post-shot instrumentation for the debug panel and harness cross-check.
	return {
		"apex_planned": _height_peak,
		"apex_actual": _height_max,
		"hang_time": _hang_time_actual,
		"carry_px": _carry_px_actual,
		"planned_px": _planned_distance_px,
		"air_fraction": _air_fraction,
		"launch_speed": _launch_speed,
	}
```

Keep `flight_height_peak()` and `flight_height_max()` — `hole_controller.gd` still calls
them and other callers may exist.

---

## Task 3 — Pipe metrics through to the debug panel

`scripts/course/hole_controller.gd:2483-2484` already writes apex into
`GameState.last_shot_metrics` at settle. Extend that block:

```gdscript
GameState.last_shot_metrics["height_peak"] = ball.flight_height_peak()
GameState.last_shot_metrics["height_max"] = ball.flight_height_max()
GameState.last_shot_metrics["flight"] = ball.flight_metrics()
```

No other write site changes. The launch-time block at line 2221 stays as is — flight
metrics only exist after the ball settles.

---

## Task 4 — Elevation readout in the debug panel

This is the piece that makes height visible. Two parts.

**4a — Extend the existing text line.** `scripts/debug/debug_controls.gd:242-247` builds
`height_line`. Add carry, hang time, and launch speed so the numbers the harness predicts
can be read directly off a live shot:

```
Apex peak 22.5 · max 22.4 (canopy short~22–28 pine~38 tall~42)
Carry 177 yd · roll 83 yd · hang 0.64s · launch 620 px/s
```

Convert carry to yards with `BallPhysics.pixels_to_yards()`. Guard for an empty `flight`
dictionary the same way the existing code guards `h_peak >= 0.0`.

**4b — Side-elevation sparkline.** Add a small `_draw()`-based Control that renders the
last shot's trajectory profile: distance downrange on X, height on Y, with horizontal
reference lines at the three canopy heights (25 / 38 / 42 px, matching the constants
already named in the debug string).

- **Build it in code, not in the scene file.** Instantiate in `_ready()` and append to
  `$Panel/Margin/Root/Scroll/VBox` after the `Metrics` label. Do not edit
  `scenes/ui/debug_panel.tscn` — keeping this epic out of the scene file makes it trivially
  revertable.
- Suggested size ~260 × 90 px, scaled through the existing `ui_scale.gd` helper if the other
  debug rows use it.
- Curve shape is the same `sin(t × PI)` the flight uses, sampled across `carry_px` and
  peaking at `apex_actual`. It is a profile of the shot that just happened, not a live trace.
- Draw the canopy lines dashed and label them. Colour the curve with the existing
  good/amber/red contact palette already used in `ball.gd:330-338` — reuse, don't invent.
- Redraw on the same tick the metrics label updates.

**Acceptance for this task specifically:** hit a driver, then a greenside chip, and the two
profiles should be visibly, obviously different in shape. Today they will not be — the chip
will draw *taller* than the driver. That is the bug this epic is built to expose, and seeing
it drawn is the deliverable.

---

## Out of scope

- Any change to `ball_physics.gd`. This epic does not touch it.
- Any tuning constant, anywhere.
- Live in-flight tracing or a shadow/height indicator in the main play view — that is a
  player-facing feature, not instrumentation. Debug panel only.
- Editing `scenes/ui/debug_panel.tscn`.
- Wiring the harness into CI. Manual runs are enough for now.

---

## Acceptance criteria

1. `python3 tools/harness.py` runs from a fresh checkout and prints the bag table, short-game
   table, canopy clearance table, and golden shots. Current expected result: **2/12 passing.**
2. `python3 tools/harness.py --chart` writes `trajectory_current.png`.
3. `README.md` documents the run command and the before/after-in-every-PR rule.
4. Debug panel shows apex, carry, roll, hang time, and launch speed for the last shot.
5. Debug panel draws an elevation profile with canopy reference lines.
6. **Live shot matches harness prediction.** Hit a full driver from a fairway lie with GOOD
   contact and no wind; the panel's carry, hang time, and apex should land within ~5% of the
   harness's Driver row (177 yd carry, 0.64s, 22.5 px apex). A larger gap means the harness
   port is wrong and must be corrected before Phase 1 — the harness is only useful if it is
   faithful.
7. No gameplay behaviour changes. A playtester who does not open the debug panel should not
   be able to tell this PR landed.

---

## Playtest verification order

1. Open debug panel, hit a full driver, confirm the numbers match the harness (criterion 6).
2. Hit a greenside chip. Confirm the elevation profile draws *taller* than the driver's.
   Screenshot both — this pair is the before-image for the whole rebuild.
3. Hit a punch shot under a short canopy. Confirm the profile shows it ducking under the
   25 px line.
4. Play three holes normally without opening the panel. Confirm nothing feels different.

---

## Notes for the agent

- Read this document and confirm your understanding before writing code.
- Touch only: `tools/harness.py` (new), `README.md`, `scripts/ball/ball.gd`,
  `scripts/course/hole_controller.gd`, `scripts/debug/debug_controls.gd`.
- If criterion 6 fails, **stop and report the discrepancy** rather than adjusting either
  side to match. Which one is wrong is a design decision, not an implementation one.

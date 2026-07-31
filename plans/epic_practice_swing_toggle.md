# Epic: Toggleable Practice Swing Count

**Status**: Shipped (2026-07-30) — confirm-aim auto-chains N practice reps then real; F1 sets 0–3.

## Goal
Replace the standalone "Practice Swing" button with a settings-driven count
(0–3). Whatever the player sets, the first N reps of their swing motion are
practice, and the N+1 rep is the real shot — same gesture, same screen, no
extra taps. Mirrors how real golfers already differ in how many practice
swings they take before committing.

## Why this beats the current flow
Today `hole_controller.gd` shows a separate `_practice_btn` above the real
swing confirm button. It's opt-in, so most players skip it entirely — even
though `shot_routine.gd` already has a fully-working `practice_mode` path
(grades the swing, plays feedback, never launches the ball). The mechanic is
good; the button is the friction. Removing the button and making practice
reps automatic (per a player-set count) keeps the same underlying system and
just changes who decides when the "real" rep happens.

## Current state (verified against repo)
- `ShotRoutine.begin_shot(p_practice, p_allow_back)` already branches on
  `p_practice`: grades the gesture via `TempoGrade.grade()` /
  `PuttStroke.grade()`, shows the verdict, and returns via `practice_result`
  signal — **without** calling `_emit_result()` / `shot_ready`. Real shots
  skip straight to `_emit_result()`. This split is exactly what we need; no
  changes required here.
- `hole_controller._start_power_swing(p_practice, p_allow_back)` is the only
  caller of `begin_shot()`. Confirm-aim calls it with `(false, true)`; the
  practice button calls it with `(true)`.
- `hole_controller._on_practice_result(verdict)` currently hands control back
  to the aim UI (shows Confirm + Practice buttons again) after a practice
  swing. This needs to instead either fire the next practice rep or, if the
  count is exhausted, fire the real shot.
- `GameState` already stores simple player-facing toggles the same shape as
  what we need (`tempo_guide_enabled`, `rough_severity_enabled`, etc.) — no
  settings screen exists yet for any of them, they're currently flipped via
  `debug_controls.gd`. We'll follow the same pattern for now and flag the
  "real" settings UI as a follow-up, not part of this epic.

## Design

### 1. New setting
Add to `game_state.gd`:
```gdscript
var practice_swing_count: int = 1  # 0-3, player-configurable
```
Default to 1 so new players feel the benefit without it being forced on
veterans who don't want it. Expose via the same debug-controls pattern as
`tempo_guide_enabled` until a real settings screen exists.

### 2. Remove the standalone button
- Delete `_setup_practice_btn()`, `_practice_btn`, and `_start_practice_swing()`
  from `hole_controller.gd`.
- Confirm-aim becomes the single entry point for the whole sequence —
  practice reps and the real shot all live behind one tap.

### 3. Auto-chain reps
Add a counter to `hole_controller.gd`:
```gdscript
var _practice_reps_remaining: int = 0
```
On confirm-aim (where `_start_power_swing(false, true)` is currently called
directly):
```gdscript
_practice_reps_remaining = GameState.practice_swing_count
_start_power_swing(_practice_reps_remaining > 0, true)
```
In `_on_practice_result(verdict)`, instead of reopening the aim UI:
```gdscript
_practice_reps_remaining -= 1
if _practice_reps_remaining > 0:
    _start_power_swing(true, true)
else:
    _start_power_swing(false, true)
```
Everything downstream (`shot_routine.configure()`, `begin_shot()`,
`_apply_committed_preview()`) already re-runs cleanly per rep — no state
leaks between reps since `begin_shot()` resets `tempo_gesture` and clears
`last_verdict` each call.

### 4. HUD: rep indicator, not a screen
Add a small dot row (●●○) near the existing meter/hint chrome — reuse the
icons-over-text pattern from the HUD cleanup work. Fill order: dots empty out
as practice reps burn down; final dot fills solid gold on the real rep. Lives
in `shot_routine.gd`'s existing `HintLabel`/`GlanceRow` area — no new panel,
no new scene.

Wire it off `phase_changed` / `practice_result` so it just reflects
`_practice_reps_remaining` each rep. Should be hideable via a display setting
for players who don't want the reminder once they've internalized their own
count.

### 5. Feedback level: quiet, per rep
Keep the existing practice verdict path as-is —
`meter_display.show_verdict(verdict)` plus the one-line hint text already do
this. Don't add a shot-result panel or strike-map pop for practice reps;
those stay reserved for the real shot. This uses the grading engine you
already built (`TempoGrade`/`PuttStroke`) to teach rhythm on every rep instead
of wasting it on silent reps.

### 6. Edge cases to sequence carefully
- **Driving range (`GameState.range_mode`)**: currently has its own
  practice-adjacent behavior (`meter_display`'s `live_coach` flag checks
  `range_mode` directly). Confirm this path doesn't get double-counted by the
  new counter — range mode should probably ignore `practice_swing_count`
  entirely and keep its current always-live-feedback behavior.
- **Back/redo button**: today `p_allow_back` only shows on the real-shot call.
  Decide whether "Back" during practice reps should back out of the *whole*
  sequence (all reps) or just cancel the current rep. Simplest: back button
  stays hidden until the real (final) rep, same as today — practice reps
  aren't cancel-able, only skippable by setting count to 0.
- **Putt/chip marker**: `tempo_gesture.putt_show_marker = practice_mode` is
  already keyed off `practice_mode`, so it'll correctly show on every
  practice rep and hide on the real one — no change needed.

## Out of scope for this epic
- A real settings menu UI (this reuses the existing debug-toggle pattern).
- Per-shot-type practice counts (e.g. more reps for driver than putter) —
  ship the flat 0–3 count first, revisit if playtesting shows a need.

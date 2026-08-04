# Epic: Shot Shape from Swing Path ("Around") — Player-Driven Fade/Draw

## Problem
Swipe direction on a full swing doesn't currently shape the shot at all.
Shot curve today comes entirely from the hole's design, not from how the
player actually swung — so there's no way to intentionally curve a shot
around a tree.

## Current state (confirmed in code)

- `scripts/shot/tempo_gesture.gd` already tracks a real lateral swing-path
  value per shot: `_max_lateral` (declared line 146, updated lines 634–635,
  returned in the gesture sample dict at line 758).
- That value **is already consumed** — but only on the green, by
  `scripts/shot/putt_stroke.gd` line 255, for putt break/line.
- Full-swing shot shape instead comes from a **hole-fixed** value:
  - `hole.suggested_shape` is set per hole in `hole_controller.gd`
    (e.g. `HoleData.SuggestedShape.STRAIGHT`, lines 351 and 374).
  - It drives the aim cone's visual bend via `_aim_shape_bend()`
    (line 1625, matched at line 1628).
  - It's passed into the shot pipeline as `p_shape` /
    `suggested_shape` in `shot_routine.gd` (lines 124, 131), which sets
    `ShotResult.intended_shape` (`shot_result.gd` lines 10, 43 — comment:
    *"draw negative, fade positive"*).
  - That finally reaches the flight math in `ball_physics.gd` line 481:
    ```gdscript
    var lateral := (result.path_error * 0.55 + result.intended_shape * 0.25) * stab_term * force_mul
    ```
- Net effect: `intended_shape` is a **hole design bias**, not a swing-path
  read. `max_lateral` — the actual player gesture — never reaches this
  calculation for full swings.

## Proposed change

- Feed `max_lateral` from the gesture sample into the full-swing shape
  calculation, the same way it already reaches `putt_stroke.gd` for
  putting.
- Design decision to confirm before build: does a strong intentional
  in-to-out/out-to-in swipe **override** the hole's `suggested_shape`, or
  **blend** with it (e.g. swiping against a hole's natural shape fights
  it, swiping with it amplifies it)? Recommend blending — matches "real
  golf grounding" principle better than a hard override, and avoids
  players ignoring hole design entirely.

## Acceptance criteria

- Two full swings with the same club/power/contact quality but opposite
  swipe paths (in-to-out vs. out-to-in) produce measurably different
  `lateral`/`spin` outcomes.
- Putting behavior (already using `max_lateral`) is unaffected — this only
  extends the full-swing path, doesn't touch `putt_stroke.gd`.
- Shot shape from swing path is legible enough in outcome that a player
  can learn "swipe this way = draw" through repetition, not just randomness.

## Out of scope

- Tree apex/height carry (Epic: Tree Apex Carry).
- Punch-out low shot (Epic: Tree Punch-Out).

## Notes / provisional values

- Open design question to flag explicitly in this doc for confirmation:
  should shaping a shot require better contact quality to execute cleanly
  (real golf: shaping is harder than hitting it straight), or should it be
  freely available at any contact quality? Recommend gating it slightly by
  contact quality — ties into the existing "affordance, not answer"
  principle (a mishit shouldn't reliably produce a clean intentional draw).
- This is the largest of the three tree-option epics — it touches the
  gesture → shot-result → flight pipeline, not just one file. Recommend
  building/playtesting this one on its own, not bundled with anything else.

## Playtest order

1. Straight hole, deliberate in-to-out swipe — confirm visible draw curve
   vs. a straight-swipe control shot, same club/power.
2. Same test, out-to-in swipe — confirm visible fade curve.
3. Confirm putting is unaffected (regression check).
4. Confirm a mishit with an intentional shape swipe doesn't produce a
   suspiciously clean shape — dispersion should still dominate on poor
   contact.

# Agent Prompt — PLAN ONLY: Phase 1 cup lip-in / rim roll (presentation)

**Repo:** `mendvibe-app/parorbetter` (Godot 4 / GDScript)
**Deliverable:** `plans/cup-lip-in-phase1.md`
**Status:** prompt for agent planning — not itself a plan

---

## Instructions to the agent

**Do not write or change any code.** Produce a plan doc at `plans/cup-lip-in-phase1.md`.
Read the files, confirm your understanding back to me, and stop. I review before any PR.

---

## Goal

Makes currently render identically whether the ball was poured in center-cut or barely
caught the edge. Add a rim-roll visual so an off-center entry curls around the lip before
dropping. Presentation only — **make rate must not change**.

---

## Real-golf grounding

Lip behavior is governed by two variables at the cup edge (Pelz's cup research is the
standard reference):

- **Entry offset** — perpendicular distance from cup center to the ball's line of travel
- **Speed at the lip**

Three outcomes fall out:

1. **Center drop** — low offset, low speed. Straight down. This is today's animation and
   is correct for this case; do not change it.
2. **Rim roll / lip-in** — moderate offset or speed. Ball rides the inner wall, curls
   partway around, falls. **This is what Phase 1 adds.**
3. **Horseshoe lip-out** — high offset AND speed. Rides around and exits offline.
   **Phase 2, out of scope.** Do not plan it. Note it as deferred only.

---

## Current behavior (verify these line refs against HEAD)

- `ball.gd:762` `_try_cup_capture()` — has `global_position`, `velocity`, and the cup's
  `global_position` at the moment of capture. All three are discarded.
- `hole_controller.gd:3600` `ball.reset_at(_cup_pos, "Green")` — teleports the node to
  cup center, throwing away entry geometry.
- `ball.gd:900` `play_cup_drop()` — same 0.18s scale-to-0.38 + darken every time.

---

## Proposed lane (validate, don't assume)

`reset_at` positions the **node**; `play_cup_drop` animates `visual`, a child sprite.
So the entire curl can live in **`visual.position` local space** — orbit out to the entry
offset, arc around the rim, collapse to zero, then the existing scale/darken fires.

Why this lane: no new physics state, no change to capture geometry or
`CUP_CAPTURE_RADIUS`, no fight with `reset_at`. Confirm this holds, or propose better.

Rough shape: `_try_cup_capture` stashes entry offset + speed before emitting `settled`;
`play_cup_drop` takes them and picks an arc length. Offset normalized against
`CUP_CAPTURE_RADIUS` so near-0 keeps today's straight drop.

---

## Questions the plan must answer

1. **Where does entry data get stashed and how does it reach `play_cup_drop`?**
   `_try_cup_capture` emits `settled`, which routes through `_on_ball_settled`. Trace the
   actual path. Propose the cleanest carrier (ball member var read by the controller,
   extra signal arg, etc.) and say why.

2. **Arc mapping.** Given `offset_ratio` (0–1 against capture radius) and lip speed,
   what arc angle and duration? Ground the thresholds in the three-outcome model above,
   not vibes. Mark every constant as a PLAYTEST TARGET with a comment.

3. **All three call sites.** `play_cup_drop()` is called at `hole_controller.gd:3349`
   (practice green), `:3369` (short game), and `:3603` (normal hole-out). A signature
   change touches all three. Plan for that explicitly — do not fix one and break two.

4. **`visual.position` is never reset — this is a latent bug.** Grep confirms
   `visual.position` appears nowhere in `ball.gd`. `reset_at` (`:259`) clears
   `visual.rotation`, `shadow.position`, scale, and modulate, but not `visual.position`.
   If a curl leaves the sprite offset, the ball renders permanently off its own node.
   The guard must land in the same PR. Say where.

5. **Banner timing.** `_show_hole_result_banner` fires immediately after
   `play_cup_drop()` in `_on_holed_out`. A 0.4–0.5s curl means "Birdie" appears while the
   ball is still on the rim. Propose a delay that waits on the drop. The existing
   `await get_tree().create_timer(1.55)` advance timer has room — confirm the budget.

6. **Legibility at zoom.** Rim radius is ~1.5–1.9 world px against a ~0.65 world ball
   radius. At `PUTT_ZOOM_CAP` 24 that's roughly a 36px-radius arc with a 31px ball.
   Does the ball visually escape the dark disc mid-curl? If so, cap the orbit radius.
   **If the usable orbit radius turns out to be under ~1 world px, say so plainly** — a
   curl that reads as jitter rather than motion is a reason to reshape or reject this
   approach, not to ship it thin.

7. **Camera interaction.** `_on_holed_out` runs a 0.38s camera pan to `_cup_pos` in
   parallel. Does a longer drop need that retimed, or is parallel fine?

---

## Checks that must still pass

- `scripts/course/hole_out_feel_check.py` asserts `play_cup_drop` appears in
  `hole_controller.gd`, inside the `_on_holed_out` body, and inside
  `_on_practice_green_holed`; and that `_on_holed_out` contains no
  `tween_property(camera, "zoom"` and no `var close_z` / `var hold_z`.
- `scripts/ball/putt_pace_check.py`
- `scripts/course/putt_camera_zoom_check.py`
- `scripts/ui/scorecard_check.py`
- `scripts/course/short_game_practice_check.py`
- `scripts/course/practice_reps_check.py`

Propose any new assert that would lock the Phase 1 contract (e.g. capture geometry
untouched).

---

## Out of scope — do not touch

- `CUP_CAPTURE_RADIUS`, `CUP_RADIUS`, `CUP_CAPTURE_MAX_SPEED`, the cup sensor, the settle
  predicate — **capture geometry is frozen**
- `BALL_R_PUTT`, `BALL_R`, `PUTT_ZOOM_CAP`
- Lip-out deflection / Phase 2 physics
- Recording paths — `_on_ball_settled`, Club Coach, `set_actual`
- `ball_physics.gd` and anything in the pacing epic (`GRAVITY_PX`, roll friction)
- Any file not named in the plan's own file list

---

## Format

Follow the `plans/` convention: bug/gap description with file paths and line numbers plus
snippets, proposed change with example code, explicit out-of-scope list, acceptance
criteria tied to specific checks.

Acceptance must include:

- **Make rate provably unchanged** — state why (no capture constant or predicate moved)
- All checks listed above pass
- `visual.position` is cleared on reset

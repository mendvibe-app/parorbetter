# Epic: Shot Clearance Feedback — "Can I Clear That Tree?"

## Problem
Apex Carry made it possible to fly over a tree, but there's no way to tell
*before* swinging whether your current club/aim actually clears a specific
tree in the way. The aim cone is purely cosmetic with respect to trees —
players find out after the swing, the same "guess and see" problem that
motivated legible-feedback work elsewhere in the game.

## Current state (confirmed in code)

- The aim cone is built and colored with no tree awareness at all.
  `hole_controller.gd` `_refresh_aim_visuals()` (lines 1660–1720) sets the
  cone polygon from `AimControl.make_aim_cone(...)` and a fixed edge color
  `Color(1.0, 0.92, 0.4, ...)` — same yellow regardless of what's underneath
  it. `cone["colors"]` (vertex colors) already exists as a per-vertex
  channel from `AimControl.make_aim_cone` — this is the natural place to
  inject clearance-based tint, no new rendering pipeline needed.
- Tree data the game already tracks is split across two places:
  - `_trees` (`hole_controller.gd` line 90): `Array` of `{c: Vector2, r:
    float}` — used for lie classification (`_classify_lie()`, line 2233)
    and the minimap (`_hole_map.configure(...)`, line ~2089). **Does not
    carry canopy height.**
  - `canopy_h` is set as scene metadata directly on each tree's `Area2D`
    node (`_add_tree()`, lines 972–986: `tree_area.set_meta("canopy_h",
    canopy)`) — only reachable by walking scene nodes, not from `_trees`.
  - These need to be unified so a clearance check has both position/radius
    and height in one place without extra node lookups every frame.
- Club height data exists and is usable: `ball_physics.gd`
  `club_loft_mul()` (lines 28–38) and the `_height_peak` formula in
  `ball.gd` (line 281: `(28.0 + velocity.length() * 0.02) * loft_h`) — this
  is the same math Apex Carry already ships, just needs to run as a
  *prediction* before the swing instead of a *result* after it.

## Proposed change

1. **Unify tree data.** Add `canopy_h` into the `_trees` array entries
   alongside `c`/`r`, set at the same time as the `Area2D` meta in
   `_add_tree()`, so clearance checks don't need a scene walk.

2. **Add a clearance estimate.** Given the current aim line (ball →
   target), the selected club's `loft_mul`, and an assumed clean/typical
   contact (same baseline the existing dispersion-circle preview already
   uses), estimate `_height` at the point where the aim line crosses each
   tree's footprint — same sine-arc timing model `ball.gd` already uses,
   run as a lookup instead of a live simulation.

3. **Surface it on the cone.** For any tree the aim line crosses, tint
   that section of the cone (or the tree itself) to reflect estimated
   clearance — clear vs. blocked. Recompute live as the player drags aim
   or swaps clubs, so switching from 9-Iron to Pitching Wedge visibly
   changes the read in real time.

## Acceptance criteria

- With a fixed aim line crossing a known tree, switching to a club that
  would clear it vs. one that wouldn't produces a visibly different cone
  read, live, without re-aiming.
- Recalculates smoothly while dragging aim (no visible stutter/perf hit).
- Preview reads correctly for both short chip-outs and full-swing
  distances — the "point along the flight where the ball crosses this
  tree" logic has to hold at all distances, not just full-swing arcs.

## Design note

This is a **prediction**, not a **guarantee** — same as the existing
dispersion circle. A mishit can undershoot the apex the same way it
undershoots distance today. The feedback should read as "this club should
clear it on a clean strike," not "this club will 100% clear it." Worth
being explicit about that distinction in any copy, so a red-to-green
color flip doesn't get read as a promise.

## Out of scope

- Numeric readouts ("need 4 more yards of height") — keep this a visual
  affordance, consistent with the affordance-not-answer principle. If the
  color read alone isn't legible enough in playtest, the side-view
  apex-vs-tree preview discussed earlier is a bigger follow-up, not part
  of this pass.
- Any change to the actual apex/collision math — this epic only adds a
  *prediction* of what Apex Carry will do, it doesn't change what Apex
  Carry does.

## Playtest order

1. Aim through a known-tall tree (pine/tall canopy) with a low-loft club
   — confirm it reads as blocked.
2. Same aim line, swap to a wedge — confirm it flips to clear.
3. Swing it for real — confirm the actual outcome roughly matches what the
   cone predicted (allowing for mishit variance).
4. Drag aim off that tree entirely — confirm the cone returns to normal
   with no lingering red/blocked state.

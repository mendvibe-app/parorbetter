# Epic: Tree Apex Carry ("Over") — Height-Aware Tree Collision

## Problem
Trees currently block a shot on ANY 2D overlap, regardless of how the ball is
flying. There is no concept of a club or shot "flying over" a tree, even a
short one, even with a full wedge. This makes greenside trees pure walls
instead of obstacles you can sometimes carry.

## Root cause (confirmed in code)

- `scripts/ball/ball.gd` line 5: `_height` is explicitly a fake — comment
  reads *"Physics stay 2D top-down; _height fakes loft for arc readability."*
- `_height` is computed at line 455 purely from shot speed/air-time, with
  **no per-club or per-shot loft input**:
  ```gdscript
  _height = sin(clampf(t, 0.0, 1.0) * PI) * (28.0 + velocity.length() * 0.02)
  ```
- Tree collision fires unconditionally at lines 609–613 and 658–659:
  ```gdscript
  # Trees block air and roll — designed hazards, not ground-only surfaces.
  if other.is_in_group("tree"):
      _apply_lie_string("Trees", false)
  ```
  This check does not look at `_height`, flight `state`, or anything else —
  any physical overlap ends the shot into Trees lie.
- `scripts/ball/ball_physics.gd` lines 12–23 (`BAG`): every club is only
  `{"name": ..., "max_yards": ...}`. There is no loft or launch-angle value
  on any club — a Pitching Wedge and a Driver are physically identical in
  the flight model except for max distance.
- Trees already carry a `size` (canopy radius, ~24–42) and an `art` index
  (0–7) per hazard group, set in `scripts/course/hole_generator.gd`
  `_haz_tree()` (lines 808–813) and `_build_trees()` (lines 816–882). The
  `art` index maps to 8 existing tree sprites (`tree_tall`, `tree_airy`,
  `tree_broad`, `tree_oak`, `tree_dark`, `tree_round`, `tree_pine`,
  `tree_cluster`) — a natural, already-existing hook for a height tier
  without inventing new data from scratch.

## Proposed change

1. **Give clubs a loft/launch value.** Add a field to each `BAG` entry
   (e.g. `"loft_mul"`) — wedges and short irons get a higher multiplier,
   driver/woods/long irons get a lower one. Feed this into the existing
   per-shot loft logic in `ball_physics.gd` (it already varies `loft` by
   contact quality at lines 464–468 — extend that, don't replace it) so
   `_height`'s peak scales with club, not just swing speed.

2. **Give trees a height tier.** Map the existing `art` index (0–7) to a
   canopy height value — e.g. `tree_pine`/`tree_tall` = tall, `tree_round`/
   `tree_airy` = short. No new hazard data needed, just a lookup table.

3. **Make tree collision height-aware.** At the moment of overlap
   (lines 609–613 / 658–659), compare the ball's current `_height` against
   that tree's height threshold. Only convert to Trees lie if the ball is
   below the canopy at that point — otherwise let the shot fly through.

## Acceptance criteria

- A wedge shot at/near its apex clears a short-canopy tree (`round`/`airy`
  art) that would previously have stopped it.
- A Driver or low-loft club shot is still blocked by that same short tree —
  it doesn't get tall enough to matter.
- A tall/pine-canopy tree still blocks even a full wedge unless the shot's
  apex is unrealistically high (tune this — it should feel rare, not free).
- Ball still gets correctly caught into Trees lie on ground contact/roll,
  same as today — this only changes the **airborne** check.

## Out of scope (separate epics)

- Punch-out / deliberate low shot (Epic: Tree Punch-Out).
- Fade/draw shaping to go around a tree (Epic: Shot Shape from Swing Path).
- Any UI callout like "this tree is tall" — pure mechanic first, feedback
  can come later once the mechanic is confirmed to feel right.

## Notes / provisional values

- Height-tier thresholds and per-club `loft_mul` values are playtest
  targets, not finals — expect to tune after first pass, same as prior
  tempo/distance epics.
- This epic is a **prerequisite** for the punch-out epic (you need a real
  height comparison to duck under) but not for the shot-shape epic, which
  is independent.

## Playtest order

1. Wedge over a short greenside tree — confirm it carries.
2. Same tree, same spot, Driver — confirm it's still blocked.
3. Tall/pine tree, full wedge — confirm it's still mostly blocked (rare
   carries only at very high apex).
4. Regression: normal ground/rolling tree contact still works everywhere
   else on the course.

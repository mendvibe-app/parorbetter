# Epic 2 — Canopy Rebalance

**Phase:** 2 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/canopy-rebalance`, from main after Phase 1 (`8b4488d`)
**Gameplay change:** restores tree difficulty. Trees are currently trivial.

---

## Why this phase exists

Phase 1 tripled apex across the bag. `TREE_CANOPY_H` was calibrated against the old model
and never moved, so **every club now clears every tree**. Verified in the harness: a driver
at stock power passes all eight canopy types, and even a lob wedge clears seven of eight.
Trees have stopped being a decision.

---

## The thing that changes how this phase works

Clearance is **not** tested against apex. `hole_controller.gd:2199` calls
`BallPhysics.estimate_height_at_along()` — the ball's height *at the tree's position*. And
that height follows `sin((along / carry) × PI)`, so it depends on where the tree sits along
the shot:

| Driver @ 0.92 (apex 73.9) | Height at tree |
|---|---|
| Tree at 10% of total | 33.0 |
| Tree at 25% | 67.6 |
| Tree at 40% | 71.1 |
| Tree at 55% | 41.8 |
| Tree past carry (68%+) | 0.0 |

**Tree position matters more than club choice.** A driver 10% out is at half the height it
reaches 25% out. This means a single canopy number cannot produce consistent difficulty —
the same tree is trivial mid-flight and a wall near the tee.

Two consequences for this epic:

1. Canopy values must be tuned against **height at realistic tree positions**, not against
   apex. Tuning against apex is how the current values ended up meaningless.
2. Trees very close to the ball are now brutal in a way they weren't before, because the
   climb is steeper. Watch for this in playtest.

---

## Current values

`hole_controller.gd:74`, indexed to `TREE_TEXTURES`:

```gdscript
const TREE_CANOPY_H: Array[float] = [24.0, 38.0, 28.0, 32.0, 22.0, 30.0, 26.0, 42.0]
##                                   round  pine cluster oak  airy  dark broad tall
```

## Proposed values

```gdscript
## Clear height (same units as ball._height peak). Ball carries if _height >= this in flight.
## Index matches TREE_TEXTURES: round, pine, cluster, oak, airy, dark, broad, tall.
## Calibrated against the Phase 1 apex model, tested at height-at-tree for trees 20–35%
## down the hole. ALL PLAYTEST TARGETS.
const TREE_CANOPY_H: Array[float] = [62.0, 80.0, 68.0, 72.0, 55.0, 70.0, 64.0, 92.0]
##                                   round  pine cluster oak  airy  dark broad tall
```

Roughly 2.4–2.6× the current values, preserving the relative ordering that already reads
correctly in the art (airy lowest, tall highest).

### What this produces

**Tree 20% down the hole** — the common case, tree guarding a corner:

| Club @ 0.92 | Height at tree | Clears |
|---|---|---|
| Driver | 59.0 | airy only |
| 5-Iron | 51.6 | none |
| 7-Iron | 48.1 | none |
| PW | 42.9 | none |
| LW | 34.1 | none |

**Tree 35% down the hole** — mid-flight, near the top of the arc:

| Club @ 0.92 | Height at tree | Clears |
|---|---|---|
| Driver | 73.9 | 6 of 8 (not pine, not tall) |
| 7-Iron | 65.8 | 3 of 8 |
| PW | 60.9 | airy only |

That contrast is the design intent: **a tree near you is a problem to go around; a tree
downrange is a problem you can fly.** That is how real golf works and it is what the
height-at-along model gives us for free once the numbers are right.

**Tall (92) is a genuine wall.** Nothing in the bag clears it at any position. This is
deliberate — it preserves the "punch out sideways, take your medicine" situation. If
playtest says that is too punishing, lower it; it is flagged.

**Punch still ducks.** A 7-iron punch at 0.80 reaches 14.6 at 20% and 20.0 at 35% — under
every canopy including the lowest (airy at 55) by a wide margin. Punch is safe.

**Half-power shots are blocked by everything.** A driver at 0.46 reaches 29.5 at 20% out and
clears nothing. Laying up now means accepting you cannot fly the tree, which is correct.

---

## Changes

### 1. `scripts/course/hole_controller.gd`

Line 74 — replace `TREE_CANOPY_H` with the proposed array. Update the comment block above it
(lines 71–73), which still describes the old scale ("Short ~22–28", "tall ~42 hard wall").

That is the only production change in this epic.

### 2. `scripts/debug/debug_controls.gd`

The debug string and the sparkline reference lines are hardcoded to the old canopy values
(`short~22–28 pine~38 tall~42`). Update both to read from the new scale so the sparkline
stays a truthful instrument. **Prefer referencing `HoleController.TREE_CANOPY_H` over
hardcoding a second copy** — a second copy is how these drifted in the first place.

Suggested reference lines: airy (lowest, 55), oak (mid, 72), tall (highest, 92).

### 3. `scripts/course/canopy_check.py` (new, or extend an existing course check)

Follow the house `*_check.py` convention: parse `TREE_CANOPY_H` from `hole_controller.gd`
and assert the invariants below rather than hardcoding the numbers.

- Punch (7-iron @ 0.80) height at 20% and 35% is under the lowest canopy
- A stock driver clears at least one canopy type at 35% out
- A stock driver clears no more than two canopy types at 20% out
- The tallest canopy is above a stock driver's apex (unclearable by design)
- Array length matches `TREE_TEXTURES` length

---

## Out of scope

- **Tree placement, density, or position on holes.** This epic changes heights only. If the
  playtest reveals that trees are placed badly relative to the tee, that is a course-design
  epic, not this one.
- **`PUNCH_UNDER_CANOPY_FRAC`** (0.88, `ball_physics.gd:193`). Punch has ample margin; leave
  it.
- **`air_distance_fraction`.** Phase 3. Note that Phase 3 will change carry, which shifts
  where along the shot the apex falls — canopy values may need one more small pass after it.
  Expected, not a reason to delay.
- Anything in the flight model itself.

---

## Acceptance criteria

1. A stock driver clears **at most 2** canopy types when the tree is 20% down the hole.
2. A stock driver clears **at least 4** types when the tree is 35% down.
3. A 7-iron punch clears **nothing** at any position.
4. Tall canopy is unclearable by every club at every position.
5. A half-power driver clears nothing at 20% out.
6. The debug sparkline reference lines match the new values and are not a hardcoded copy.
7. All `*_check.py` pass, including the new canopy check.
8. Flight-model goldens **unchanged at 11/13** — this epic touches no flight physics. Any
   movement means something out of scope changed.

---

## Playtest verification order

1. Find a hole with a tree near the tee. Drive at it. It should block — this is the case
   that was trivial before and should now feel like a real obstacle.
2. Find a tree further down the fairway. Drive at it. It should clear. **The contrast
   between 1 and 2 is the whole point of this phase.**
3. Punch under a tree from the rough. Must still work.
4. Hit a tall tree with everything in the bag. Nothing should clear it.
5. Play three holes normally. The question to answer: **are trees a decision again, or are
   they now a wall?** Over-correcting is the likely failure mode here.

---

## Notes for the agent

- Read this document and confirm your understanding before writing code.
- Touch only: `scripts/course/hole_controller.gd`, `scripts/debug/debug_controls.gd`, and
  the new check file.
- All eight canopy values are playtest targets. If one needs to move, **report the proposed
  value and reasoning** rather than changing it silently.
- Report line-number drift as in previous phases.
- Do not touch `ball_physics.gd` or `ball.gd`. The flight model is settled.

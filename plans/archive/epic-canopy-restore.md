# Correction — Canopy Restore

**Track:** correction following Phase 3. Not a numbered phase.
**Branch:** `fix/canopy-restore`, from main after Phase 3
**Anticipated by:** Epic 2, which flagged that Phase 3 would shift clearance.
**Size:** one constant array and its check.

---

## What happened

Phase 3 raised carry across the bag, which stretches the flight arc. At any fixed point down
the hole the ball is now **lower** than it was, because it reaches apex further out.

The drift is smaller than Epic 3 predicted. Phase 2's acceptance criteria technically still
pass — a stock driver clears 0 types at 20% out (target was ≤2) and 4 at 35% (target was ≥4).
The driver is essentially fine.

**The loss is at the mid-iron end.** Approach shots lost their options:

| Case | Phase 2 verified | After Phase 3 | Proposed |
|---|---|---|---|
| Driver @ 20% | 1 clear | 0 | 1 |
| Driver @ 35% | 6 clears | 4 | 6 |
| **7-Iron @ 35%** | **3 clears** | **1** | **4** |
| PW @ 35% | 1 clear | 1 | 2 |

A 7-iron over a downrange tree went from three tree types it could fly to one. That removes
the "club up and go over it" decision from approach play, which was the point of Phase 2.

---

## The change

Scale `TREE_CANOPY_H` by **0.90**, preserving all relative ordering.

```gdscript
## Clear height (same units as ball._height peak). Index matches TREE_TEXTURES:
## round, pine, cluster, oak, airy, dark, broad, tall.
## Rescaled x0.90 after Phase 3 lengthened carry and flattened height-at-tree.
## ALL PLAYTEST TARGETS.
const TREE_CANOPY_H: Array[float] = [56.0, 72.0, 61.0, 65.0, 50.0, 63.0, 58.0, 83.0]
##                                   round  pine cluster oak  airy  dark broad tall
```

**Why 0.90 and not more.** x0.85 over-corrects — a 7-iron at 35% jumps to 6 clears, double
its Phase 2 value, which would make downrange trees a non-decision. x0.90 restores the driver
exactly and leaves the irons marginally easier than before.

**Why not less.** The tall canopy must stay above a stock driver's apex (73.9) to remain a
genuine wall. At x0.90 tall is 82.8, with margin. The floor is x0.81, below which tall
becomes clearable and the "punch out sideways" situation disappears.

**Punch is unaffected.** A 7-iron punch reaches 12.5 px at 20% out against a new lowest
canopy of 50 — still ducking with a wide margin.

---

## Changes

### `scripts/course/hole_controller.gd`
Line ~75 — replace the array and update the comment to note the Phase 3 rescale.

### `scripts/course/canopy_check.py`
The existing assertions parse `TREE_CANOPY_H` rather than hardcoding it, so they should
survive. Verify, and confirm the acceptance bands still express the intent:

- Driver clears ≤ 2 at 20%, ≥ 4 at 35%
- 7-iron clears **≥ 2 at 35%** — add this. It is the case that degraded, and its absence is
  why the drift went undetected by the suite.
- Punch clears nothing at any position
- Tall is above stock driver apex

### `scripts/debug/debug_controls.gd`
No change expected — the sparkline reads `HoleController.TREE_CANOPY_H` after Phase 2. Confirm
rather than assume.

---

## Out of scope

- `air_distance_fraction`, apex, hang time, the bag. All settled.
- Tree placement or density.
- `PUNCH_UNDER_CANOPY_FRAC`.
- The bag-calibration question (driver totals 239 vs a real ~275). Separate epic.

---

## Acceptance criteria

1. Driver clears ≤ 2 canopy types at 20% out, ≥ 4 at 35%.
2. 7-iron clears ≥ 2 at 35% — the regression this epic fixes.
3. Tall remains above stock driver apex; nothing in the bag clears it.
4. A 7-iron punch clears nothing at any position.
5. All `*_check.py` pass. Flight goldens unchanged at 13/15.

---

## Playtest verification

1. Drive at a tree near the tee — should still block.
2. Drive at a tree downrange — should still clear. The near/far contrast is Phase 2's core
   result and must survive.
3. **7-iron approach over a downrange tree — should clear.** This is what regressed.
4. Punch from the trees — must still duck.
5. Nothing in the bag should clear a tall tree.

---

## Notes for the agent

- Touch only `hole_controller.gd` and `canopy_check.py`.
- Do not touch any flight-model constant.
- If a value needs to move from x0.90, report it with reasoning.

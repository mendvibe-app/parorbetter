# Epic — Punch Legibility

**Track:** correction, outside the 8-phase flight rebuild
**Branch:** `fix/punch-legibility`, from main after Phase 2
**Found:** Phase 2 playtest — punch aim line showed blocked everywhere, and two punch
attempts both graded MISS.

---

## Two independent problems

### 1. The aim preview lies about punch

`_aim_tree_clearance()` (`hole_controller.gd:2155`) only models **flying over** a canopy:

```gdscript
var h := BallPhysics.estimate_height_at_along(along, total_px, air_frac, peak)
if h < canopy:
    any_block = true
```

But punch doesn't fly over — it **ducks under**. `ball.gd:707-711` already implements that:

```gdscript
if _punch_flight and _height <= canopy * BallPhysics.PUNCH_UNDER_CANOPY_FRAC:
    return   # pass through, no strike
```

So a punch that would sail cleanly under a tree gets painted red by the aim line. The physics
is correct; the preview is wrong. After Phase 2 raised canopies, this went from occasional to
always — punch apex is ~8–20 px against a lowest canopy of 55, so the preview now shows
blocked for every tree on every punch.

**This is not a canopy tuning problem.** Raising `APEX_SCALE_PUNCH` would be actively harmful:
it would lift the ball into the `0.88 × canopy` to `canopy` band, where it neither clears nor
ducks — a kill zone. Punch apex stays where it is.

### 2. Punch is graded as a full swing

`tempo_grade.gd:69-71`:

```gdscript
static func target_ratio(shot_type: String) -> float:
	# Punch uses full 3:1; putt/pitch/flop are short-game 2:1 tempo.
	return TARGET_SHORT if shot_type == "putt" or shot_type == "pitch" or shot_type == "flop" else TARGET_FULL
```

**Real golf says this is wrong.** Tour Tempo's core finding is that downswing duration is
roughly fixed — governed by the kinetic sequence and gravity — while backswing duration
scales with backswing length. Ratio therefore falls out of how far back you go: full swing
3:1, putting 2:1.

A punch is *defined* by an abbreviated backswing: three-quarter or less, ball back, hands
ahead, held-off finish. Shorter backswing against a similar downswing means a **lower ratio
than a full swing**. Asking for 3:1 is asking the player to make a full-length backswing and
then hit a punch.

Live evidence — two attempts, both naturally at 1.7–1.8:1, both graded MISS:

| Config | 1.8:1 swing | 1.7:1 swing |
|---|---|---|
| Current — 3:1 target, `TOL_FULL` | MISS | MISS |
| **2:1 target, `TOL_FULL`** | **PERFECT** | **GOOD** |
| 2:1 target, `TOL_SHORT` | PERFECT | PERFECT |

---

## Changes

### 1. `scripts/shot/tempo_grade.gd` — punch targets 2:1

Add `"punch"` to the short-target list in `target_ratio()` and update the comment, which
currently states the opposite.

**Do not change `base_tolerance()`.** Punch keeps `TOL_FULL`. Short-game tolerance on top of
the corrected target makes everything PERFECT (see table above); with `TOL_FULL` the player
still has to hit it — 1.3:1 grades THIN/FAT and 3:1 grades MISS. A punch is a control shot
from a bad lie, not a free pass.

No new tempo constant. `TARGET_SHORT` already exists.

**Free consequence, verify it happens:** `guide_back_ms()` (line 195) selects the short guide
when `target_ratio(shot_type) < 2.5`, and `guide_down_ms()` divides by the target. So the
ghost guide and meter ticks should switch to short-swing timing automatically. Confirm this
rather than adding a second code path.

### 2. Route punch into the grade path

`shot_routine.gd:408` calls `TempoGrade.grade(sample, shot_type, ...)` with the picker /
recommended shot type. `punch_mode` is only surfaced via `flight_shot_type()` (line 195),
which feeds physics — **not grading**. So `target_ratio()` never sees `"punch"` today.

Make the grade call aware of punch mode. Prefer reusing `flight_shot_type()` if its mapping
is correct for grading; if it is not (it excludes putt and chip), add the smallest routing
that gets `"punch"` to `grade()` when `punch_mode` is true. **Report which approach you take
and why** — this is the one design decision in the epic.

### 3. `scripts/course/hole_controller.gd` — aim preview understands ducking

In `_aim_tree_clearance()`, when the shot is a punch, apply the same rule `ball.gd` uses:

```gdscript
# Punch ducks under foliage rather than carrying it (mirrors ball.gd tree collision).
# Under the band → passes; inside 0.88*canopy..canopy → strike.
if is_punch and h <= canopy * BallPhysics.PUNCH_UNDER_CANOPY_FRAC:
    continue   # not a block
```

The function already receives a `punch` argument at its call site (line 2316) — check whether
it is currently used at all.

**Consider a third state.** The function returns `"clear"` / `"blocked"` / `"none"`. A punch
passing *under* a tree is meaningfully different from a full swing carrying *over* it, and
showing the same colour for both loses information the player wants. If a third state (e.g.
`"under"`) is cheap to thread through to the aim tint, propose it. If it is invasive, return
`"clear"` and note it as follow-up — do not build a large UI change inside this epic.

### 4. Checks

Update or add `*_check.py` assertions:

- `target_ratio("punch") == TARGET_SHORT`
- `base_tolerance("punch") == TOL_FULL` (guards against the double-gift)
- `guide_back_ms("punch")` returns the short guide
- A punch below `0.88 × min(TREE_CANOPY_H)` is not reported blocked by aim clearance
- A punch inside the `0.88 × canopy` to `canopy` band **is** reported blocked

Existing tempo checks likely assert the old 3:1 punch behaviour. Report anything that breaks
before changing it.

---

## Out of scope

- `APEX_SCALE_PUNCH`. Punch apex is correct; raising it creates a kill zone.
- `TREE_CANOPY_H`. Phase 2 values are verified and stay.
- `PUNCH_UNDER_CANOPY_FRAC` (0.88). Leave it.
- Any flight-model change. Goldens must stay at 11/13.
- Making punch selectable outside the Trees lie. Real golf would allow it — into wind, under
  branches, off a tight lie — and the shot-type picker already has a column it could join.
  That is a product decision for its own epic, logged not built.

---

## Acceptance criteria

1. `target_ratio("punch")` returns 2.0; `base_tolerance("punch")` returns `TOL_FULL`.
2. A punch swing at 1.8:1 from a Trees lie grades **PERFECT**; at 1.7:1 grades **GOOD**;
   at 3.0:1 grades **MISS**. (These are the live numbers from playtest.)
3. The ghost guide and meter ticks show short-swing timing in punch mode.
4. Aim clearance no longer reports blocked for a punch that will pass under the canopy.
5. Aim clearance still reports blocked for a punch inside the strike band.
6. All `*_check.py` pass. Flight goldens unchanged at 11/13.

---

## Playtest verification

1. Hit into the trees. Toggle Punch. **The aim line should no longer be red everywhere.**
2. Punch out under a tree. It should escape, and grade something other than MISS if the tempo
   is near 2:1.
3. Check the ghost guide in punch mode — it should be pacing a short swing, not a full one.
4. Deliberately swing a full 3:1 tempo while in punch mode. It should grade badly. The shot
   should still be hittable, not automatic.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only: `tempo_grade.gd`, `shot_routine.gd`, `hole_controller.gd`, and check files.
- The routing decision in change 2 is the one judgement call — report it rather than picking
  silently.
- Report line-number drift as in previous phases.

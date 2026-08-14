# Correction — Bag Calibration

**Track:** correction following Phase 3. Not a numbered phase.
**Branch:** `fix/bag-calibration`, from main after the canopy restore
**Contains two separable changes.** Part A is a correction to the test suite and should ship
regardless. Part B is a gameplay change and is Matt's call.

---

## Background

Phase 3 fixed the carry/roll split and left two goldens permanently red:

```
FAIL  Driver total_yd   239.2   want 250.0-275.0
FAIL  7-iron total_yd   147.2   want 160.0-180.0
```

Those ranges encode **PGA Tour** distances. The game produces a 239-yard driver, which maps
to a solid single-digit amateur — a reasonable player-character for a golf game and almost
certainly the intended feel. The goldens are testing against a spec nobody chose.

Grounding against amateur launch-monitor data (Arccos / Shot Scope aggregates, ~10 handicap):

| Club | Game carry @ 0.92 | 10-hcp target | Delta |
|---|---|---|---|
| Driver | 218 | 220 | −2 |
| 3-Wood | 199 | 200 | −1 |
| Hybrid | 179 | 185 | −6 |
| 5-Iron | 163 | 170 | −7 |
| 6-Iron | 151 | 158 | −7 |
| 7-Iron | 139 | 145 | −6 |
| 8-Iron | 127 | 133 | −6 |
| 9-Iron | 114 | 120 | −6 |
| PW | 98 | 107 | **−10** |
| GW | 85 | 95 | **−10** |
| SW | 72 | 82 | **−10** |
| LW | 59 | 68 | **−9** |

**The driver is correct. The shortfall grows steadily toward the wedges**, reaching ~12%. So
the player's long game is a 10-handicap and their wedge game is closer to a 15. Nobody chose
that split — `max_yards` predates this work.

Gapping is already good after Phase 3 (12–20 yards throughout), so this is calibration drift,
not a structural problem.

---

## Part A — Re-spec the goldens *(ship this regardless)*

Replace the two Tour-distance goldens with amateur-grounded ones:

```
Driver total_yd    230-250   (currently 239)  -> PASS
7-iron total_yd    140-160   (currently 147)  -> PASS
```

This is **not loosening a frozen golden.** The frozen ranges encode *real golf*, and real golf
for this player is amateur, not Tour. The original ranges were written before we knew what
handicap the game modelled. Add a comment in the check file recording that decision so it is
not re-litigated later.

Everything else in the suite stays frozen. Expected result: **15/15**.

---

## Part B — Rescale the bag *(product decision)*

Bring `max_yards` up so every club lands on its 10-handicap target, making the bag internally
consistent.

```gdscript
## max_yards is the club's total distance ceiling. Calibrated so a stock swing (0.92)
## carries the ~10-handicap amateur average for each club (Arccos / Shot Scope aggregates).
## PLAYTEST TARGETS.
```

| Club | `max_yards` now | Proposed | Resulting carry | Target |
|---|---|---|---|---|
| Driver | 260 | **265** | 222 | 220 |
| 3-Wood | 235 | 235 | 199 | 200 |
| Hybrid | 210 | **215** | 183 | 185 |
| 5-Iron | 190 | **200** | 171 | 170 |
| 6-Iron | 175 | **185** | 159 | 158 |
| 7-Iron | 160 | **165** | 143 | 145 |
| 8-Iron | 145 | **150** | 131 | 133 |
| 9-Iron | 130 | **135** | 119 | 120 |
| PW | 110 | **120** | 106 | 107 |
| GW | 95 | **105** | 93 | 95 |
| SW | 80 | **90** | 80 | 82 |
| LW | 65 | **75** | 67 | 68 |

Resulting carry gaps: 23, 16, 12, 12, 16, 12, 12, 13, 13, 13, 13 — realistic, with the
expected larger jump between driver and 3-wood.

### Why this is a real decision, not obvious polish

**It makes the whole course easier.** Every hole was designed around current distances. Wedges
gaining 10 yards and mid-irons gaining 6 means shorter approach clubs everywhere, and par 4s
that used to need a 7-iron now need an 8. Hole pars and green sizes were tuned against the old
bag.

**Partial fixes don't work.** Bumping only the wedges compresses the 9-iron→PW gap from 16
yards to 8. The bag moves together or not at all.

**The counter-argument is legitimate:** a slightly short wedge game is a defensible design
choice. It makes approach play demand more club, which raises the difficulty of scoring
without changing anything structural. If the game currently *feels* right, leaving `max_yards`
alone is a fine answer — and Part A still ships.

**Recommendation:** ship Part A now. Take Part B only if wedge distances have felt short in
play. If unsure, ship A, play a few rounds paying attention to approach clubs, and decide
after.

---

## Changes

### Part A — `scripts/ball/flight_model_check.py`
Update the two `total_yd` golden ranges and add the rationale comment. No other assertion
changes.

### Part B — `scripts/ball/ball_physics.gd`
Update `max_yards` in `BAG`. **`loft_mul` does not change** — apex is driven by `REAL_APEX_FT`
keyed on `max_yards`, so verify how the nearest-key lookup behaves with the new values. If a
club's `max_yards` now rounds to a different `REAL_APEX_FT` key, **report it** — that would
silently move apex, which is out of scope.

### Part B — `scripts/ball/flight_model_check.py`
Re-run all goldens against the new bag. **Apex goldens must not move.** If they do, the
`REAL_APEX_FT` lookup shifted and that needs resolving before merge.

---

## Out of scope

- `air_distance_fraction`, apex, hang time, `GRAVITY_PX`, canopies. All settled.
- Hole design, par values, green sizes. If Part B lands and holes feel easy, that is a
  course-design pass, not this epic.
- `loft_mul` values.
- Club Coach history. Already stale; Phase 7 resets it.

---

## Acceptance criteria

**Part A**
1. Both `total_yd` goldens PASS. Suite reports **15/15**.
2. No other golden range changed.

**Part B** (if taken)
3. Every club's stock carry within 3 yards of its 10-handicap target.
4. All adjacent carry gaps ≥ 8 yards.
5. **Apex goldens unchanged** — the `REAL_APEX_FT` lookup must not shift.
6. All `*_check.py` pass. `club_identity_check.py` and `club_bag_check.py` likely assert on
   `max_yards` — report before changing.

---

## Playtest verification (Part B only)

1. Driver — should carry ~222.
2. Approach with a 7-iron to a known 145-yard target. It should be the right club now.
3. Full wedges — PW ~106, SW ~80. These gained the most.
4. **Play three holes and pay attention to club selection.** The question: do holes now play a
   club shorter, and does that make them too easy?

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- **Ship Part A first as its own commit**, so it can merge even if Part B is declined.
- Report every check file that asserts on `max_yards` before touching the bag.
- The `REAL_APEX_FT` nearest-key interaction is the one hidden risk in Part B. Check it
  explicitly and report what you find.

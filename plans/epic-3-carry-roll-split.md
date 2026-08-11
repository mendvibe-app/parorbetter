# Epic 3 — Carry and Roll Split

**Phase:** 3 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/carry-roll-split`, from main after Phase 2 + punch corrections
**Gameplay change:** large. Every club carries substantially further and rolls substantially
less. Tree difficulty shifts as a side effect (see *Downstream*).

**Absorbs:** short-game-roadmap.md Phase 2 (chip roll-ratio retune). That work already
shipped and is playtest-verified — this epic explicitly preserves it.

---

## Why this phase exists

`air_distance_fraction()` decides how much of a shot is carry and how much is roll. It has
two problems.

**It is far too low across the bag.** A driver carries 163 of its 239 yards and rolls 77.
Real golf is roughly 250 carry and 25 roll. Every club in the game is modelled as though it
lands on a firm links fairway and releases hard.

**It is a step function, and the steps have collapsed the middle of the bag.**
`_air_fraction_full()` returns fixed values at bucket boundaries (245, 180, 150, 120, 95, 75
yards). When a club crosses a boundary, the jump in carry fraction almost exactly cancels the
drop in total distance:

| Adjacent pair | Carry gap now | Should be |
|---|---|---|
| 5-Iron → 6-Iron | **0.3 yd** | ~12 |
| 7-Iron → 8-Iron | **2.8 yd** | ~12 |
| Driver → 3-Wood | 7.0 yd | ~19 |

This is visible in live Club Coach data, which has shown 6I/7I/8I/9I clustering at 101–118
yards for weeks. **Four clubs in the middle of the bag are functionally one club**, and it is
a step-function artifact rather than a tuning problem. No amount of adjusting bucket values
fixes it; the buckets themselves are the bug.

---

## The model

Replace the buckets with a continuous ramp grounded in real carry-to-total ratios.

```
carry_fraction = lerp(CARRY_FRAC_SHORT, CARRY_FRAC_LONG, (club_max - 65) / (260 - 65))
```

Real golf carries almost everything and rolls a little. Long clubs land shallow and release;
short clubs land steep and stop. The relationship is monotonic in club length, so a linear
ramp in `club_max_yards` is a good proxy without needing landing-angle machinery.

```gdscript
## Carry share of total distance. Long clubs land shallow and release; short clubs land
## steep and stop. Calibrated to PGA Tour carry/total ratios. PLAYTEST TARGETS.
const CARRY_FRAC_LONG := 0.91   ## driver end (260 yd club)
const CARRY_FRAC_SHORT := 0.98  ## lob wedge end (65 yd club)
```

### Resulting bag @ power 0.92

| Club | Total | Carry now | **Carry new** | Roll new | Real ratio |
|---|---|---|---|---|---|
| Driver | 239 | 163 | **218** | 22 | 0.91 |
| 3-Wood | 216 | 156 | **199** | 18 | 0.92 |
| Hybrid | 193 | 139 | **179** | 14 | 0.93 |
| 5-Iron | 175 | 126 | **163** | 11 | 0.94 |
| 6-Iron | 161 | 126 | **151** | 10 | 0.94 |
| 7-Iron | 147 | 115 | **139** | 8 | 0.95 |
| 8-Iron | 133 | 112 | **127** | 6 | 0.95 |
| 9-Iron | 120 | 100 | **114** | 5 | 0.96 |
| PW | 101 | 91 | **98** | 4 | 0.97 |
| GW | 87 | 79 | **85** | 3 | 0.97 |
| SW | 74 | 69 | **72** | 2 | 0.98 |
| LW | 60 | 57 | **59** | 1 | 0.98 |

**Gapping is restored across the whole bag** — every adjacent pair separates by 12–19 yards,
and the two broken pairs go from 0.3 and 2.8 to 12.0 and 12.3.

### Shot-type modifiers

Two change and two do not.

| Type | Now | Proposed | Grounding |
|---|---|---|---|
| **chip** | 0.20–0.33 absolute | **unchanged** | Playtest-verified in the short-game work. Absolute, so the base change does not touch it. Do not retune. |
| **flop** | 0.92–0.98 absolute | **unchanged** | Near-zero roll is correct and already verified on device. |
| **pitch** | `lerp(full, 0.72, 0.55)` → ~0.75 | **absolute 0.90** | A partial wedge lands steep and stops. Pinning it to an absolute value stops it drifting whenever the full-swing base moves. |
| **punch** | `full × 0.72` → ~0.68 | **`full × 0.88`** → ~0.83 | A knockdown lands shallow and runs — real numbers are roughly 150 total / 125 carry. It should still roll more than a full shot, just not twice as much. |

Pitch moves from derived to absolute deliberately: it is the only shot type whose behaviour
would otherwise change silently every time the base ramp is retuned.

---

## Two things this phase does NOT fix

### The carry goldens still cannot pass, and the reason is not carry

`Driver stock carry_yd` wants 250–275. After this phase a stock driver carries **218**. The
gap is not in the split — 218/239 is exactly the real 0.91 ratio. The gap is that **the
driver's total is 239 where real golf is 275**.

`club_max_yards` for the driver is 260, and a stock swing is 0.92 of that. The bag itself is
calibrated below tour distance.

**That is a product decision, not a physics bug**, and it is Matt's call: *should a stock
drive in this game be 239 yards or 275?* A 239-yard drive is a perfectly reasonable amateur
number and may be the intended feel. Tour distance would mean raising the whole bag.

**Action for this epic:** split the conflated golden into two.

- `Driver carry/total ratio` in 0.89–0.93 → **this phase makes it pass**
- `Driver total_yd` in 250–275 → **stays failing**, and now names the real question

Same for the 7-iron. This is not loosening a golden; it is separating two different claims
that were bundled into one. Every other golden stays frozen.

### Trees get harder — Phase 2 will need a touch-up

Longer carry stretches the flight arc, so at any fixed point down the hole the ball is
**lower** than it was:

| Tree at % of total | Height before | Height after |
|---|---|---|
| 15% | 47.1 | **36.5** |
| 20% | 58.9 | **47.0** |
| 30% | 72.6 | **63.5** |
| 40% | 71.2 | 72.5 |

A driver at 20% out drops from 59 to 47 px, which clears nothing (lowest canopy is 55). Trees
near the tee become materially harder.

**Do not touch `TREE_CANOPY_H` in this epic.** This was anticipated in Epic 2. It gets its own
small pass after this phase is playtested, so the canopy change can be attributed separately.
Expect the playtest to feel tree-heavy.

---

## Changes

### `scripts/ball/ball_physics.gd`

1. Add `CARRY_FRAC_LONG` and `CARRY_FRAC_SHORT` near the other playtest knobs.
2. Replace `_air_fraction_full()` with the continuous ramp. **Delete the bucket ladder
   entirely** — do not leave it dead. `AIR_DISTANCE_FRACTION` (the old 0.78 mid-bucket
   constant) becomes unused; report every other reference before removing it.
3. In `air_distance_fraction()`: pitch becomes absolute 0.90; chip and flop unchanged.
4. `PUNCH_AIR_FRAC_SCALE` 0.72 → 0.88.
5. Check the `lie == "Sand" and shot_type == "full"` override (`air_frac = 0.55`). That was
   calibrated against the old scale and is now far out of line with everything else. **Report
   what it should be rather than changing it silently.**

### `scripts/ball/flight_model_check.py`

Parse the new constants. Split the two carry goldens as described above. Add:

- Carry/total ratio within 0.02 of the real ratio for every club in the bag
- **Adjacent-club carry gap ≥ 8 yards for every pair** — this is the regression test for the
  collapsed middle irons and the most valuable new assertion in the phase
- Monotonic carry fraction from Driver to Lob Wedge
- `air_distance_fraction("chip", ...)` unchanged from its current values (guards the
  playtested short-game work)

---

## Out of scope

- `TREE_CANOPY_H` — follow-up pass after playtest.
- `total_yards`, `club_max_yards`, the bag, and any distance multiplier. The bag-calibration
  question is raised here and answered elsewhere.
- Apex, hang time, `GRAVITY_PX`. Phase 1 is settled and this phase must not move apex goldens.
- Roll friction and the roll distance clamp. Phase 5.
- Chip and flop fractions. Verified on device; leave them alone.

---

## Acceptance criteria

1. Carry/total ratio within 0.02 of the real ratio for every club.
2. **Every adjacent club pair separates by ≥ 8 yards of carry.**
3. Carry fraction is monotonic across the bag with no steps.
4. Chip and flop carry fractions are byte-identical to before.
5. Apex goldens unchanged — this phase must not move Phase 1's results.
6. `Driver carry/total ratio` golden PASSES; `Driver total_yd` golden still FAILS.
7. All `*_check.py` pass.
8. On device: a stock driver reports carry ≈ 218 and roll ≈ 22.

---

## Playtest verification order

1. Driver from the tee. Carry ~218, roll ~22. **It should look like a drive that flies and
   settles, not one that lands early and skitters.**
2. Hit 6-iron, 7-iron, 8-iron at the same target. **They must land in three clearly different
   places.** This is the phase's headline fix and the thing your Club Coach has been
   complaining about.
3. Greenside chip. Must feel identical to before — if it changed, something outside scope moved.
4. Pitch from ~40 yards. Should land softer and roll less than it used to.
5. Punch from the trees. Should still run out, just less extremely.
6. Play three holes. Expect trees to feel too hard — that is the known follow-up, not a bug.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `scripts/ball/ball_physics.gd` and `scripts/ball/flight_model_check.py`.
- Report line-number drift as in previous phases.
- If a constant needs to move from the proposed values, **report the value and reasoning**.
- The Sand override and any remaining `AIR_DISTANCE_FRACTION` references are report-first
  items, not silent fixes.

# Flight Model Rebuild — Roadmap

**Status:** planning. No code written yet.
**Owner:** Matt (design/diagnosis) → coding agent (implementation, one phase per PR)
**Supersedes:** short-game-roadmap.md Phases 2–6 (see *Relationship to existing work*)

---

## The problem in one paragraph

Par or Better does not simulate ball flight. It computes a distance answer up front
(`club_max × power × lie × contact`), splits that answer into carry and roll, invents a
hang time, and then **divides distance by time to get speed**. The ball is puppeted toward
the pre-computed answer, and the flight animation is decorative — height is
`sin(t × PI) × peak`, with no gravity and no relationship to the ball's actual motion.

That architecture is defensible for a 2D top-down mobile game. The failure is that we have
been *tuning it as if it were a simulation*. Because speed is an output of distance and
time, every change to hang time, carry fraction, or loft silently moves speed — and
therefore trajectory, tree collisions, camera framing, and landing energy. That is the
whack-a-mole. It is structural, not a series of unrelated bugs.

## Evidence

Measured by the faithful offline port in `scripts/ball/flight_model_check.py` (stock power
0.92 = top of pocket, fairway, GOOD contact). Numbers below replace earlier main-branch
estimates that used power 1.00 without force taxes / current bag.

| Symptom | Current (harness stock 0.92) | Real golf |
|---|---|---|
| Driver apex | **9.9 yd** (22.3 px) | 30–40 yd |
| 7-iron apex | **13.8 yd** (31.1 px) | ~32 yd |
| **3-yard chip apex** | **17.4 yd** (39.2 px) | 1–3 yd |
| Driver total | **~239 yd** | ~275 yd (~13% low) |
| Driver carry / roll | **163 / 77 yd** | ~250 / ~25 yd |
| 7-iron carry | **115 yd** | ~172 yd |
| Hang time, driver → SW | **0.61s → 1.54s** (~2.5× rise) | ~6.4s → ~5.0s (flat, slight fall) |
| Clubs that clear a pine (38 px) | PW and shorter only | most of the bag |

**Carry is the hidden failure.** Driver total is only ~13% low (239 vs ~275), so scorecard
distance looks almost plausible. But the split is **163 carry / 77 roll** where real golf is
roughly **250 / 25** — carry is ~**35% short** while roll is inflated. Totals look nearly
right on the scorecard while the ball never spends enough of its trip in the air. Nothing
in the old UI flagged that.

**A greenside chip currently flies higher than a full driver** (~17 yd apex vs ~10 yd). Apex
is dominated by a flat `28.0 +` constant in `ball.gd` peak formula, so it is effectively
*constant × loft_mul* — and since wedges have the highest loft_mul, the shortest shots fly
the highest. The bag is upside down. This is also the real cause of "trees are unclearable":
trees are fine; the bag apexes at a third of real height (driver fails short/pine/tall).

Hang time is inverted for the same reason. In real golf hang time is nearly flat across the
bag (~5–7s) and *distance* comes from speed. Our model varies hang time ~2.5× in the wrong
direction and derives speed from it.

## Root causes (what we are actually fixing)

1. **Apex and hang time are invented separately from each other and from the ball's motion.**
2. **Speed is an output, not an input** — so nothing can be tuned in isolation.
3. **Five independent multipliers stack on distance** across two files, with no single owner.
4. **Plan and simulation are allowed to disagree**, and the disagreement is patched three
   separate times in `_process_flight` / `_process_roll` rather than resolved.
5. **Height is invisible in a top-down game**, so none of the above was observable in play.
6. **Distance totals being approximately correct masked a badly wrong carry/roll split and a
   badly wrong trajectory** — total yards near the real number hid short carry, long roll,
   and low apex until the harness separated them.

## Guardrails

- **One phase = one PR = one playtest pass.** Non-negotiable. This plan is exactly the kind
  of work that produces untraceable regressions if bundled.
- **Run `harness.py` before and after every phase.** Attach the before/after golden-shot
  diff to the PR. A phase is not done until the intended goldens flip to PASS *and no
  previously passing golden regresses*.
- **The agent touches only files named in the current phase's epic.**
- **Tuning constants get flagged in comments as playtest targets**, not shipped as final.
- Each phase gets its own epic doc with exact file paths and line numbers before build.

## Explicitly out of scope

- **Putting.** Putts return early from `launch_velocity()` before any of this code runs, so
  they are structurally insulated. Feels good, don't touch it.
- **Tempo gesture and grading** (`tempo_gesture.gd`, `tempo_grade.gd`). The delivery layer
  is fine. We are fixing what happens *after* the swing is graded.
- **A real impact model** (smash factor, gear effect, spin loft). Over-engineering for a 2D
  top-down game. The guide that prompted this work recommends it; we are declining that part.
- **Literal TrackMan matching.** We have no ball speed in mph and no spin rate in rpm, so we
  cannot match launch-monitor inputs. We match *derived* targets instead: carry, apex,
  hang time, landing angle, roll-out, and club gapping.
- **Full wedge bag expansion.** Still deferred.

---

## Phases

### Phase 0 — Harness and observability
*No gameplay change. Nothing else ships before this.*

Land `harness.py` in the repo (suggest `tools/`) as the regression suite, and make height
readable during play so Phases 1–2 can actually be playtested.

- Harness in repo with source line references in the header so it can be kept in sync
- Golden shots encode **real-golf targets**, not current behaviour — the current 2/12 pass
  rate *is* the backlog, expressed as a test
- Debug panel already prints apex (`debug_controls.gd:240`); add a side-elevation trajectory
  readout or overlay so apex is legible without reading a number

**Acceptance:** harness runs clean from a fresh checkout; a playtester can state the apex of
their last shot without opening a spreadsheet.
**Risk:** none.

---

### Phase 1 — Hang time and apex from one source
*The big one. Highest leverage change in the codebase.*

Replace the invented `air_time` lerp and the `(28.0 + speed × 0.02) × loft` apex with a
single consistent relationship: hang time comes from club and power, apex falls out of hang
time (`apex = g × t² / 8`), and speed falls out of carry and hang time. One quantity, one
owner, internally consistent.

Rough calibration to sanity-check during the epic (not final values):

| Club | Hang t | Apex px | Apex yd | Speed |
|---|---|---|---|---|
| Driver | 1.10 | 68 | 30 | 511 |
| 7-Iron | 1.18 | 78 | 35 | 328 |
| PW | 1.15 | 74 | 33 | 205 |
| SW 3-yd chip | 0.28 | 4 | 2 | 20 |

**Acceptance:** apex goldens for Driver / 7i / PW / SW pitches / SW chips all PASS; hang time
flat-to-slightly-falling across the bag; chip apex below full-swing apex for every club.
**Dependents this breaks:** tree clearance (everything becomes trivially clearable), aim-cone
preview, camera framing, `estimate_height_peak()` UI estimates, Club Coach history.
**Playtest focus:** does the ball *look* right in the air, and does the camera still hold it?

**Shipped (PR #45):** verified on device; all deltas under 1.5%; `GRAVITY_PX` 535 confirmed by playtest; no calibration changes.

---

### Phase 2 — Canopy and tree rebalance
*Restores challenge immediately after Phase 1 removes it. Ship close behind Phase 1.*

With real apex numbers, re-derive canopy heights so trees are a genuine but solvable
problem, and confirm the punch shot ducks under a short canopy while a full mid-iron clears
a pine.

**Acceptance:** short/pine/tall canopy heights re-derived against the Phase 1 apex table;
punch clears nothing tall but ducks reliably; at least one club in the bag can clear each
tree type; `Driver > pine` and `7i > pine` goldens PASS.
**Playtest focus:** are trees a decision again rather than a coin flip?

---

### Phase 3 — Carry and roll split
Fix `air_distance_fraction()`. Current values model every club as a links bounce — driver
carries 177 and rolls 83. Move to real ratios and fold in the chip/pitch roll retune that
was queued separately in the short-game roadmap.

**Acceptance:** carry goldens for Driver and 7-iron PASS; roll-out is surface-sensitive and
reads as release rather than a skid; chip roll ratio lands in the retuned window.
**Playtest focus:** does a driver on firm fairway release the way it should, and does a chip
finally check-and-run instead of stopping dead?

---

### Phase 4 — One owner for distance
*Invisible refactor. No intended behaviour change.*

Collapse the five scattered distance multipliers (`lie_multiplier`, `contact_multiplier`,
the mash tax, the `dist_mul` force tax, and the `path_error` term buried inside it) into a
single `resolve_distance()`. Nothing outside that function may touch total distance.

**Acceptance:** harness output byte-identical before and after. This is a pure consolidation;
any behaviour delta is a bug in the refactor.
**Why it matters:** without this, Phase 5 has five places to go wrong instead of one.

---

### Phase 5 — Speed as an input; delete the disagreement
Flip the last inversion: launch speed comes from club and power, and carry falls out of it
rather than the reverse. Then remove the double flight termination (`t >= 1.0` **or**
`along >= air_limit`) and the hard roll distance clamp, because they stop being necessary
once plan and simulation can no longer disagree.

**Acceptance:** flight ends for exactly one reason; roll stops from friction, not a clamp;
spin that bends the ball costs distance honestly rather than being compensated for; the
low-speed sidespin shortfall in short pitches resolves without a special case.
**Playtest focus:** the "plan says 3 yards, ball went sideways" class of bug should be gone.

---

### Phase 6 — Retire the band-aids
Remove `short_shot_line_scale()`, the flight reverse-guard, the `remain < 40` braking hack,
and the `spin_scale` speed clamp — one at a time, confirming with the harness that each was
only ever compensating for a root cause now fixed.

**Acceptance:** each removal is a separate commit with a harness diff showing no regression.
If one *can't* come out, that is a real finding and gets documented rather than reverted
silently.

---

### Phase 7 — Feel pass and history reset
Only after the model is trustworthy. Focused playtesting for forgiveness and feel, plus a
Club Coach history reset — per-club tendency data collected before Phase 1 describes a game
that no longer exists.

**Acceptance:** gapping feels right across the bag; Club Coach advice matches current
behaviour; `decisions.md` updated with the new model and its calibration targets.

---

## Sequencing and playability

Playability dips between Phase 1 and Phase 2 — Phase 1 makes every ball fly noticeably
higher and further, which trivialises trees until Phase 2 restores them. That window is
real and short. Keep Phases 1 and 2 in consecutive sessions rather than spreading them.

Phases 4–6 are invisible-to-improving. Phase 3 is visible and should feel like an
improvement immediately.

## Relationship to existing work

- **short-game-roadmap.md Phase 1** (shot-type picker, club eligibility, landing/rollout
  visualisation) is UI and constants — safe to ship on its own track at any time.
- **short-game-roadmap.md Phase 2** (chip roll-ratio retune) is `air_distance_fraction`,
  which this plan's Phase 3 rewrites. **Fold it into Phase 3 and delete it from the
  short-game roadmap** rather than tuning numbers this work invalidates.
- **short-game-roadmap.md Phases 3–5** (distance/coaching desync, ghost-guide familiarity,
  flop shot) should wait for Phase 5 here. The desync is a symptom of plan-vs-simulation
  disagreement and may resolve on its own.
- **correction-swipe-sign-convention.md** — the double-applied spin curvature it documents is
  addressed structurally by Phase 5. Re-verify the sign convention after that lands rather
  than fixing the constants now.
- **Apex/Canopy Rebalance epic** is superseded by Phase 2 here.
- **Wind flag HUD, scorecard, haptics, water hazards** are independent of the flight model
  and can ship in parallel on their own track.

## Open questions for Matt

1. Is `tools/` the right home for the harness, or does it belong outside the Godot project?
2. Does the Phase 1 hang-time table feel right for a mobile game's pacing, or does a 1.1s
   driver flight read as slow on a phone?
3. Should Phase 2 raise apex-to-canopy headroom generally, or keep tall trees as a genuine
   "no club in the bag clears this, punch out" situation?

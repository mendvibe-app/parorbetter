# Swing Input Rework — Roadmap

**Status:** Phase 1 shipped on main (mixed window open). Phase 2 in progress — close the window.
**Owner:** Matt (design/diagnosis) → coding agent (implementation, one phase per PR)
**Companion to:** `design-effort-based-swing.md` (the settled mechanic) and
`flight-model-rebuild-roadmap.md` (a parallel, mostly-independent track — see *Sequencing*)

---

## The decision, restated

Backswing amplitude (`backswing_len`) is captured every swing and currently discarded except
as a balance-penalty floor check. Tempo ratio is the only graded signal. This rebuild makes
amplitude the real power input and keeps ratio as the real quality input — the split every
comparable golf game already converged on (PGA Tour 2K25, Golden Tee, Golf Clash, WGT), and
the split Tour Tempo describes in real golf (backswing length varies with intended power,
ratio holds constant across effort levels).

Three product decisions already made, non-negotiable inputs to every phase below:

1. **Overswing is visible and deliberate, with a cost.** The player sees the target amplitude
   and chooses to exceed it.
2. **Every shot type moves together.** No mixed state where some shot types are effort-based
   and others are still aim-solved.
3. **Flat replacement.** No mode, no toggle, no legacy behavior.

---

## Why this is smaller than it first looks

`resolve_distance()` (Phase 4 of the flight rebuild) already owns total distance and takes
`power` as a plain input. It does not care where `power` comes from. **This rework changes
who produces `power`, not what happens to it.** The call sites that currently solve power
from aim distance change to read it from swing amplitude instead; `resolve_distance`,
`launch_velocity`, `apex_for`, and `hang_time` are untouched.

**Putting is already most of the way there.** `PuttStroke.power_from_frac()` makes amplitude
the primary power signal today, with tempo as a modifier layered on top — exactly the target
shape. Putting likely needs an alignment pass, not a rebuild.

That leaves the real work concentrated in: full swing (currently 100% aim-solved), the four
non-punch shot types (pitch/chip/flop/punch, currently aim-solved with per-type carry
fractions), the aim system (currently sets both direction and, via `retarget_bearing`,
distance), and the UI (currently shows a tempo ghost; needs an amplitude target too).

---

## Guardrails

Same discipline as the flight rebuild, restated because this is the second major track and
the habit needs to hold across both:

- **One phase = one PR = one playtest pass.**
- **Every phase gets a build spec before code**, with exact file paths and line numbers.
- **Tuning constants are playtest targets**, flagged in comments.
- **Report line-number drift and pushback** rather than silently working around either.

---

## Sequencing against the flight rebuild

These two tracks touch overlapping code (`force_factor`, `POWER_POCKET_HI/LO`,
`recommended_power`) but for different reasons — the flight rebuild is making the physics
honest about a *given* power; this rework is changing how power gets *decided*. They are not
strictly ordered, but:

**Recommendation: finish flight Phase 5 first**, then run this track. Phase 5 deletes the
plan-vs-simulation disagreement (the double flight termination, the roll clamp, the
band-aids). Some of what Phase 5 removes was compensating for aim-solved power not matching
delivered power — once amplitude *is* the delivered power, "plan vs actual" changes character
(it becomes "did the player hit their target amplitude," not "did the physics lie"). Doing
Phase 5 first means this rework calibrates against a flight model that no longer has known
physics disagreements baked in, which makes the eventual feel-tuning cleaner to reason about.

This is a recommendation, not a hard dependency — flag if you'd rather start this track now
instead.

---

## Phases

### Phase 0 — Instrumentation
*No gameplay change.* **Shipped** (`feature/swing-input-instrumentation-p0` → main).

Expose the amplitude/power correlation in the debug panel the way flight got a sparkline.
Build a `*_check.py`-style harness for the amplitude→power mapping so it can be tuned and
regression-tested offline, the same discipline as the flight harness.

**Acceptance:** debug panel shows live `backswing_len` alongside current (still aim-solved)
power, so the gap between them is visible before anything changes.

**Device confirm:** instrumentation accurate for both families — TempoGrade (full / pitch /
flop / punch) shows BS len/frac vs commit/true/rolled; PuttStroke (putt / chip) shows
`actual_frac` vs `target_frac` alongside the same power trio. Harness:
`scripts/shot/amplitude_power_check.py`.

### Phase 1 — Core mapping, full swing only
*The load-bearing phase.* **Shipped** (`feature/amplitude-power-full` → main).

Full swing now reads power from backswing amplitude (pad-height, `LEN_FULL=0.62` derived from
existing lane hints); pitch/chip/flop/punch/putt remain aim-solved (chip/putt already
amplitude-primary via `PuttStroke`). **Known mixed state, accepted deliberately** — UI
hints signal the difference (full = pull length; others = aim distance). Closing this
window is the priority for Phase 2.

On-pad target + pocket (`POWER_POCKET_HI`) marks; `true_power` from amplitude so
`force_factor` mash tax fires on overswing (device-confirmed: 239.2 → 215.1 yd at full mash).

### Phase 2 — Extend to pitch, chip, flop
Each already has its own lane geometry and carry-fraction model. Give each its own
amplitude→power mapping in the same pattern as Phase 1, reusing the per-type lane
infrastructure rather than inventing a second system.

### Phase 3 — Extend to punch
Punch's lane was just fixed to match pitch's geometry. Same amplitude→power treatment,
building on that work rather than redoing it.

### Phase 4 — Putting alignment
Audit `PuttStroke` against the now-unified model. Likely small: putting is already
amplitude-primary. Confirm the target-amplitude visualization and overswing-cost language
match the rest of the game rather than rebuilding the mechanic.

### Phase 5 — Retire the aim-solve path
Once every shot type reads power from amplitude, `recommended_power()` and
`solve_committed_power()` stop being authoritative. They likely still have a role — a
"recommended club and swing size for this distance" advisory, shown as a coaching hint rather
than a hard input — but that is a repurposing, not a deletion. Confirm Club Coach, dispersion
data, and the debug panel all reflect amplitude-sourced power rather than stale aim-solved
numbers.

### Phase 6 — Feel pass
Only after every shot type is on the new model. Tune amplitude sensitivity per club, the
shape of the overswing cost curve, and whether "the fine line of keeping tempo while swinging
harder" — the thing that started this whole rework — actually feels like that line in play.
This is where the qualitative goal gets checked against the qualitative complaint that
prompted it.

---

## Interim state between phases 1–4

**Full swing on the new model while pitch/chip/flop/punch are still aim-solved is a real
mixed state**, and decision 2 says the *shipped* game should never present that. Two ways to
reconcile phased delivery with that constraint — **flag your preference before Phase 1
starts:**

- **(a)** Build and merge phases 1–4 on a branch or behind a flag, playtesting each
  individually, but do not consider the track "live" until all four land together.
- **(b)** Accept a short window where the live game is genuinely mixed, on the reasoning that
  it's better to catch problems on one shot type at a time (the same reasoning that made
  punch's isolated rollout valuable) even though the end state must be uniform.

This doc defaults to (a) — phased *build*, unified *ship* — but it's worth confirming, since
it changes how "acceptance" reads for phases 1–3 individually.

---

## Open items carried from the design doc

- Whether `recommended_power`'s post-rework role is advisory-only or removed entirely
  (Phase 5 question, not decided yet).
- Exact shape of the amplitude→power curve per club — linear is the starting assumption,
  Phase 1's harness should confirm or correct it against how the pad actually feels.

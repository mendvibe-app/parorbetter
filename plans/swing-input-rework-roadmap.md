# Swing Input Rework — Roadmap

**Status:** COMPLETE (code). Phases 0–6 shipped. Amplitude power across all shot types;
aim-solve kept as advisory/preview. Device feel checklist closed as deferred — reopen if
free play finds issues.
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
**Shipped** (`feature/amplitude-power-short` → main). Pitch/flop use the same pad-H linear map as
full (`lane_pad_len` 0.50, `bs_floor` 0.10). Chip stays on `PuttStroke.power_from_frac` (already
amplitude-primary) with pull-length hints + scored pace marker. Punch remained aim-solved
until Phase 3.

### Phase 3 — Extend to punch
**Shipped** (`feature/amplitude-power-punch` → main). Punch joins `uses_amplitude_power`;
markers draw from `full_show_markers` only (single source of truth); hints say pull length =
power. Overswing tax measured at −14.8 yd on 7i (147.2 → 132.4). Full/pitch/flop/punch now
share one amplitude-driven power model with real overswing cost and correct on-screen
signaling — **full-swing-family mixed window closed**. Remaining deliberate split: chip/putt
on PuttStroke (Phase 4).

### Phase 4 — Chip/putt alignment
**Shipped** (`feature/chip-putt-alignment` → main). Investigation overturned the original
framing twice (neither “smash-long as-is” nor “import mash tax” was correct) and found a
genuine non-monotonic distance bug at the chip GOOD→THIN boundary instead — fixed by
keeping the THIN label but dropping its distance tax for overpull specifically, since real
chip mishits go long from bad contact, not short from an energy penalty. FAT underpull tax
and putt’s Green `contact_mul = 1.0` exclusion kept. Mishit-risk pad marks (rose ticks at
`abs_n = 1.15`) added for chip/putt, distinct from full-family’s pocket/mash marker.
**Logged, not fixed:** pre-existing PERFECT chip +6% contact bonus.

### Phase 5 — Retire the aim-solve path
*Shipped as investigation + a targeted fix, not a retirement*
(`feature/aim-solve-reconciliation` → main).

All seven aim-solve call sites classified — advisory target and legitimate preview, both
confirmed correct and kept. One real bug found: pitch/flop preview locked to the pin while
the amplitude floor (`POWER_POCKET_LO`) meant a correctly-executed pull always overshot it —
fixed by flooring the preview to match, verified against a tick-hit outcome at three club/pin
combinations. Club Coach confirmed already reading only actual outcomes, no changes needed.

Original framing (kept for history): once every shot type reads power from amplitude,
`recommended_power()` and `solve_committed_power()` stop being authoritative. They still
have a role — a "recommended club and swing size for this distance" advisory — but that is
a repurposing, not a deletion.

### Phase 6 — Feel pass
**Shipped (code/docs close).** Phases 0–5 already put every shot type on amplitude power;
no further constant retune in this close-out. Linear amplitude→power remains the starting
map; overswing mash tax and per-club curves stay playtest knobs if feel fails.

**Device feel (playtest, not a code gate):**
- Full / pitch / flop / punch: target mark vs pocket, deliberate overswing cost readable
- Chip / putt: pull-length still owns pace; mishit marks clear
- Logged not fixed: PERFECT chip still +6% via `contact_multiplier` — **fixed**
  (`chip-distance-real-golf` Phase 3)
- Does “harder swing + hold tempo” feel like the intended fine line?

**Acceptance (met for code):** track closed on paper; feel = Matt device checklist.

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

- **Phase 5:** `recommended_power` / `solve_committed_power` kept as advisory target +
  aim preview. Not removed.
- Exact shape of the amplitude→power curve per club — linear is the starting assumption,
  Phase 1's harness should confirm or correct it against how the pad actually feels.
- **Logged (Phase 4):** PERFECT chip +6% — **fixed** in `chip-distance-real-golf.md` Phase 3.

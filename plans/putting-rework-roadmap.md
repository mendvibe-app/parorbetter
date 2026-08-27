# Putting Rework — Roadmap

**Status:** Phase 0 prototype in build (`GameState.debug_putt_line_aim` / F1). Spec:
`plans/putting-phase0-line-interaction.md`. Phases 1–5 not started.
**Owner:** Matt (design/diagnosis) → coding agent (implementation, one phase per PR)
**Origin:** true-scale putt zoom investigation surfaced that only 1 of the 3 real putting
fundamentals (power) is currently a player decision — line is hardcoded straight-at-cup,
contact is computed but multiplier-neutered. Camera/visibility work was blocked on this
being settled first.

---

## The decision, restated

Real putting (confirmed against coaching sources, not assumed) breaks into three player
skills: **line** (read the green, choose where to start the ball), **speed/power** (pace to
the hole, slope-adjusted), and **contact** (solid strike — mishits go offline *and* short/long
in reality, not just short/long).

Audit of current code against those three:

| Pillar | Current state |
|---|---|
| Power | Real player input — the swing-gesture alley. Slope-aware already. |
| Contact | Graded (PERFECT/GOOD/THIN/FAT) but `contact_mul` hardcoded to `1.0` for `lie == "Green"` — the grade has zero effect on outcome. |
| Line | Not a player decision. `AimControl.default_aim_target()` returns `cup_pos` directly for any green lie — every putt aims dead straight at the hole regardless of break. |

**Decision: line becomes a real player input.** This is the fundamental every coaching
source treats as primary, and it's the one currently missing entirely. Contact gets
activated to complete the loop (a mishit should threaten the line you set, not just the
pace). Camera work (read-view vs. execute-view split, flag visibility, screen real estate
reclaim) is downstream of line existing — you can't design a read view around an aim
interaction that doesn't exist yet.

---

## Why this is bigger than the camera work that started it

Every phase of the true-scale investigation (Phase 1 geometry, Phase 2 camera, the green
art recon) was tuning an existing system. This is a new mechanic — nothing else in the game
lets a player set an aim point that intentionally diverges from the target, then has physics
curve it back. Getting the interaction wrong on a phone touchscreen (dragging a 3-inch putt's
line vs. a 40-foot lag putt's line are not the same gesture problem) costs a full phase if we
skip straight to a build spec. Phase 0 exists to not skip that.

---

## Guardrails

Same discipline as the flight and swing-input rebuilds:

- **One phase = one PR = one playtest pass.**
- **Every phase gets a build spec before code**, exact file paths and line numbers.
- **Tuning constants are playtest targets**, flagged in comments.
- **Do not let camera phases (3–4) start before line (phase 2) is playtested and stable** —
  designing a read-view around an interaction that's still changing wastes the camera work,
  the same lesson as "don't tune camera before geometry is settled."

---

## Phases

### Phase 0 — Aim/line interaction design (no production code)

Decide the actual touch interaction for setting a putt's starting line before building it
for real. Candidates to throw away or keep: drag an aim point on the green (extend the
existing full-shot aim-cone system to `lie == "Green"`?); tap-to-place a start point; a
angle-adjust gesture layered onto the existing power alley. Must work at both ends of the
range — a 3 ft putt (tiny adjustment, easy to overshoot with a drag) and a 40 ft putt
(needs a coarser, more forgiving control). Output: a locked interaction spec (sketch/prototype
+ written description), not shipped code.

**Acceptance:** Matt has played or seen a throwaway prototype of the interaction at both a
short and a long putt distance and signed off before Phase 1 starts.

### Phase 1 — Contact comes alive for putts

Independent of Phase 0/2 — can ship first as a standalone, low-risk win. Remove the
`contact_mul = 1.0 if lie == "Green"` override in `PuttStroke.grade()`. Tune FAT/THIN
penalties specifically for putt-scale strokes — reusing full-swing contact tax values would
almost certainly be too harsh for a stroke this short; needs its own real-golf-grounded
curve, not a copy-paste.

**Acceptance:** a THIN/FAT-graded putt visibly under- or over-runs relative to an identical
PERFECT-graded putt at the same input power. `putt_pace_check.py` (or a new contact-specific
harness) covers the new curve.

### Phase 2 — Line becomes a real player input

The core mechanic. Build the Phase 0 interaction for real. `AimControl.default_aim_target()`
no longer hardcodes `cup_pos` for green lie — player sets a start line, physics launches the
ball along it, slope/break curves it from there same as today. Contact (Phase 1) should now
also threaten line accuracy on a mishit (push/pull), not just pace — real putting's mishits
go offline, not just short.

**Acceptance:** two identical-power putts with different chosen start lines finish in
different places on a sloped green; a mishit visibly pulls/pushes the starting direction.

### Phase 3 — Read-phase camera + flag visibility

Depends on Phase 2 shipping and being stable. Wide view during the new aim/line step:
`green_book` slope overlay visible (already exists), pin flag visible (move the hide
trigger from "on green" to "committed to address," not "on green" outright — flag hides only
once the player locks in their line and moves to execute).

**Acceptance:** flag is visible while setting a line on the green, hides once address is
committed; green_book and the new aim control are both usable in the same wide frame.

### Phase 4 — Execute-phase camera + screen reclaim

Depends on Phase 3's phase boundary existing. Once line is committed, cut to the tight
true-scale camera (Phase 1/2 of the original true-scale work) — now scoped to one job only
(pace execution), not aim + context simultaneously. Fold in the swing-panel real-estate
reclaim identified earlier (bottom panel currently ~47% of screen height) since it matters
most exactly here, where the green view needs to be as large as possible.

**Acceptance:** visible transition from read view to execute view on committing a line;
execute view gives measurably more screen height to the green than today's single-camera
approach.

### Phase 5 — Revisit legibility polish (parked until 1–4 ship)

Short-putt glow/halo aid and the green-art resolution bump (from the earlier recon) get
re-evaluated here, not before. Both may be less urgent — or need different specs — once
players are spending most of their time in a wide read view and only briefly in a tight
execute view, versus the single always-tight view they fight today.

---

## Explicitly not doing

- Not rebuilding this as a 3D/perspective camera — genre-level insight from the mobile golf
  game research, but the wrong-sized fix for this problem.
- Not shrinking green sizes to eliminate long putts — conflicts with the USGA-grounded
  design principle everything else on this project is anchored to.
- Not drawing the ball/hole larger than true scale as a shortcut — last-resort only, not in
  scope here now that line/contact give the camera work a smaller, better-defined job.

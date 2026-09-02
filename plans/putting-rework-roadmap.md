# Putting Rework — Roadmap

**Status:** Line + contact signed off. Phase 3 read camera shipped. Phase 4
execute panel in build (playtest). Pickup: `plans/HANDOFF-putting-true-scale.md`.
Board: `plans/README.md`.
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
| Contact | Green curve in `resolve_distance`: THIN 1.06 / FAT 0.90 / MISS 0.78 / PERFECT 1.00. Mishit line floor `PUTT_CONTACT_LINE_FLOOR`. Shipped. |
| Line | Player input. Bearing drag, distance locked to cup (`PUTT_LINE_*`). Starts on cup line (`default_aim_target` → `cup_pos`); drag aims offline. |

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
- **Phase 4 640 reverted.** **Do not start Phase 5 polish until 900 panel is playtested** (`putt-panel-restore-900.md`).

---

## Phases

### Phase 0 — Aim/line interaction design — SHIPPED

Locked candidate: bearing drag, distance locked to cup. Promoted off F1
2026-08-27. Spec: `plans/putting-phase0-line-interaction.md`.

### Phase 1 — Contact comes alive for putts — SHIPPED

Spec: `plans/putting-phase1-contact.md`. Playtested 2026-08-27 (FAT dies, THIN
runs, mishit line ~5 in @ 6 ft / 7 in @ 8 ft).

### Phase 2 — Line becomes a real player input — DEFAULT SHIPPED

Line aim is the only putt aim path (`_apply_aim_world`). Mishit line floor
ships in Phase 1 (`PUTT_CONTACT_LINE_FLOOR`).

### Phase 3 — Read-phase camera + flag visibility — SHIPPED

Spec: `plans/putting-phase3-read-camera.md`. Book zoom + flag during aim; flag
out and book closed on Confirm. Was already in tree; contract locked in
`green_book_check.py`.

### Phase 4 — Execute-phase camera + screen reclaim — REVERTED

640 failed pace playtest. All shot types use `SHOT_PANEL_H` 900 again.
Spec: `plans/putt-panel-restore-900.md`.

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
- Not retuning green slope / break in this track — parked since true-scale Phase 1. Pickup:
  `plans/green-slope-align-roadmap.md` (field + gravity; includes chip/pitch/flop on-green roll).

# Epic: Tree Punch-Out ("Under") — Deliberate Low Shot Type

## Problem
Being in Trees today just means "worse club choice, less power, tighter
timing" — it's a penalty, not a deliberate low-shot option. There's no way
to intentionally flight a shot low to duck under branches, the way a real
player takes extra club and swings low/flat on purpose.

## Current state (confirmed in code)

- `scripts/ball/ball_physics.gd` `clubs_for_lie()` (lines 148–162) already
  removes Driver/Woods when `lie == "Trees"` — irons/hybrids/wedges only.
- `lie_multiplier("Trees")` = **0.58** (lines 275–276) — shortens carry.
- `lie_timing_scale("Trees")` = **0.62** (lines 298–299) — tightens the
  swing timing window.
- `shot_need_yards()` for Trees = `remaining_yd * 1.35` (lines 199–201) —
  asks for more club to compensate.
- None of this is a *shot type* — it's a blanket penalty applied to
  whatever club/swing you pick. There's no toggle for "hit it low on
  purpose."

## Proposed change

Add an explicit **Punch** shot option, selectable when in Trees lie (and
possibly anywhere, for players who want a stinger-style shot):

- Meaningfully lower the fake `_height` apex vs. a standard shot with the
  same club (real punch = flatter ball flight).
- Trade-off: more roll, less stopping power, less shot-shaping control —
  matches how a real punch shot behaves (you give up spin/control for
  trajectory).
- Depends on **Epic: Tree Apex Carry** for anything to actually duck
  *under* — without that epic, Punch is just a flatter-flying normal shot
  with no mechanical benefit near trees. The shot-type/UI work here can
  still be built in parallel, but the "why would I use this" payoff needs
  the apex-carry height check to exist.

## Acceptance criteria

- Player can select Punch from Trees lie via a clear UI toggle (not buried
  in club select).
- Resulting `_height` apex is measurably lower than a standard shot with
  the same club and same power.
- Distance behavior shifts appropriately — less carry, more roll, not just
  a flat distance cut.
- Existing `clubs_for_lie()` Trees restrictions (no Driver/Woods) still
  apply on top of Punch.

## Out of scope

- Apex/tree-height comparison itself (Epic: Tree Apex Carry).
- Fade/draw shaping (Epic: Shot Shape from Swing Path).

## Notes / provisional values

- Apex reduction amount and roll/carry trade-off ratio are playtest
  targets — start conservative, tune from there.
- Open question to confirm before implementation: is Punch Trees-only, or
  a general option available on any lie (real players punch out of wind
  too)? Recommend starting Trees-only to keep scope tight, expand later if
  it plays well.

## Playtest order

1. Build/confirm this only after Tree Apex Carry lands — otherwise there's
   nothing to verify the payoff against.
2. Punch shot under a tight tree gap that a standard-height shot would
   clip — confirm it gets through.
3. Compare total distance/roll of Punch vs. standard shot, same club, same
   power — confirm the trade-off reads correctly.

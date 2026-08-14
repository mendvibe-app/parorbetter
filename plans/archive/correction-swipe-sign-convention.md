# Correction addendum — verify swipe sign convention before finishing

## Status: CLOSED (playtest deferred)

**Closed 2026-08-14** — open device QA parked so the board is clean. Reopen this file
(or a new correction) after free play if draw/fade sign feels wrong.

Direction rework is shipped (`02facf3`). Original note: do not assume the current sign
convention is correct — it has not been physically verified and may be backwards.

## The issue

`shot_result.gd` documents `intended_shape` as "draw negative, fade positive."
`tempo_gesture.gd`'s `_max_lateral` (lines ~650–654) is a raw geometric
perpendicular-offset reading of the swipe gesture — its sign was **never
explicitly tied to in-to-out vs. out-to-in swing path**, it was just wired
through as "positive lateral → positive shape" in the original shape epic
without verifying against real ball-flight physics.

Real golf (verified via research): an **in-to-out** path produces a
**draw/hook** (curves left for a right-handed golfer — should be **negative**
in this game's convention). An **out-to-in** path produces a **fade/slice**
(curves right — should be **positive**).

**Open question that must be resolved before shipping:** when a player
swipes right on the pad, does that read as "I released the club out to the
right" (in-to-out → should map to negative/draw) or "I cut across to the
right" (out-to-in → should map to positive/fade)? The code doesn't currently
answer this — it just picked positive-in/positive-out and never checked it
against physics or player intuition.

## What to do

1. **Before finalizing**, trace `_max_lateral`'s sign back to an actual
   physical gesture: have someone swipe deliberately in-to-out (finger drifts
   toward the follow-through side, right-handed feel) and log the resulting
   `max_lateral` sign. Confirm which physical motion produces positive vs.
   negative.
2. **Set the final mapping so it matches real ball flight law**, not
   whichever sign happened to fall out of the geometry:
   - in-to-out swipe → **negative** shape (draw/hook)
   - out-to-in swipe → **positive** shape (fade/slice)
   If step 1 shows the current code has this backwards, flip the sign once,
   in one place (either the `perp` calc in `tempo_gesture.gd` or the
   `swing_shape` assignment in `shot_routine.gd` — pick whichever is closer
   to the raw sensor read, not a downstream consumer, and comment why).
3. **`transition_pull`'s direction is downstream of this same question** —
   don't leave it hardcoded as "always subtract" without re-checking it
   against whatever sign convention step 2 lands on. Rushed/over-the-top
   swings are documented as producing pulls *or* slices depending on face,
   not a guaranteed single direction — so this value should bias toward
   whichever sign this game's convention uses for "out-to-in," not be
   assumed independently.
4. Once resolved, add a one-line comment at the `_max_lateral` declaration
   and at `swing_shape` in `shot_routine.gd` stating the confirmed physical
   mapping in plain language (e.g. "positive = out-to-in swipe = fade/slice,
   confirmed via manual gesture test on [date]") so this doesn't have to be
   re-derived again later.
5. Re-run the Shot 5 regression case (strong swipe, rushed tempo, must not
   flip) against whichever sign convention is confirmed correct — the
   expected sign of the "should stay net positive" acceptance criterion may
   need to flip along with this fix if the convention changes.

Do not proceed to final playtest sign-off on the direction rework until this
is confirmed one way or the other — shipping the wrong convention would teach
players the opposite of the shot shape they're actually swiping for.

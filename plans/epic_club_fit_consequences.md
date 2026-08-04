# Epic: Club-Fit Consequences — Distance Variance + Dispersion Scaling

## Problem
Picking a badly-mismatched club (Driver for a 150-yard shot) currently only
costs you line and spin consistency. Distance always solves to the correct
number on clean contact, and the landing-circle size is a flat lookup by
club category — so a forced Driver shot shows the exact same wide circle
it would show for a proper 250-yard tee shot. Nothing in the game currently
makes "wrong club for the distance" feel as risky as it should.

## Current state (confirmed in code)

- `ball_physics.gd` `force_factor()` (lines 431–439) returns 0–1 based on
  how far outside the 60–92% "sensible swing pocket" (`POWER_POCKET_LO`/
  `POWER_POCKET_HI`, lines 84–85) the solved power sits. This already
  correctly detects a mismatched club/distance combo.
- That `force` value currently only feeds two things (lines 480–484 area):
  `lateral` gets `* force_mul` (up to ~1.9x), `spin` gets `* (1.0 + force *
  0.7)` (up to ~1.7x). **Distance is never touched by `force`.**
  `solve_committed_power()` always targets the exact requested distance
  regardless of how forced the swing is.
- The landing-circle radius comes from `game_state.gd`
  `get_aim_radius_yards()` (lines 321–332), which calls
  `BallPhysics.lateral_spread_range_yards(club_max_yards)`
  (`ball_physics.gd` lines 143–154) — **a flat lookup keyed only to club
  category** (Driver always 40–60yd spread, PW always 10–18yd), blended
  with player form. It has no awareness of `force_factor` at all, so a
  badly forced club and a well-fit club at the same distance show
  identical circle sizes.

## Proposed change

1. **Distance variance from force.** Where `solve_committed_power()` /
   the final velocity calc happens, scale the distance result by some
   function of `force` — a forced swing should be capable of coming up
   notably short or occasionally long, not landing exactly on the solved
   number every time on clean contact. In-pocket swings (force = 0) keep
   today's precision.
2. **Dispersion circle from force, not just club category.** Feed `force`
   (or an estimate of it, computed the same way the clearance preview
   already estimates a shot before swinging) into
   `get_aim_radius_yards()` / `lateral_spread_range_yards()` so the
   landing-circle radius visibly grows for a badly-fit club, on top of
   its category baseline. Driver at 150 yards should look obviously
   riskier than Driver at 250, not identical.

## Acceptance criteria

- Two shots at the same target distance, same tempo/contact quality, one
  with a well-fit club (in-pocket) and one badly forced — the forced one
  shows measurably more distance variance on the same contact quality.
- The pre-shot landing circle for a badly forced club is visibly larger
  than for a well-fit club at the same target distance.
- In-pocket shots (the common case) are unaffected — this only kicks in
  once `force_factor() > 0`.
- Shortest-club-in-bag exception (`is_shortest_available()`) still applies
  — babying the shortest wedge for short game is correct play, not a
  forced club, and should not get penalized.

## Out of scope

- Any change to the apex/height math — that's the separate Apex/Canopy
  Rebalance epic. This one is purely about distance and dispersion.
- Redesigning `force_factor()` itself — reuse it as-is, just wire two new
  consumers onto the existing signal.

## Notes

- This directly addresses "why does any club just go the right distance
  if I swing it well" — the answer becomes "it doesn't, once you're
  outside the pocket," matching how real club mismatch actually degrades
  a shot (distance control suffers, not just line).
- Real golf grounding: taking extra club and swinging easy is legitimate
  technique *inside* a reasonable range — this change should punish
  genuine mismatch (Driver at 150), not the smooth-6-iron-instead-of-
  full-8-iron case, which typically stays inside or near the pocket.

## Playtest order

1. Hit a well-fit club (in-pocket) at a target distance — confirm
   distance/circle behavior matches today.
2. Hit the same target distance with a badly mismatched club (well below
   pocket lo) — confirm both distance variance and circle size increase.
3. Confirm shortest-club short-game shots are unaffected.

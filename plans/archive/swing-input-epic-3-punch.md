# Swing-Input Phase 3 — Punch Amplitude Power

**Track:** swing-input-rework-roadmap.md, Phase 3 of 7
**Branch:** `feature/amplitude-power-punch`, from main after Phase 2
**Prerequisite:** Phases 1–2 merged. `power_from_amplitude`, `amplitude_for_power`, and
`uses_amplitude_power` already exist and are shot-type-parameterized.
**Gameplay change:** punch reads power from pull length instead of aim distance. Every other
system stays exactly as it is — this closes the last gap in the full-swing-family mixed
window.

---

## Why this phase is small

Everything this phase needs already exists, built generically on purpose. From current main:

```gdscript
// ball_physics.gd:128
## TempoGrade-pad types that read power from amplitude (not aim). Punch = Phase 3.
static func uses_amplitude_power(shot_type: String) -> bool:
	return shot_type == "full" or shot_type == "pitch" or shot_type == "flop"
```

The comment names this phase. `power_from_amplitude()` and `amplitude_for_power()` already
take `shot_type` and call `TempoGrade.bs_floor(shot_type)` and `lane_pad_len(shot_type)` —
both of which **already resolve correctly for punch**, because punch's pad geometry was fixed
during the punch-legibility correction, before this track even started:

```gdscript
// tempo_gesture.gd — _uses_short_lane() groups punch with pitch/flop for lane geometry
func _uses_short_lane() -> bool:
	return shot_type == "pitch" or shot_type == "flop" or shot_type == "punch"
```

Punch's address/top hints, and therefore its `lane_pad_len`, are **already identical to
pitch's**. And `bs_floor("punch")` already resolves to `0.10` via the same short-list group
pitch and flop use. So `power_from_amplitude(len, "punch")` will compute correctly the moment
it's called — no new geometry, no new floor, no new lane math.

**What's deliberately separate and must stay separate:** `_is_pitch()` explicitly excludes
punch —

```gdscript
func _is_pitch() -> bool:
	## Punch is NOT included — it uses _uses_short_lane() for path only so VEL_TOP /
	## min-backswing pitch tuning does not silently apply to punch.
	return shot_type == "pitch" or shot_type == "flop"
```

Lane geometry and amplitude-power eligibility are two different gates on purpose. This phase
touches only the second one.

---

## The change

One line:

```gdscript
static func uses_amplitude_power(shot_type: String) -> bool:
	return shot_type == "full" or shot_type == "pitch" or shot_type == "flop" or shot_type == "punch"
```

Everything downstream — `shot_routine.gd:512`'s `amp_power`/`power` wiring, `true_power`
assignment, the pocket-line and target markers, `force_factor` mash tax eligibility — is
already generic over `shot_type` and requires no changes. If any of it turns out **not** to be
generic when you actually read it, report that as a finding; the expectation going in is that
it is.

---

## The two checks that mattered for Phases 1 and 2, applied here

Same two failure modes as before — confirm explicitly, don't assume they transfer for free
just because the plumbing is shared:

1. **`true_power` for punch must come from `amp_power` (pre-`power_mul`), the same as
   full/pitch/flop**, so overswinging a punch genuinely taxes distance via `force_factor`
   rather than looking like it does. Trace the exact line, don't infer from Phase 1/2's
   pattern holding — confirm it holds for the `punch` string specifically.
2. **Confirm nothing that should stay untouched moves.** Putt and chip must remain
   bit-identical — they're not part of `uses_amplitude_power`'s string set and never will be
   in this phase. Full, pitch, and flop must also remain bit-identical to their Phase 1/2
   behavior — this phase adds a fourth string to an existing list, it does not touch the
   other three.

---

## What this does NOT change

- Punch's tree-clearance mechanics (`PUNCH_UNDER_CANOPY_FRAC`, the duck-under aim logic from
  the punch-legibility correction). Completely separate system, untouched.
- Punch's `APEX_SCALE_PUNCH`. Flight-side, settled, out of scope for the input track entirely.
- Putt or chip. Phase 4.
- Any UI hint copy beyond what's needed to reflect punch now being amplitude-driven — reuse
  the existing hint mechanism from Phase 1/2 (`hint_label` in `shot_routine.gd`'s
  `begin_shot`), just add punch to whichever branch already says "pull length = power."

---

## Interim state after this phase

Full, pitch, flop, and punch all share one power model. Chip and putt remain on
`PuttStroke`'s older, distance-gaining model. That split is now a **deliberate two-family
state**, not an in-progress mixed window — Phase 4 addresses whether chip/putt should move
toward alignment or stay structurally different (the smash-long vs. mash-cost asymmetry
flagged after Phase 2). This phase does not need to wait for that decision.

---

## Acceptance criteria

1. `uses_amplitude_power("punch")` returns `true`. Every other string's return value is
   unchanged.
2. A punch's `true_power` is the pre-`power_mul` amplitude value. Overswinging a punch past
   its pocket line measurably costs distance via `force_factor` — same style of test as
   Phase 1's 24-yard driver measurement, produce the punch equivalent.
3. Full, pitch, flop, chip, and putt all produce bit-identical output to pre-Phase-3, verified
   by rerunning Phase 1 and Phase 2's regression checks, not just asserting they still pass.
4. The tree duck-under mechanic still works correctly for a punch at both a short pull and a
   full pull — confirm amplitude-driven power didn't change how the punch escape height is
   computed (it shouldn't; that's downstream of the same `power` value either way, but verify).
5. Flight goldens unchanged.
6. All `*_check.py` pass, including `amplitude_full_check.py` and `amplitude_short_check.py`
   extended to cover punch, or a new minimal punch-specific check if that's cleaner — agent's
   call, report which.
7. Hint copy reflects punch as amplitude-driven.

---

## Playtest verification order

1. Hit into the trees, toggle punch, pull a short-to-moderate amplitude. Confirm it still
   ducks under the canopy correctly — this is the one place punch's power interacts with a
   system this track hasn't touched before (canopy clearance), so it's worth confirming
   directly rather than trusting the acceptance criteria alone.
2. Pull past the pocket line on a punch. Confirm the distance cost is legible, the same way
   it was for full swing and pitch.
3. Play a hole where punch, pitch, and full swing all come up. Confirm the shot family now
   feels consistent — pull length means the same thing across all of them.
4. Hit a putt and a chip. Confirm nothing changed.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- This phase should be small. If implementing it reveals that the plumbing isn't as generic
  as this document claims, **stop and report** rather than adding new punch-specific branches
  to make it fit — that would mean an earlier phase's "already generic" claim was wrong, and
  that's worth knowing precisely rather than working around silently.
- Touch `ball_physics.gd` (the one-line change), `shot_routine.gd` only if the hint-copy
  branch needs a punch case added, and whichever check files need extending.

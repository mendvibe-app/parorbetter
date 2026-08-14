# Swing-Input Phase 1 — Core Mapping, Full Swing Only

**Track:** swing-input-rework-roadmap.md, Phase 1 of 7
**Branch:** `feature/amplitude-power-full`, from main after swing-input Phase 0
**Prerequisite:** Phase 0 merged — `backswing_len`/`frac` capture and F1 visibility confirmed
**Gameplay change:** large and intentional. Full-swing distance comes from how far back the
player pulls, not from where they aimed.

---

## What already exists that this reuses

Putt already has the exact mechanism this phase needs — just wired backwards. Today:

```gdscript
// shot_routine.gd:246
tempo_gesture.putt_target_frac = PuttStroke.marker_frac(committed_power)
```

`committed_power` (aim-solved) produces a **target amplitude**, drawn on the pad as a marker
the player aims their stroke at (`tempo_gesture.gd:689`, `tgt_disp := putt_target_frac *
_lane_len()`). The player's actual amplitude then determines rolled power via
`PuttStroke.power_from_frac()`.

**This phase inverts that relationship for full swings, using the same drawn-marker
machinery.** Instead of aim solving power and amplitude just executing it, amplitude solves
power directly, and the aim-implied distance becomes the marker shown as a *suggestion* —
exactly like the putt marker today, but advisory rather than authoritative.

---

## The model

```gdscript
## Full-swing power from backswing amplitude. THE power source for shot_type=="full" —
## aim/committed_power stops being authoritative for full swings after this lands.
## PLAYTEST TARGET curve.
static func power_from_amplitude(frac: float) -> float:
	# frac is backswing_len (pad-height fraction) from tempo_gesture, NOT lane fraction —
	# full swing's lane is fixed at bs_floor=0.18 to ~1.0, matching the existing floor.
	var floor_frac := 0.18   # TempoGrade.bs_floor("full") — same value, don't duplicate literal
	var t := clampf((frac - floor_frac) / (1.0 - floor_frac), 0.0, 1.0)
	return lerpf(POWER_POCKET_LO, 1.0, t)   # 0.60 at floor, 1.0 at full pad length
```

Near-linear off the pad, floored at `POWER_POCKET_LO` (0.60 — already the game's definition
of "the shortest swing that still counts as a real attempt," reused rather than inventing a
second floor) and capped at 1.0 at full pad extension. **Overswinging past 1.0 pad length is
not clamped here** — see *Overswing* below, this is where decision 1 (visible, deliberate
overswing with a cost) becomes real.

### Wiring

`shot_routine.gd:485` currently reads:

```gdscript
var power := clampf(committed_power * float(verdict["power_mul"]), 0.05, 1.0)
```

For `shot_type == "full"`, replace `committed_power` with `power_from_amplitude(sample.backswing_len)`.
Every other shot type is untouched in this phase — per the roadmap's decision 2 (everything
must eventually match), this is Phase 1 of a build sequence, not a shipped mixed state; see
*Interim state* below.

`committed_power` (aim-solved) is **not deleted**. It becomes the input to the target-marker
calculation, mirroring putt exactly:

```gdscript
// New, sibling to the existing putt_target_frac line
tempo_gesture.full_target_frac = amplitude_for_power(committed_power)  // inverse of power_from_amplitude
```

Draw this marker on the full-swing pad the same way `tgt_disp` already draws the putt target
— a suggested pull length for the club and distance the player is aimed at. **This is
coaching, not a gate.** The player can pull short of it, to it, or past it; all three are
valid, with different consequences (short distance, on-target, overswing cost).

---

## Overswing — decision 1 made real

`force_factor()` already taxes `power > POWER_POCKET_HI` (0.92) — the mash penalty from
Phase 4/5. Today nothing makes that threshold visible or reachable through player choice; it
fires as a side effect of aim-solved power occasionally landing above 0.92, invisibly.

After this phase, **overswing is the player pulling back past the target marker's
implied 0.92 point.** Show a second, shorter reference mark on the pad — call it the pocket
line — at the amplitude corresponding to `POWER_POCKET_HI`. Pulling past it is visible,
optional, and costs distance via the existing mash tax. This is the entire mechanic decision
1 asked for, and it requires no new physics — `force_factor` already does the penalty, this
phase just makes triggering it a legible choice instead of an accident.

---

## Interim state — decision 2

Full swing moves in this phase; pitch/chip/flop/punch do not (Phases 2–3). Per the roadmap's
own resolution of this tension: **build phased, ship unified.** Concretely for this phase:

- Land and playtest on `feature/amplitude-power-full`. Do not merge to main until Phase 2
  (short game) is also ready, unless Matt explicitly decides otherwise.
- If Matt wants Phase 1 merged and live before Phase 2 lands (option (b) from the roadmap —
  accept a real mixed window to catch problems early), that overrides this default. State
  which applies before implementation starts.

---

## What this does NOT change

- **Putt and chip.** Already amplitude-primary via `PuttStroke`; untouched.
- **Pitch, flop, punch.** Still aim-solved. Phase 2.
- **`resolve_distance()`, `launch_velocity()`, apex, hang, carry.** All settled by the flight
  rebuild. This phase changes what produces the `power` float; nothing downstream of it moves.
- **Tempo ratio grading.** Contact quality still comes from timing ratio, completely
  independent of amplitude. A full-length pull with rushed timing is still a bad shot.

---

## Open implementation questions — report before choosing silently

1. **Does `frac` for full swing use pad-height (`backswing_len`) or lane-fraction
   (`backswing_frac`)?** Phase 0 exposed both without picking. Putt uses lane-fraction. Full
   swing's lane is effectively the whole pad (`address_hint`/`top_hint` y = 0.30/0.92 today),
   so the two are nearly equivalent for this shot type — confirm they actually are before
   assuming it doesn't matter.
2. **Is `power_from_amplitude`'s curve actually near-linear**, or does the pad's physical feel
   (finger travel vs. perceived effort) argue for an eased curve? Flag if the harness's offline
   testing suggests linear feels wrong once mapped to real pull distances.
3. **Does the overswing pocket-line marker belong on the pad itself, or in a HUD element
   outside it?** Putt's marker precedent is on-pad; recommend following that unless there's a
   concrete reason not to.

---

## Acceptance criteria

1. A short pull produces a short shot; a full pull produces the club's full distance; nothing
   in between is a step function.
2. `power_from_amplitude(bs_floor("full")) == POWER_POCKET_LO` and
   `power_from_amplitude(1.0) == 1.0` — the mapping's endpoints are exact, not approximate.
3. Pulling past the pocket line is visible on the pad before the swing commits, and costs
   distance via the existing (unmodified) `force_factor` mash tax.
4. Tempo ratio grading is unaffected by amplitude — verify a short pull and a full pull with
   identical timing produce identical contact quality.
5. All other shot types produce bit-identical output to before this phase — this touches only
   the `shot_type == "full"` path.
6. Flight goldens unchanged. This phase does not touch anything downstream of `power`.
7. A harness (house `*_check.py` style) verifies the amplitude→power curve and its inverse
   independently of Godot.

---

## Playtest verification order

1. Full pull, on-tempo, driver. Should produce the club's max reachable distance
   (`POWER_POCKET_HI`, not 1.0 — confirm the pocket marker and the mash tax are both legible
   here).
2. Half pull, on-tempo, driver. Should produce roughly half the power-implied distance, not
   half the yardage (power and distance aren't linearly related — confirm this reads sensibly
   rather than confusingly).
3. Deliberately pull past the pocket line. Confirm the cost is visible and the shot result
   explains itself — the player should be able to tell *why* they lost distance.
4. Full pull with rushed tempo. Confirm contact quality still degrades independent of
   amplitude — the two axes must stay genuinely orthogonal.
5. Play several holes. The target feeling, direct from the original complaint: **swinging
   harder for more distance should now work, and should cost something when overdone** — the
   same tension real golf has.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch `scripts/shot/tempo_gesture.gd`, `scripts/shot/shot_routine.gd`,
  `scripts/ball/ball_physics.gd` (add `power_from_amplitude`/inverse only — no other changes),
  plus a new harness file. Report anything else needed.
- Reuse `POWER_POCKET_LO`/`HI` and `bs_floor("full")` rather than introducing parallel
  constants — this phase's whole premise is unifying two systems, not adding a third.
- Answer the three open implementation questions in your plan before writing code.

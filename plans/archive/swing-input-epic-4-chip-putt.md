# Swing-Input Phase 4 — Chip/Putt Alignment

**Track:** swing-input-rework-roadmap.md, Phase 4 of 7
**Branch:** `feature/chip-putt-alignment`, from main
**Gameplay change:** none, unless investigation finds a real gap. This phase is primarily
verification and legibility — grounded in research before any code was proposed.

---

## The question this phase was flagged to answer

After Phase 2, chip/putt's overswing consequence (distance gain via `power_mul = rolled /
committed`, uncapped above 1.0) looked structurally opposite to full/pitch/flop/punch's
(distance loss via `force_factor` mash tax). The open question was whether Phase 4 should
unify them.

**Neither original framing survives grounding.** Two research passes, real golf and
comparable games, both complicate the "just pick one" framing:

### Comparable games: PGA Tour 2K25 runs one unified system, not two

> "Putting in PGA TOUR 2K23 uses similar controls and mechanics to other shots like drives
> but requires less power and aggression."

Every shot type — full swing through putt — is graded on the same Transition/Rhythm/Swing
Path model. **This game already has that shape.** Every shot type pairs an amplitude→power
signal with an independent timing/pace→quality signal (`TempoGrade` ratio for full family,
`PuttStroke`'s pace-band for chip/putt). The architecture was never actually split; only the
overshoot *consequence* looked different.

### Real golf: chip overswing isn't a smooth distance-loss curve OR a clean overshoot

> "A too-long backswing for a short chip will likely result in **deceleration of the club
> into impact**." — real golfers self-correct an oversized backswing by easing off, which is
> itself an accuracy problem, not a smooth speed penalty. When that self-correction fails,
> the well-known result is a **bladed or skulled chip** — a contact-quality disaster that
> sends the ball much too far, not a controlled proportional overshoot.

So the real mechanism is: **overswing on a chip primarily threatens contact quality, and a
contact-quality failure is what actually produces the bad distance outcome** (either too
short from deceleration, or way too long from a blade). That's neither pure "smash long" nor
the full-swing mash tax.

### What the code already does — confirmed by reading it, not assumed

```gdscript
// putt_stroke.gd:143-152 — grade()
if incomplete and abs_n > BAND_GOOD:
	contact = ShotResult.ContactQuality.MISS
elif incomplete:
	contact = ShotResult.ContactQuality.FAT if frac_err < 0.0 else ShotResult.ContactQuality.THIN
elif abs_n <= BAND_PERFECT:
	contact = ShotResult.ContactQuality.PERFECT
elif abs_n <= BAND_GOOD:
	contact = ShotResult.ContactQuality.GOOD
else:
	# Pace error only — short leave / blow past. Hole-out from line+physics, not auto-MISS.
	contact = ShotResult.ContactQuality.FAT if frac_err < 0.0 else ShotResult.ContactQuality.THIN
```

**A large amplitude miss already degrades contact to THIN/FAT**, and for chip specifically
(not putt), `contact_mul` then multiplies the resulting distance
(`putt_stroke.gd:165` comment: *"chip multiplies contact"*). So an overpulled chip already
gets two effects layered: `power_mul` scaling distance up from raw amplitude, and a real
chance of a contact-tier penalty pulling it back down. **This is closer to the real-golf
mechanism than either original framing** — it's just not packaged or signaled the same way
as the full-swing mash tax, and nobody has verified it actually produces sensible outcomes
across the amplitude range.

---

## What this phase actually is

**Not** "import the mash tax into chip." **Not** "leave chip alone, it's fine." Instead:

1. **Verify** the existing THIN/FAT-on-large-miss mechanism produces sensible results across
   realistic overpull magnitudes — nobody has checked this with real numbers.
2. **Confirm** putt's exclusion from `contact_mul` (per the code comment, only chip multiplies
   contact) is intentional and still correct, not leftover asymmetry.
3. **Make it legible.** The player currently has no way to know that overpulling a chip risks
   contact-tier degradation, not just extra distance. Full swing's pocket-line marker makes
   its overswing consequence visible before the swing; chip/putt has nothing equivalent.

---

## Investigation before any code

1. Sweep `abs_n` (amplitude miss) across a realistic range for a chip and quantify: at what
   miss magnitude does contact first degrade to THIN/FAT, and what does that do to final
   distance combined with `power_mul`? Does a bad overpull actually end up short (as real
   deceleration-driven misses do) or still long (as a real bladed shot does) or does the
   current model produce something that matches neither?
2. Check whether `power_mul`'s scaling and `contact_mul`'s penalty can combine into something
   incoherent — e.g., a moderate overpull that's just past the THIN/FAT threshold landing
   *shorter* than a smaller overpull that stayed in GOOD, because the contact penalty
   dominates. That would be a real bug, not a design choice, if found.
3. Confirm putt genuinely should stay outside `contact_mul` — putts don't have the
   blade/skull failure mode a chip has (you can't blade a two-foot putt into the pond), so
   this asymmetry is probably correct, but confirm rather than assume.

**If the sweep in item 1 or 2 finds something incoherent, that's this phase's real fix** —
not a redesign toward the mash tax, a correction to make the existing, better-grounded
mechanism actually behave the way it's supposed to.

---

## Legibility work (do regardless of what the investigation finds)

Add a visible signal, on the chip/putt pad, that overpulling risks more than just extra
distance — sibling to the pocket-line marker full/pitch/flop/punch already have, but
representing "risk of mishit" rather than "mash tax threshold," since that's what's
mechanically true here.

---

## Out of scope

- Any change to `power_mul`'s base formula (`rolled / committed`).
- Importing `force_factor` or `POWER_POCKET_HI` into chip/putt. Confirmed by both research
  passes that this would be modeling the wrong failure mode.
- Full/pitch/flop/punch. Untouched, already shipped.
- Putt's exclusion from `contact_mul` — confirm, don't remove, unless investigation finds it
  genuinely wrong.

---

## Acceptance criteria

1. Investigation items 1–3 reported with real numbers before any code changes.
2. If a genuine incoherence is found (criterion 2 above), it's fixed and the fix is reported
   against specific before/after numbers — not a broad retune.
3. If nothing incoherent is found, no distance-mechanic code changes — this phase closes as
   verification plus legibility only.
4. A visible mishit-risk signal exists on the chip/putt pad.
5. Full/pitch/flop/punch produce bit-identical output — this phase doesn't touch their code
   paths at all.
6. Flight goldens unchanged.
7. All `*_check.py` pass.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- This phase is investigation-first by design — the grounding above already overturned my
  own two prior framings twice. Don't let a third assumption in without checking it against
  real numbers from the actual code.
- If the sweep shows the existing mechanism is already coherent and just needs a UI signal,
  say so plainly — a "nothing was wrong, here's the legibility fix" outcome is a completely
  acceptable result for this phase, not an underwhelming one.

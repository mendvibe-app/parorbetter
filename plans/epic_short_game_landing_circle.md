# Epic: Short-Game Landing Circle Sizing

**Status:** Phase 0 confirmed — see `plans/short-game-landing-circle-phase1.md` (implementing).
**Priority:** Low-risk, independent. Can ship between heavier physics phases. Does NOT block or get blocked by the putting recording fix, pacing epic, or green sizing.
**Type:** UI / feedback legibility, with a probable underlying dispersion-model bug.

---

## 1. The bug

Playtest, Hole 5, Par 3, 123 yds. Ball is just off the green, roughly 20–25 ft from the pin. Club is Lob Wedge, shot type is **Chip**. The aim/landing target circle rendered on screen is visually enormous — it reads as roughly **30+ feet across**, wider than the distance the ball needs to travel.

That is wrong on its face. A chip is the most controlled shot in the bag: short carry, low flight, minimal air time, so there is almost nothing for error to compound through. A competent player picks a landing spot the size of a dinner plate and hits within a couple of feet of it. Showing a 30 ft target on a 20 ft chip tells the player the game has no idea what a chip is.

Suspicion: short-game shot types are inheriting a full-swing dispersion formula, or there is a fixed radius floor that never got a short-game branch. **Confirm this against the code — do not assume it.**

---

## 2. Phase 0 — Investigate and report back (no code)

Read the relevant source and answer these before proposing any change:

1. **Where is the landing/aim circle radius computed?** Likely candidates to start in: `scripts/shot/shot_routine.gd`, `scripts/shot/ball_physics.gd`, `scripts/ui/` (whichever node draws the aim reticle). Give me the exact file and line numbers.
2. **What is the radius actually a function of?** Fixed constant? Fraction of target distance? Club-derived? Contact/tempo-derived? Report the actual formula as written.
3. **Do the four shot types (Full / Chip / Pitch / Flop) branch at all** in that calculation, or do they share one path?
4. **Is there a minimum radius floor or clamp?** If so, what is it in game units, and what does it work out to in feet at current world scale?
5. **Is the drawn circle the same value the physics uses for dispersion,** or is it a display-only approximation that has drifted from the actual outcome model? This matters a lot — if the circle is honest and the *physics* is this wide, this is a much bigger bug than a UI one.
6. **Does the circle represent landing spot only, or landing + expected roll-out?** See §5.

Report findings. Do not proceed to Phase 1 until we've discussed.

---

## 3. Real-golf grounding

The governing principle: **dispersion scales with carry distance, swing length, and air time.** A 15-yard chip and a 125-yard wedge must not share a circle size. Short shots are tight; long shots are wide; high shots are wider than low shots of the same distance.

Rough target radii to sanity-check the model against (these are **playtest starting targets, not final values** — comment them as such in code):

| Shot type | Typical carry | Target circle radius | Why |
|---|---|---|---|
| Chip | 5–20 yds | ~2–4 ft | Minimal air time, putting-like stroke, most controlled shot in the bag |
| Pitch | 20–50 yds | ~5–10 ft | More swing length, more air time, more room for error |
| Flop | 10–30 yds | ~6–12 ft | Short, but highest flight and steepest face — least control per yard |
| Full wedge | 90–130 yds | ~15–25 ft | Full swing dispersion begins here |
| Mid iron | 150–180 yds | scale up from above | Existing model probably fine — verify, don't rewrite |

**Preserve the flop-wider-than-chip relationship.** That is real and it is the whole trade you make for a soft landing. If the current model flattens all short shots to one number, restoring that distinction is half the value of this epic.

Cross-reference how PGA Tour 2K25 and Golf Clash handle short-game reticles — for reference on legibility, not as templates.

---

## 4. Phase 1 — The fix (shape only, pending Phase 0)

Whatever the underlying cause turns out to be, the fix should land as:

- A dispersion value that **scales with carry distance**, not a flat constant.
- An explicit **short-game branch or multiplier** so Chip / Pitch / Flop each get their own coefficient rather than inheriting the full-swing curve.
- Any minimum radius floor re-derived from the chip case, not from the full-swing case.
- Constants commented as playtest targets with the real-golf rationale inline.

One phase, one PR, one playtest. Do not bundle this with any other epic.

---

## 5. Second-order issue — flag, don't fix yet

A chip has two components: **where it lands** and **how far it rolls out.** The current display shows one circle and communicates nothing about roll. Sizing the circle correctly may only fix half the legibility problem — a player aiming a lob wedge chip needs to know the ball lands *here* and finishes *there*.

Report in Phase 0 whether roll-out is modeled for short-game shots at all. Do not build a roll-out indicator in this epic. If it's warranted it becomes its own epic, sequenced after the pacing work (roll friction is already known to be wrong — `60.0` multiplier, correct value ~0.75 — so any roll-out visual built now would be tuned against broken physics).

---

## 6. Do not touch

- `scripts/shot/tempo_gesture.gd`, `tempo_grade.gd` — tempo is not implicated here
- Anything in the pacing epic: `GRAVITY_PX`, `FLIGHT_DURATION_FRAC`, roll friction multiplier
- Green generation / sizing constants
- Camera and zoom values
- Cup capture radii and thresholds
- Club Coach recording paths
- Any file not named in Phase 0 findings

---

## 7. Acceptance criteria

1. A chip from ~20 ft off the green renders a circle that is visibly **smaller than the distance to the pin**, in the 2–4 ft radius range.
2. Chip, Pitch, and Flop from the same lie render **visibly different** circle sizes, in that order of increasing width.
3. Circle size **grows with carry distance** within a shot type — a 40 yd pitch is wider than a 20 yd pitch.
4. Full-swing shots are unchanged from current behavior unless Phase 0 shows the full-swing path is itself the bug.
5. If the circle drives actual dispersion (not display-only), outcomes match the drawn circle — a chip that looks tight lands tight.
6. Screenshot the Hole 5 chip case pre- and post-fix as the regression record.

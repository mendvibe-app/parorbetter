# Short Game System — Roadmap (Aug 2026)

Goal: turn 5 separate conversation threads into a sequence your coding agent can implement one
bounded piece at a time, with a playtest checkpoint between each — not one large handoff.

Reference doc: `shot-type-ground-truth.md` (as-built definitions, already delivered)

---

## Input model — the constraint every phase below has to respect

Two input families exist today. Nothing in this roadmap introduces a third.

- **Stroke-length family** (Putt, Chip): draw-back distance vs. a target fraction. No transition
  timing graded.
- **Tempo-gesture family** (Full, Pitch): timed backswing:downswing ratio (3:1 / 2:1), transition
  timing graded, swipe direction owns shot shape.

**Flop slots into the tempo-gesture family** — it's a real swing with a transition, just with an
open face, tighter tolerance, and harsher miss consequences. It does not need Putt/Chip's
stroke-length model.

---

## Status (branch `feature/shot-type-picker`)
Phases 1–5 implemented in code (2026-08-09). Phase 6 still deferred.
Playtest each phase before treating values as final.

## Phase 1 — Manual shot-type picker + club eligibility gate + landing/rollout visualization
**Unlocks:** player chooses Chip/Pitch/Full (Flop deferred to Phase 4) instead of the game
silently picking by aim distance.
**Touches:** `shot_routine.configure()`, `TempoGrade.shot_type_for()` (becomes a *recommendation*,
not a hard assignment), club select UI, hint label.
**Eligibility gate (current bag):**
| Club | Full | Chip | Pitch |
|---|---|---|---|
| Driver → 6-Iron | ✅ | ❌ | ❌ |
| 7i / 8i / 9i | ✅ | ✅ | ❌ |
| PW | ✅ | ✅ | ✅ |
| Gap/Sand Wedge | ✅ | ✅ | ✅ |
**Recommend logic:** reuse existing hazard/tree-clearance check to suggest Chip (clear path) vs.
Pitch (obstacle in the way); player can always override within what the club allows.

**Landing vs. rollout visualization (folded in — the picker is only useful if the player can see
what they're choosing between):**
- Problem: the aim circle today shows one generic landing radius, with no visual distinction
  between where the ball first touches down (carry) and where it ends up after roll. A player
  can't currently tell "does my carry clear that bunker/rough" from "does my total distance clear
  it" — same circle either way.
- Fix: two distinct markers — first-bounce/landing point, and final rest position after roll —
  connected by a line or fading trail so the gap between them is visually obvious. Should scale
  naturally per shot type (Chip's landing/rest markers sit close together since it's roll-heavy;
  Pitch's sit further apart since it's carry-heavy).
- This directly answers "will I clear the hazard before it rolls out" — the question that
  prompted this addition.
**Explicitly out of scope:** Flop, chip roll-ratio retune, ghost-guide fade fix, wedge bag
expansion.
**Playtest checkpoint:** does the picker feel discoverable? Does the recommendation feel right
often enough to trust? Can players correctly predict, before swinging, whether their carry clears
a hazard versus their total rollout distance?
**Acceptance criteria:**
- Every club shows only its eligible shot types; ineligible types are not selectable.
- A recommended shot type is visibly flagged, and choosing a different eligible type is a single
  tap/action.
- Landing marker and rest marker render as visually distinct points for every shot type, on every
  hole surface (fairway, rough, green, sand).
- No change to Full or Putt behavior, inputs, or visuals.

## Phase 2 — Chip roll-ratio retune
**Problem:** chip's air/roll split currently runs ~42–52% roll; real chipping runs ~67–80% roll.
**Touches:** `BallPhysics.air_distance_fraction()` chip branch only.
**Explicitly out of scope:** the separate chip coaching-text bug below (Phase 3 covers it) — don't
fix both in the same pass, so if something feels wrong after, you know which change caused it.
**Playtest checkpoint:** does chip roll-out read as "long putt with a wedge" now?
**Acceptance criteria:**
- Chip air fraction lands in the ~20–33% carry range (i.e. ~67–80% roll) across PERFECT/GOOD
  contact on at least 3 different lie types.
- Pitch's air fraction is unchanged.
- No change to `PuttStroke` or `TempoGrade` files.

## Phase 3 — Distance/coaching-text desync fix
**Problem:** Chip/Putt's "Target X ft → rolled Y ft" line is computed from a standalone formula,
disconnected from the real simulated ball flight shown in "Plan X yd → Actual Y yd." They can
disagree on the same shot.
**Touches:** `PuttStroke.grade()` target_yd/rolled_yd — needs to read from the same physics result
`ball_physics` already produces, not a parallel formula.
**Also bundle:** the debug-panel desync (Path pulled from `last_shot_metrics`, Shape breakdown
pulled from `last_tempo_metrics` — can go out of sync when tempo grading is skipped). Same root
cause category (two sources of truth for one number), same file family, safe to fix together.
**Playtest checkpoint:** do the two distance numbers ever disagree again across ~50 chip/putt reps?
**Acceptance criteria:**
- "Target → rolled" coaching text and "Plan → Actual" carry text derive from the same underlying
  physics result on every chip/putt shot — zero disagreement across a 50-shot manual test log.
- Debug panel's Path and Shape breakdown always populate from the same shot metrics object; no
  scenario produces a populated Path with a blank Shape section.

## Phase 4 — Ghost-guide per-shot-type familiarity
**Problem:** the tempo ghost-guide overlay fades based on overall player form, not per-shot-type
experience — so an experienced player can be invisible-guided into a shot type they've never
knowingly hit.
**Touches:** `tempo_gesture._guide_alpha()` — fade should key off reps-with-this-shot-type
(Club Coach already tracks something adjacent to this), not global form.
**Playtest checkpoint:** does a high-form player get a strong guide the first few times they pick
Pitch or Chip on purpose?
**Acceptance criteria:**
- Ghost-guide alpha is computed per shot-type rep count, not global `GameState.get_form()`.
- A max-form player with zero Pitch reps sees the same guide strength as a fresh player's first
  Full swing.
- Guide strength still fades appropriately as reps accumulate within that shot type.

## Phase 5 — Flop shot (new shot type)
**Depends on:** Phase 1 (picker must exist first), Phase 4 recommended but not required.
**Club gate:** Gap/Sand Wedge only (tightens to SW/LW once Phase 6 ships).
**Distance:** ~10–30yd cap — mechanically incapable of scaling longer, not just discouraged.
**Roll:** near-zero — needs its own `air_distance_fraction` branch, distinctly lower than Pitch.
**Risk:** new miss-severity band, harsher than the other three — a bad flop should feel like a
real mistake, not a mild miss.
**Input:** tempo-gesture family (see input model above), tighter tolerance than Pitch.
**Recommend logic:** should rarely be the *default* recommendation — real players treat it as
last-resort. Surfaced as an available override when short-sided with an obstacle, not pushed.
**Playtest checkpoint:** isolated flop-only reps before it's available mid-round.
**Acceptance criteria:**
- Flop is only selectable on Gap/Sand Wedge.
- Flop cannot produce a total distance beyond ~30yd regardless of committed power input.
- Flop's miss-severity band is measurably harsher than Pitch's for an equivalent tempo error.
- Flop is never the auto-recommended shot type outside a defined short-sided/no-green scenario.

## Phase 6 — Full wedge bag expansion (deferred, own epic)
Splits the current merged "Gap/Sand Wedge" into real PW/GW/SW/LW entries with real loft-based
distance gapping. Flop tightens to SW/LW only. Not started until Phases 1–5 are stable — this
multiplies the shot-type × club matrix by 4x, so it needs the mechanic proven first.

---

## Guardrails for the agent, regardless of phase
- One phase = one PR = one playtest pass. Do not combine phases even if they touch nearby files.
- Tuning constants (roll %, tolerance bands, miss-severity scalars) are playtest targets, not
  final values — flag them as such in code comments.
- Don't touch Full or Putt's grading logic in any phase below — both are confirmed feeling good
  today and are explicitly out of scope everywhere in this roadmap.

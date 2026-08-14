# Correction — Club-Select Tendency Icon Dominated by Tempo

**Track:** correction, found live during playtest
**Branch:** TBD, from main
**Size:** likely small logic change, but the direction needs a decision — written up for
tomorrow, not implemented tonight.

---

## The complaint, precisely

Nearly every row in club select shows the same icon (lightning bolt / `rushed_transition`),
making the icon carry no information useful for choosing between clubs.

---

## Root cause, confirmed by trace

```gdscript
// club_coach_log.gd:64-89, resolve_tip()
// 1. Tempo bias (root cause) checked before path error (symptom).
if tempo_avg <= -TEMPO_THRESHOLD:
	return {"tag": "rushed_transition", ...}     // checked FIRST, unconditionally
if tempo_avg >= TEMPO_THRESHOLD:
	return {"tag": "lingering_top", ...}
// path/hook/slice only reached if tempo is clean
```

Tempo bias is checked first and short-circuits everything else. If a club's average tempo
crosses the threshold, that's the only tip returned — path leak, contact issues, anything
else club-specific never gets evaluated.

**And confirmed via your own Club Coach data across this entire session:** nearly every club
in your bag shows `tempo avg` negative and `resolved tip: rushed_transition`. That's not
inconsistent per-club data — it's one real, consistent habit showing up everywhere it's
checked.

**The actual problem: tempo is a player-level habit, not a club-level property.** You don't
rush your transition more on a 7-iron than a 5-iron for any club-specific reason — so of
course the same tag fires on nearly every row. It's accurate on every individual row and
useless as a tool for differentiating between rows, which is what this list exists to help
with.

**Confirmed the deeper conflation:** `resolve_tip()` is called identically by both
`coach_screen.gd:130` and `club_select.gd:232` — the same function, same priority order,
serving two genuinely different questions. Club Coach is a practice-review screen where
"root cause before symptom" (tempo before path) is the right coaching philosophy — you're
there to improve. Club select is an in-the-moment decision screen where the question is
"which club is safest for *this* shot" — and a repeated, non-differentiating tempo flag
crowds out the path/contact information that would actually help answer that.

---

## Directions to consider — not decided yet

**A. Split the two contexts.** Keep `resolve_tip()`'s priority order (tempo-first) for the
Club Coach screen, where it's correct. Give club select its own resolution — likely
club-specific signals first (path/hook/slice/contact), falling back to tempo only if nothing
club-specific stands out. This treats the two screens as the different questions they
actually are, rather than sharing one answer.

**B. Move tempo out of the per-row icon entirely.** If it's genuinely a player-wide habit,
show it once — a session or round-level note — rather than repeating it on every club. Frees
the per-row icon for whatever's actually club-specific.

**C. Do nothing to the logic; change presentation only.** Keep tempo-first resolution, but
visually de-emphasize it when it's the same tag repeated across many rows (e.g., grey out
rather than full-color bolt) so a genuinely differentiating icon still stands out when one
exists.

**Recommendation for discussion, not a decision:** (A) is the most correct fix — it resolves
the actual conflation rather than working around it — but it's also the most code. (B) is
smaller and matches the insight precisely (tempo isn't a club fact) but changes what the
Club Coach flow looks like at the round level, which wasn't asked for. (C) is safest and
smallest but doesn't fix the underlying mismatch, just hides its symptom.

---

## Out of scope

- The tempo threshold itself (`TEMPO_THRESHOLD`) — not being questioned, just where its
  result gets shown.
- The Club Coach screen's tip logic — confirmed correct for its purpose, not touched under
  direction A.
- The icon art itself (already shipped, correct, matches its concept).
- Fixing the underlying tempo habit — that's Matt's swing, not a code problem.

---

## Investigation before implementation

1. Confirm how often, across your actual bag, a club would show something *other* than
   rushed_transition if tempo were deprioritized — i.e., does path/hook/slice data actually
   differ meaningfully club to club? If it doesn't either, none of these directions help much
   and the finding is different than assumed.
2. If direction A is chosen: decide whether club select needs its *own* resolve function or
   whether `resolve_tip()` should take a context parameter. Report which fits the existing
   code shape better.
3. Check whether `MIN_SAMPLES_FOR_TIP` and the insufficient_data/on_track paths need any
   adjustment under a reordered priority, or whether they're independent of this.

---

## Notes for the agent

- This is a "write up for tomorrow" doc — read and investigate, report findings and a
  recommendation, before implementing anything.
- Read this document and confirm understanding before writing code.
- Touch `club_coach_log.gd` and/or `club_select.gd` depending on the chosen direction; report
  before expanding beyond those.

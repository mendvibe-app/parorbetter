# Epic: Unified Swing Fault Diagnosis (Retire the Standalone "Balance" Word)

## Problem

Post-shot feedback currently comes from **two independent grading systems that don't know about each other**, glued together with a middle dot:

1. **Tempo** — backswing:downswing ratio vs. target, with its own coaching-style fault vocabulary ("rushed the transition," "lost speed through impact," etc.)
2. **Balance** — a blended 0–1 score from swing smoothness (acceleration spikes, jerk, transition speed, backswing/follow-through length, incomplete swing), which collapses to one of three words: `steady` / `shaky` / `lurch`

Because these are computed separately, a shot can get contradictory feedback in the same sentence — e.g. tempo says `Held the top well` while balance says `lurch`, when both are actually reacting to the same rushed transition. Renaming `lurch` to something friendlier doesn't fix this; it just makes the contradiction easier to read.

The real problem: **balance never says what to fix.** It's a roughness score, not a diagnosis. Meanwhile tempo already *has* real diagnostic language for some of the same faults (`pace_copy()`, `tempo_grade.gd:265-335`). This epic merges them into one fault list so a shot gets a single, actionable, real-golf diagnosis instead of two scores stapled together.

## Goals

- One fault name per shot, chosen from a single ranked list, spoken once.
- Every fault name is something a real coach would say and a player can act on next swing.
- No duplicate/contradictory measurement of the same fault (transition speed, short backswing) by two different formulas.
- The underlying `balance` **number** keeps doing its current job in grading (tolerance shrink, contact demotion, path amplification) — this epic touches *what we say*, not *how shots are graded*.

## Non-goals / Out of scope

- Changing contact grading, distance/power_mul, or path error math. `TempoGrade.grade()`'s numeric outputs (`contact`, `power_mul`, `path_error`, `tolerance`) must be bit-for-bit unchanged before/after.
- Changing tempo ratio targets, tolerance bands, or any tuning constant (`TARGET_FULL`, `TOL_FULL`, `BAND_PERFECT`, etc.).
- Redesigning the live tempo ratio bar or practice-mode feedback (separate systems, not touched here).
- Putting AND full-swing both get fault vocabulary in this epic, but they are separate call sites (`PuttStroke.putt_note`, `TempoGrade.tempo_note`) and should be playtested separately (see Playtest Order).

## Current State (grounded in code)

- `TempoGrade.balance()` (`tempo_grade.gd:79-120`) computes a single float from 6 penalties (accel, jerk, transition, short backswing, short follow-through, incomplete) and returns *only the final blended number*. The individual penalties are discarded after this function returns — nothing downstream can see which one dominated.
- That float is used two ways:
  - **Functionally** (in scope to preserve exactly): `tolerance_width()` (`tempo_grade.gd:123-132`) shrinks the accept window as balance drops; `grade()` (`tempo_grade.gd:189-194`) demotes contact tier when balance is very low; `grade()` (`tempo_grade.gd:206-209`) amplifies shot path error when balance is very low.
  - **Cosmetically** (in scope to replace): `tempo_note()` (`tempo_grade.gd:338-366`) and `PuttStroke.putt_note()` (`putt_stroke.gd:191-236`) each independently collapse the same float into `steady`/`shaky`/`lurch` via `bal_word`, then append it to whatever tempo/miss text already exists.
- `pace_copy()` (`tempo_grade.gd:265-335`) already contains real diagnostic fault language for backswing/downswing pace and ratio mismatch, computed from `back_read`/`down_read` (categorical: `on_pace`/`slow`/`fast`) — a completely separate code path from `balance()`, sometimes describing the same underlying fault (rushed transition, short backswing).

## Proposed Architecture — 3 Phases

### Phase 1: Expose balance's sub-penalties without changing the math

Refactor `balance()` into a detail function plus a thin wrapper, so the blended float stays byte-identical but the ingredients become visible:

```
static func balance_detail(sample, tighten, shot_type) -> Dictionary:
    # ... exact same math currently inside balance() ...
    return {
        "score": clampf(1.0 - pen, 0.0, 1.0),   # identical to today's balance() return
        "causes": {
            "cast":       accel_pen * accel_w,
            "jerky":      jerk_pen * 0.15,
            "rushed_transition": transition_pen * trans_w,
            "short_backswing":   short_bs * 0.20,
            "short_finish":      short_ft * 0.15,
            "incomplete": incomplete_pen,
        }
    }

static func balance(sample, tighten, shot_type) -> float:
    return balance_detail(sample, tighten, shot_type)["score"]
```

Every existing caller of `balance()` (tolerance_width, grade()) is untouched. Zero grading risk — this phase is pure refactor, verifiable by asserting old vs. new `balance()` output matches on a batch of recorded samples.

### Phase 2: Build one ranked fault list combining balance causes + tempo causes

New function, real-golf vocabulary, single severity scale:

```
static func diagnose_swing(
    causes: Dictionary,      # from balance_detail()["causes"]
    back_read: String, down_read: String, ratio: float, target: float
) -> Dictionary:
    # Build one candidate list: balance causes (already 0..1 severity)
    # + tempo causes, given comparable 0..1 severity (see Decision Point below)
    # Sort descending by severity, apply tie-break rule, return the winner
    # (or a clean/positive read if nothing crosses a "worth mentioning" floor).
    return {
        "fault": "rushed_transition",       # or "" if swing was clean
        "line": "Rushed the transition — no pause at the top",
        "severity": 0.61,
    }
```

**Fault vocabulary (real golf terms, not engine terms):**

| Internal fault key | Player-facing line |
|---|---|
| `cast` | "Cast at it — released too early" |
| `jerky` | "Rough tempo through the swing" |
| `rushed_transition` | "Rushed the transition — no pause at the top" |
| `short_backswing` | "Backswing too short — take it to the top" |
| `short_finish` | "Quit on it before the finish" |
| `incomplete` | "Didn't complete the swing" |
| `back_slow` / `back_fast` | (from existing `pace_copy` back_line) |
| `down_fast` / `down_slow` | (from existing `pace_copy` down_line) |
| `ratio_off` | (from existing `pace_copy` headline, e.g. "Through too quick for that backswing") |
| *(none dominant)* | "Smooth swing" / omit fault line entirely — silence reads as positive |

**Decision point to confirm before implementation:** balance's causes are already 0–1 penalty scores; tempo's pace faults are currently categorical (`slow`/`fast`/`on_pace`), not numeric. To rank them on one scale, tempo faults need a comparable severity number — the natural source is how far `back_ms`/`down_ms` sit outside the guide window (already computed in `pace_band()`, `tempo_grade.gd:246-253`) or how far `ratio` sits from `target` relative to tolerance (already computed as `abs_n` in `grade()`). Recommend reusing `abs_n`-style normalization so tempo and balance severities are apples-to-apples. Flagging this as a playtest-tunable, not a final formula — the specific weights that make "cast" beat "rushed transition" when both are borderline will need on-device calibration, same as the existing `# ponytail: accel/jerk thresholds are playtest knobs` note already living at `tempo_grade.gd:93`.

**Tie-break rule:** if the top two candidate severities are within ~10% of each other, that's a genuinely mixed-fault shot — say the top one, don't try to blend two fault sentences together (avoids the "why does it say two contradictory things" problem this epic exists to fix).

### Phase 3: Rewire the two display call sites

- `tempo_note()` (`tempo_grade.gd:338-366`): replace the `bal_word` append with the `diagnose_swing()` result. Where `pace_copy()`'s headline is already the clear story (e.g. short backswing case at line 349), the diagnosis function should recognize that fault is already spoken and either stay silent or fall back to a light intensity word — avoid saying "backswing too short" twice in one sentence.
- `PuttStroke.putt_note()` (`putt_stroke.gd:191-236`): same swap for the four `bal_word` usages (lines 227, 232, 235, 236). Putts don't have `back_read`/`down_read` (no ghost pace guide), so the candidate list here is balance causes only — still a real improvement over the current single word.

## Before / After Examples

| Scenario | Before | After |
|---|---|---|
| Jabbed it, good distance | `1 ft long · lurch` | `1 ft long · cast at it — released too early` |
| Didn't finish, short | `1 ft short · didn't finish through the ball (lurch)` | `1 ft short · quit on it before the finish` |
| Full swing, rushed transition, tempo read it as fine | `Held the top well · lurch` | `Rushed the transition — no pause at the top` |
| Full swing, backswing already flagged short | `backswing too short · take it to the top · lurch` | `Backswing too short · take it to the top` (no redundant second mention) |
| Genuinely clean swing | `steady` | `Smooth swing` (or omitted — TBD in playtest, see Acceptance Criteria) |

## Acceptance Criteria

- [ ] `balance()` output is numerically identical before/after Phase 1 refactor across a recorded sample batch (regression check, not a judgment call).
- [ ] `tolerance_width()`, contact tier demotion, and `path_error` amplification in `grade()` are unaffected — same shot inputs produce same contact grade, power_mul, and path_error as pre-epic.
- [ ] No shot's feedback string names the same fault twice (e.g. "backswing too short" appearing in both the primary miss line and the diagnosis tail).
- [ ] No two systems (tempo pace read vs. diagnosis) contradict each other in the same sentence.
- [ ] Every fault line is a real, teachable golf instruction — reviewed against Tour Tempo / standard swing-fault language, not engine terminology.
- [ ] `lurch` no longer appears anywhere in player-facing strings (search `bal_word` and grep for `lurch` returns nothing outside old comments/history).
- [ ] Clean/no-fault case decided and implemented consistently: either a short positive line ("Smooth swing") or omitted entirely — pick one, don't mix.

## Playtest Order

1. **Putt feedback in isolation** (`PuttStroke.putt_note`) — smaller surface area, no tempo-pace interaction, good first correctness check on the fault vocabulary itself.
2. **Full-swing feedback** (`TempoGrade.tempo_note`) — includes the harder case (merging tempo pace faults with balance causes, tie-break rule).
3. Confirm across shot types where `balance_detail()` uses different constants — putt/pitch vs. full (`is_pitch` branch, `tempo_grade.gd:88-97`) — the pitch-specific accel thresholds exist because pitch's short pad reverse motion reads differently; verify diagnosis language doesn't mislabel a normal pitch reverse as "cast."
4. Regression pass: confirm contact/distance/path outputs match pre-epic recordings (Phase 1 acceptance criterion) before shipping Phase 2/3 copy changes live.

## Rollback Plan

Because Phase 1 is a pure refactor and Phases 2/3 only change what string gets built (not grading math), rollback is low-risk: revert `tempo_note()` and `putt_note()` to reference `balance()`'s float and the old `bal_word` ternary if the new diagnosis reads worse in playtest. Keep `balance_detail()` in place either way — it's harmless additional data even if unused.

## Open Questions for Matt

1. Severity-scale decision point above (Phase 2) — comfortable letting the coding agent pick a reasonable normalization, or want to lock the formula first?
2. Clean-swing case: short positive line, or silence? (Affects UI — a line means the panel always has a "swing quality" row; silence means that row sometimes disappears.)
3. Any fault names above that don't match how you'd actually coach it — this list was built from the existing penalty variables, not audited against your Tour Tempo reference material yet.

# Epic: Tempo Feedback Rework — Practice-Only Live Meter + Post-Shot Two-Part Read

## Why (grounded in research, not vibes)

Two decisions came out of a playtest + design pass, backed by real golf coaching and comparable golf games:

1. **Live tempo bar during a real shot doesn't do a job any real system asks it to do.** Real golf tempo training (Tour Tempo, Kostis metronome method) is delivered through *sound during the motion*, not a gauge you read and react to — and the downswing window (~0.25–0.4s) is too fast for a human to watch a needle and adjust anyway. Our ghost-dot + tick system already fills that role. The live ratio bar is redundant and, per the reported "green on green on green" issue, actively hurts readability for no coaching benefit.
2. **Practice Mode is the correct exception.** Tour Tempo's own app — the tool our 3:1 mechanic is modeled on — is explicitly a *range/practice* tool: repetition with a live number to match is the entire point of practice. That distinction (live feedback while grooving vs. clean feedback while performing) is a real golf distinction, not an arbitrary game one.
3. **Post-shot feedback should be structural, not a single blended word.** PGA Tour 2K25's EvoSwing — already our reference for the swing gesture itself — grades swings as separate labeled components (contact, rhythm, transition, swing path) rather than one number. Our current post-shot "Late"/"Early" collapses two different timings (backswing pace, downswing pace) into one ambiguous word. Real coaching also has a diagnostic bias worth reflecting: when a ratio is off, it's overwhelmingly because the **backswing was too slow**, not because the downswing was too fast — that's the textbook Tour Tempo diagnosis, and our wording should lead with it rather than staying neutral.

## Scope

**In scope:**
- Gate the live ratio meter (full/pitch shot types) to Practice Mode only.
- Declutter the real-shot swing pad — no live meter, no live title text — while the player is actually scoring a hole.
- Rework the post-shot panel's tempo readout from one "Late/Early + ratio" line into a two-part read: backswing pace + downswing/transition pace, each independently labeled.

**Out of scope (don't touch):**
- The underlying `TempoGrade` scoring math (ratio, tolerance bands, contact quality). Scoring stays speed-invariant exactly as designed — we are only changing what the player is *shown*, not how shots are graded.
- Putt/chip amplitude feedback (`TempoMini._draw_amplitude_strip`, `MeterDisplay._draw_putt_amplitude`) — those are a structurally separate system per prior epic notes and aren't part of this pass.
- Ghost dot / metronome tick system — stays as-is; it's the validated real-time coach.

---

## Part 1 — Gate the live meter to Practice Mode

**File:** `scripts/shot/meter_display.gd`

`set_shot_context()` currently sets:
```gdscript
visible = p_type != "putt" and p_type != "chip"
```
This makes the full/pitch ratio bar visible any time it's not a putt/chip — regardless of context. There are three swing contexts in the current build, not two, and they use two different flags:
- Real hole shot (scored) — `practice_mode = false`, `GameState.range_mode = false`
- **Practice Swing button** (per-shot do-over before committing) — sets `ShotRoutine.practice_mode = true`
- **Range Mode** (the driving range) — a *separate* flag, `GameState.range_mode`. Confirmed from `hole_controller.gd`: `_begin_range_swing()` calls `_start_power_swing(false)`, i.e. it does **not** set `practice_mode` today.

Both of the latter two are "no score on the line, grooving a swing" contexts — the exact case the Tour Tempo app itself is built for — so both should keep the live meter. Gate on either flag being true, not `practice_mode` alone:
```gdscript
visible = (p_practice or GameState.range_mode) and p_type != "putt" and p_type != "chip"
```
Putt/chip stay hidden either way (unchanged — that's the existing "hint owns the instruction" behavior, not part of this epic).

**File:** `scripts/shot/shot_routine.gd`

`practice_mode` is already threaded into `meter_display.set_shot_context(shot_type, timing_scale, practice_mode)` via `begin_shot()` — no change needed there. `MeterDisplay` can read `GameState.range_mode` directly (it's an autoload), so no new plumbing is needed to get that second flag into `set_shot_context()`.

## Part 2 — Declutter the real-shot pad

**File:** `scripts/shot/meter_display.gd`

With Part 1 done, real shots naturally get a hidden meter — confirm there's no dead space/layout gap left behind where the bar used to sit (check the `.tscn` layout for `MeterDisplay`'s anchor — if other HUD elements were positioned relative to it, they may need to shift to fill the space, not just leave it blank).

No changes needed to `tempo_gesture.gd` — the ghost dot and tick system are unaffected and continue to run during every real shot exactly as now.

## Part 3 — Post-shot two-part read

**Files:** `scripts/shot/tempo_grade.gd`, `scripts/ui/tempo_mini.gd`, `scripts/ui/shot_result_panel.gd`

### The attribution problem to solve

`TempoGrade.grade()` already returns `backswing_ms` and `downswing_ms` (actual times), plus `ratio` and `target`. But `ratio` alone can't tell you *which* phase was off — a 4.5:1 ratio could be a slow backswing, a fast downswing, or both. The `tempo_note()` function already makes a partial attempt at this via a relative comparison (`down_ms < back_ms / target * 0.92`), but it's still derived entirely from the ratio, not from any absolute reference.

**Use the existing guide durations as the absolute anchor.** `TempoGesture` already computes an expected absolute pace for the ghost demo — `_guide_back_sec()` / `_guide_down_sec()`, club-scaled via `club_guide_duration_scale()`. These are the same numbers already driving the ghost dot's pacing, so they're a "free" reference: compare the player's actual `backswing_ms` against the guide's expected back-seconds (scaled to ms), and separately compare `downswing_ms` against the guide's expected down-seconds. This gives two genuinely independent reads instead of one number split two ways.

Add a static function to `TempoGrade` (or call into `TempoGesture`'s existing guide-duration helpers — whichever keeps `TempoGrade` pure; `TempoGesture`'s scaling depends on `club_max_yards` so the grade call site will need to pass that through) that returns something like:
```gdscript
{
  "backswing_read": "on_pace" | "slow" | "fast",
  "downswing_read": "on_pace" | "slow" | "fast",
}
```
using a similar tolerance-band approach to the existing contact bands (perfect/good/off), just applied to each absolute duration vs. its guide target instead of to the ratio.

### Wording — lead with the real-coaching diagnosis

Per the research: when the ratio comes in high (too many backswing units per downswing unit), the default real-world diagnosis is "backswing too slow," not "downswing too fast" — golfers who feel like they rushed the downswing are usually told to speed up the backswing instead. Bias the copy accordingly:
- Backswing read "slow" → *"Backswing — too slow, take it back with more pace"* (leads with the coaching-standard fix)
- Backswing read "on pace" + downswing read "fast" → *"Downswing — rushed the transition"*
- Backswing read "on pace" + downswing read "slow" → *"Downswing — lost speed through impact"*
- Both "on pace" → *"Tempo — on time"* (current good case, keep as-is)

This replaces the single `_verdict_word()` "Early"/"Late"/"On time" output in `tempo_mini.gd` with two labeled lines instead of one word.

### UI

**File:** `scripts/ui/tempo_mini.gd`

`_draw_ratio_strip()` currently draws one strip with one needle and one word label. Replace with two compact rows (backswing / downswing), each with its own short label and color (reuse the existing green/yellow/red band-color logic per row, just fed by each row's own deviation instead of one shared `err`). The existing ratio number (`%.1f:1`) can stay as a small secondary readout under both rows — it's genuinely useful context, just shouldn't be the only signal.

**File:** `scripts/ui/shot_result_panel.gd`

No structural changes expected — `show_launch()` / `show_final()` already just call `tempo_mini.show_verdict(GameState.last_tempo_metrics, ...)`. As long as `last_tempo_metrics` (set in `shot_routine.gd`) carries the new backswing/downswing read fields from `TempoGrade.grade()`, this file doesn't need edits.

---

## Acceptance criteria

- [ ] Full/pitch live ratio meter is visible during Practice Mode swings, hidden during real (scored) shots.
- [ ] No layout gap or dead space left on the real-shot pad where the meter used to render.
- [ ] Post-shot panel shows two independently-labeled reads (backswing pace, downswing/transition pace), not a single Late/Early word.
- [ ] Wording defaults to the backswing-first diagnosis when the ratio is high, matching real coaching bias.
- [ ] `TempoGrade`'s actual scoring output (`ratio`, `tolerance`, `contact`, `power_mul`, `path_error`) is unchanged — this epic only changes what's displayed, not how shots are graded.
- [ ] Putt/chip amplitude feedback path is untouched.
- [ ] Live meter is visible in both the Practice Swing button flow and Range Mode (confirmed as two separate flags in code — see Part 1), and hidden on real scored shots.

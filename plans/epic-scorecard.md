# Epic: Live Scorecard

**Status:** Ready for implementation
**Branch suggestion:** `feature/scorecard`
**Depends on:** none — all required state already exists in `GameState`
**Related:** 18 Hole Round mode (stroke play) — this is the payoff UI for that system

---

## 1. What we're building

A real paper-style scorecard that fills in hole by hole as the round is played, using
correct golf markings — circle for birdie, double circle for eagle, square for bogey,
double square for double-bogey-or-worse, plain digit for par — with a running OUT / IN /
TOTAL and score-to-par, matching what's printed on an actual course scorecard.

This is scoped to **18 Hole Round (stroke play) mode**. Survival's identity is already
built around lives/hearts as the moment-to-moment feedback loop; a scorecard interrupt on
every hole there would fight that pace rather than support it. Stroke play is the mode
that's literally "play a real round," so it's the right home for this.

Approved concept prototype: `scorecard-prototype.jsx` (paper card, front/back nine grid,
pen-stroke draw-on animation per mark). This epic ports that concept into Godot using the
scoring data that already exists in `GameState`.

---

## 2. Why this is a small epic

No new scoring state is needed. It already exists:

- `GameState.hole_scores: Array[int]` — score-to-par diff appended on every hole-out
  (`scripts/autoload/game_state.gd:74`, appended in `add_score_to_par()` at `game_state.gd:379-388`)
- `GameState.course: Array[HoleData]` — par per hole via `HoleData.par` (`scripts/course/hole_data.gd:23`)
- `Scoring.result_from_diff(diff)` / `Scoring.label()` — already produces exactly the
  Eagle/Birdie/Par/Bogey/Double+ buckets we need for marks (`scripts/systems/scoring.gd`)
- `GameState.is_stroke_play()` — existing mode gate (`game_state.gd:152-153`)

**Strokes for a hole = `par + diff`.** We don't need a separate strokes-per-hole array;
derive it from `course[i].par + hole_scores[i]` when rendering.

This means the entire epic is new *presentation* — one new scene/script, three small
hook-ins to existing files. No GameState changes.

---

## 3. New file: `scripts/ui/scorecard.gd` + `scenes/ui/scorecard.tscn`

A reusable `Control` that renders the full 18-hole card and can be used in two places:
the live in-round peek, and the round-complete summary.

**Public API:**

```gdscript
class_name ScoreCard
extends Control

## Rebuilds the grid from GameState (call once when entering stroke play,
## and again on reset_run).
func populate() -> void

## Call right after GameState.add_score_to_par(diff) for the hole that just
## finished. Triggers the draw-on animation for that single cell; does not
## rebuild the whole grid.
func reveal_hole(hole_index: int, diff: int) -> void
```

**Rendering approach:** 18 hole cells laid out as two rows of nine (front/back), each
cell a small `Control` with:
- hole number + par (static labels, set once in `populate()`)
- a strokes `Label` (set on reveal)
- a mark drawn via `_draw()` on a child `Control` — `draw_arc()` for birdie/eagle circles,
  `draw_rect()` with `filled=false` for bogey/double squares, nothing for par

Mark color by result, matching the prototype:
- Birdie / Eagle → warm red (`#B23A2F`) — *provisional, confirm against brand palette*
- Bogey / Double+ → navy (`#24334A`) — *provisional*
- Par → no mark, just the digit

`reveal_hole()` plays a ~0.5s tween that scales the mark's `draw_progress` from 0→1
(store as a float on the cell, redraw each frame via `queue_redraw()` in `_process`,
draw arcs/rects at `2π * draw_progress` / partial rect points respectively) — this is the
"pen stroke" moment. Keep it under 600ms; this fires once per hole and shouldn't feel
like it's blocking the next shot.

**OUT / IN / TOTAL columns:** sum of the 9 par values, sum of revealed strokes, and
`GameState.format_score_to_par()` for the to-par pill. Recompute in `populate()` and
after each `reveal_hole()`.

**Course label:** there's no course name (`GameState.course` is procedurally generated —
`scripts/autoload/game_state.gd:32-33, 166-168`). Use the theme instead, e.g.
`"PARKLAND COURSE"` from `HoleData.CourseTheme` (`hole_data.gd:10`). Don't invent a
course-name field for this epic.

---

## 4. Hook 1: trigger the reveal at hole-out

`scripts/course/hole_controller.gd:2492` (`_on_holed_out()`) already computes `diff` and
calls `GameState.add_score_to_par(diff)` at line 2518. Add the reveal call immediately
after it, gated to stroke play:

```gdscript
# hole_controller.gd:2518, existing line:
GameState.add_score_to_par(diff)
# ADD:
if GameState.is_stroke_play():
    scorecard.reveal_hole(GameState.current_hole, diff)
```

This sits inside the existing 1.55s hold before `request_next_hole.emit()`
(`hole_controller.gd:2528` area), so the mark animation has room to play without adding
any new wait time — it rides the beat that's already there for the camera settle.

`scorecard` needs to be wired as an `@onready` reference to the scene instance (see
Hook 2 for where it lives).

---

## 5. Hook 2: make it visible during play — a peek, not an interrupt

Per the friction lesson from the practice-swing-button epic, this should **not** be a
full-screen forced interrupt every hole. Recommended: a small pinned tab (like a physical
scorecard tucked in a pocket) in the HUD, visible only in stroke play, that the player can
tap to expand/collapse. The mark-draw animation plays in the collapsed tab's mini-cell
even if the player never opens it, so the "as you go" feeling is ambient, not forced.

`scripts/ui/hud.gd`:
- `refresh()` (`hud.gd:44-56`) already branches HUD content by mode (`lives_row.visible = GameState.is_survival()` at line 55). Add a parallel `scorecard_tab.visible = GameState.is_stroke_play()` there.
- Add `@onready var scorecard_tab: Control` pointing at a new child scene instance of `ScoreCard` (collapsed-state variant), added to `scenes/ui/hud.tscn`.

This is a judgment call worth confirming before implementation: **pinned tab that
expands** vs. **always-expanded strip along one edge**. The prototype's full grid is wide
(9 columns) — on a phone screen that likely wants the expand/collapse pattern rather than
sitting open during shots. Flagging for your call; recommend expand/collapse as the
default.

---

## 6. Hook 3: round-complete — replace the text-only card

`scripts/ui/game_over.gd` currently renders a plain text approximation
(`_hole_card_line()`, lines 53-68) — just `format_score_to_par()` strings space-separated,
wrapped every 6. Replace this with an instance of the same `ScoreCard` scene, fully
populated and revealed, as the actual round summary artifact.

```gdscript
# game_over.gd:_show_stroke_complete(), replace the `_hole_card_line()` call and
# its append with:
scorecard_summary.populate()   # ScoreCard child instance added to game_over.tscn
scorecard_summary.reveal_all() # new method: reveals all 18 at once, no animation delay
scorecard_summary.visible = true
```

Add `reveal_all()` to `ScoreCard` as a thin wrapper that sets every cell's
`draw_progress = 1.0` directly (no tween) — the round is already over, no need to replay
18 pen-strokes in sequence.

`_hole_card_line()` can be deleted once this is wired up.

---

## 7. Art assets — generate via PixelLab MCP, not ad hoc

The scorecard's marks (circles/squares) are code-drawn (§3) and need no art. But two
small pieces of chrome would benefit from actual assets rather than more `_draw()` calls,
and they need to match the existing icon language in `assets/ui/` — small pixel art, hard
edges, tight limited palette (e.g. `life_full.png` / `life_empty.png`, the heart icons
already used for Survival lives).

Candidates:
- **Scorecard tab icon** (collapsed HUD state, §5) — a small pixel-art scorecard/pencil
  icon, sized to sit next to the existing lives row
- **Paper texture / corner fold** for the card background, if the flat `Panel` fill from
  the prototype reads too flat in-engine — low priority, only pursue if the plain version
  looks bare once it's actually on a phone screen

**Generate these through the PixelLab MCP connector**, not a generic image model and not
the PIL fallback — PixelLab is what's kept the rest of the icon set consistent, and a
different generator here would visibly clash with `life_full.png` and friends. PixelLab
isn't connected in this session (needs the domain allowlisted + a fresh session to
activate, per earlier setup notes); pick this up in a session where it's live. Prompt it
with the two reference icons above (`assets/ui/life_full.png`, `life_empty.png`) so the
palette and pixel density match, rather than describing the style from scratch.

Both are genuinely optional for v1 — ship with the plain drawn version first, swap in
generated art after playtesting confirms it needs it. Don't block the epic on this.

---

## 8. Out of scope for this epic

- Survival mode fill-in animation or scorecard view (lives/hearts remain that mode's
  identity; revisit only if playtesting shows a real gap)
- Editing/correcting a posted score after the fact
- Exporting or sharing the scorecard as an image
- Multi-player / marker mode (one card per player)
- Handicap-stroke dots per hole on the card face (net scoring already exists in
  `GameState.net_score_to_par`, but rendering handicap dots on the mark grid is a nice
  follow-up, not required for v1)

---

## 9. Acceptance criteria

- [ ] Playing a full 18 Hole Round (stroke play) posts a mark to the correct cell after
      every hole-out, with the correct shape for Eagle/Birdie/Par/Bogey/Double+ per
      `Scoring.result_from_diff()`
- [ ] Strokes shown per cell equal `course[i].par + hole_scores[i]` and match what the
      existing `_hole_result_feedback()` toast reports for that hole
- [ ] OUT / IN / TOTAL and to-par pill update correctly at 9 holes and 18 holes
- [ ] Scorecard tab is hidden entirely in Survival mode and in Range/Green practice
- [ ] Round-complete screen shows the same fully-populated card, replacing the old
      text-only `_hole_card_line()` output
- [ ] No added delay to hole-to-hole pacing — reveal animation fits inside the existing
      1.55s post-holeout hold
- [ ] Legible at phone width — 9-column grid doesn't force horizontal scrolling in the
      collapsed/expanded states you choose

---

## 10. Playtest order

1. Stroke play, isolated: play a full 18 with the tab **collapsed** throughout — confirm
   marks are posting correctly even when unseen (check by expanding at hole 18).
2. Same round with the tab **expanded** — confirm animation timing feels good pace-wise,
   doesn't feel like it's blocking the next tee shot.
3. Force each result type at least once (birdie, eagle, par, bogey, double+) via debug
   controls if available, to visually confirm all four mark shapes render correctly.
4. Confirm Survival mode shows no scorecard tab and is otherwise unaffected.
5. Round-complete screen: confirm parity between the last-seen live card and the
   final summary card (should be identical, since it's the same component).

---

## 11. Open questions to confirm before build

1. **Tab pattern:** expand/collapse vs. always-open strip (recommend expand/collapse — see §5)
2. **Mark colors:** red birdie/eagle, navy bogey/double — confirm against brand, or should
   this just use `PAR OR BETTER`'s existing UI accent colors instead of inventing new ones?
3. **Reveal animation duration:** 0.5s pen-stroke default — fine, or want it snappier for
   pace of play?
4. **PixelLab timing:** ship v1 with the plain code-drawn card and generate the tab
   icon / paper texture in a follow-up pass once PixelLab is reconnected, or hold the
   epic until that session is available?

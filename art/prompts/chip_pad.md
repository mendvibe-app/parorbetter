# Prompt Skill: Chip Pad

**Status**: Active
**Depends on**: art/STYLE.md (**Pixel Kit Golf**), art/prompts/tempo_pad.md, art/prompts/putt_pad.md
**Purpose**: Visual elements for the chip stroke pad — same amplitude-gesture family as putt (`PuttStroke` grading, shorter lane), warm sand/wedge palette skin.

Any agent generating chip pad art must follow this file and art/STYLE.md.

---

## 1. Context

Chipping reuses `TempoGesture`'s amplitude-pad rendering (the same code path as putt: lane, arc-edge taper, follow cue, address ball, practice marker) but with a warm palette and a shorter lane than putt. It must feel like a sibling of the putt pad (same landmark roles, same "this is a stroke-length pad, not a tempo-ratio pad" language) while reading as clearly "chip," not a putt recolor and not a full-swing recolor.

Real golf distinction driving the visual: a chip is a shoulders-only stroke played from just off the green with a wedge — low and running, distance controlled by how far back the stroke goes (same DNA as putting), not a full backswing/downswing tempo motion. The palette should read "wedge / fairway apron," not "water" (putt) and not the full-swing tempo pad's green.

Landmarks (same roles as putt):
- START – address
- TOP – backswing / stroke-length peak
- THROUGH – impact through the ball

Additional:
- Pull / arc lane (center track; widening edge guides stay code-drawn)
- Optional idle coach cue (subtle)

No soft feet-scale ruler for chip (unlike putt) — keep labels/ticks entirely code-side as usual; nothing extra to bake into the art here either way.

**Current state**: code ships with placeholder art — the putt art set exact-recolored from its cool water palette into this file's warm sand palette (hue-swap only, same silhouettes). Replace with dedicated chip-specific art generated from this prompt when ready; the recolor is a stand-in, not the target look.

---

## 2. Technical Constraints

- Style: art/STYLE.md
- View: Flat UI overlay
- Resolution: 64×64 landmarks; lane 64×128
- Palette: Prefer **sand** + neutrals (`#D4BB92` / `#BA986B` / `#8B6B45` / `#E8DCC0` / `#E8F0E8` / `#1A1F1A`) — art/STYLE.md's existing Sand anchors, reused rather than inventing a new documented palette. Warmer than putt's water blues, cooler/less saturated than a bunker-sand tile so it doesn't compete with real sand terrain.
- Transparency: Required
- Naming:
  - `ui_chip_landmark_start.png`
  - `ui_chip_landmark_top.png`
  - `ui_chip_landmark_through.png`
  - `ui_chip_lane.png`
  - `ui_chip_coach_idle.png`

---

## 3. Generation Guidance

- Same silhouettes / visual family as putt landmarks (this is the closest sibling — same grading math, same drawing code), but warm wedge/sand materials instead of water.
- TOP reads as "stroke-length peak," not a power apex — same intent as putt's TOP, not full swing's.
- THROUGH = contact through the ball (diamond/spark OK, warm-toned).
- Lane: clear vertical path, visibly shorter proportionally than the full-swing lane when drawn on pad (code already places chip's address/top hints between putt's and full's) — art itself can still be the same 64×128 strip convention; the shortened feel comes from how code stretches it between the two hint points.
- Coach stays abstract; pad golfer is separate overlay frames (`art/prompts/golfer.md`), not the coach cue.

---

## 4. Master Prompt Addition

UI overlay chip stroke pad, crunchy true pixel, warm sand/wedge palette, hard outline, transparent, [specific element], sibling of putt pad landmark family (shorter lane, warmer materials)

---

## 5. Output

Individual elements → `art/generated/` → cleaned → `assets/ui/`. Wire in `TempoGesture` chip draw path only (`_draw_chip`, alongside the shared amplitude-pad helpers `_draw_putt_lane_tex` / `_draw_putt_arc_edges` / `_draw_putt_follow_cue` / `_draw_putt_address` / `_draw_putt_practice_marker`, which already accept chip's texture/color arguments).

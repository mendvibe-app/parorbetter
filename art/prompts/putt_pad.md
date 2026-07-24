# Prompt Skill: Putt Pad

**Status**: Active  
**Depends on**: art/STYLE.md (**Crunchy Pixel**), art/prompts/tempo_pad.md  
**Purpose**: Visual elements for the putt stroke pad — same gesture family as full swing, cool water palette skin.

Any agent generating putt pad art must follow this file and art/STYLE.md.

---

## 1. Context

Putting reuses `TempoGesture` with a cool palette. It must feel related to the full-swing tempo pad (same landmark roles) but clearly “putt,” not a green recolor of full swing.

Landmarks (same roles):
- START – address
- TOP – backswing / pace length peak
- THROUGH – impact through the ball
- FOLLOW – soft finish past address

Additional:
- Pull / arc lane (center track; widening edge guides stay code-drawn)
- Optional idle takeaway cue (subtle)

Keep soft feet-scale ticks and labels in code (no text baked into art).

---

## 2. Technical Constraints

- Style: art/STYLE.md
- View: Flat UI overlay
- Resolution: 64×64 landmarks; lane 64×128
- Palette: Prefer **water** + neutrals (`#5BA8D9` / `#3A7EAE` / `#2A5A7A` / `#A8D4F0` / `#E8F0E8` / `#1A1F1A`). Sand accents OK for impact spark.
- Transparency: Required
- Naming:
  - `ui_putt_landmark_start.png`
  - `ui_putt_landmark_top.png`
  - `ui_putt_landmark_through.png`
  - `ui_putt_landmark_follow.png`
  - `ui_putt_lane.png`
  - `ui_putt_coach_idle.png`

---

## 3. Generation Guidance

- Same silhouettes / visual family as full-swing landmarks, but cooler materials (water language).
- TOP reads as “pace turn,” not a power apex.
- THROUGH = contact through the ball (diamond/spark OK).
- Lane: clear vertical path; must stretch between address and top.
- Coach stays abstract; pad golfer is separate overlay frames (`art/prompts/golfer.md`), not the coach cue.

---

## 4. Master Prompt Addition

UI overlay putt stroke pad, crunchy true pixel, cool water palette, hard outline, transparent, [specific element], sibling of tempo pad landmark family

---

## 5. Output

Individual elements → `art/generated/` → cleaned → `assets/ui/`. Wire in `TempoGesture` putt draw path only.

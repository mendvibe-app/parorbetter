# Prompt Skill: Pad Golfer (Swing Sync)

**Status**: Active  
**Depends on**: `art/STYLE.md` (**Pixel Kit Golf**) + `art/prompts/kit.md`  
**Purpose**: Discrete pose frames for the input-area golfer that tracks the thumb stroke.

Any agent generating golfer art must follow this file, STYLE.md, and the **character pipeline** in kit.md.

---

## 1. Context

Side/¾ silhouette in a **top-left mini stage** (sky + grass drawn in code). Pose follows spatial stroke progress (`live_stroke_u`), not the 3:1 ratio meter.

Not the idle coach cue (`ui_tempo_coach_idle` / `ui_putt_coach_idle`).

**Three visual identities (same person, different setup):**
- **Full** — upright, long club, big shoulder turn (driver / long irons)
- **Putt** — crouched, narrow stance, short putter, low hands (not a recolor of full)
- **Chip / pitch** — open lean, wedge, compact arc (pitch reuses chip golfer art; tempo still 2:1)

Frames per set (8 keyframes, stroke order):
ADDRESS → TAKEAWAY → MID → LATE → TOP → EARLY_DOWN → IMPACT → FOLLOW

---

## 2. Technical Constraints

- Style: Pixel Kit Golf (hard outline, limited palette, Filter Off)
- Pipeline: kit-authored modular sprites (same identity); never freeform a new person per pose
- View: Flat UI overlay, side/¾ facing **right**
- Resolution: **128×192** per frame
- Palette: STYLE neutrals + greens; skin `#D4BB92` / `#BA986B`; shirt `#E8F0E8`; pants `#2E342E` / `#1A1F1A`; club near-black
- Transparent background (stage is code-drawn)
- Same proportions / pivot across frames (feet planted)
- Naming (full; putt/chip same suffixes with `_putt_` / `_chip_`):
  - `ui_golfer_address|takeaway|mid|late|top|early_down|impact|follow.png`

---

## 3. Generation Guidance

- Readable at ~100–130px on-screen (Filter Off), top-left of pad
- Full: arms + long club big arc
- Putt: short shaft; waist–chest takeaway
- Chip: wedge head longer than putter; same compact arc as putt
- Simple cap + body blocks — no face mush
- Leave margin so outline survives nearest scale

**Derisk:** lock address + impact as same person before generating the rest of the pack.

---

## 4. Master Prompt Addition

```
pixel art game kit character, flat UI overlay 128x192, side view facing right,
hard outline, transparent background, mobile golf [full|putt|chip] pose,
[address|mid|top|impact|follow], same character identity, limited STYLE palette
```

---

## 5. Output

`art/generated/` → gate → `assets/ui/`.  
Wired in `TempoGesture._draw_golfer` / `_golfer_pose_pair` (`_is_putt()` / `_is_chip()` pick the set).

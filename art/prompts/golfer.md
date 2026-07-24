# Prompt Skill: Pad Golfer (Swing Sync)

**Status**: Active  
**Depends on**: art/STYLE.md (**Crunchy Pixel**)  
**Purpose**: Discrete pose frames for the input-area golfer that tracks the thumb stroke.

Any agent generating golfer art must follow both this file and art/STYLE.md.

---

## 1. Context

Side/¾ silhouette drawn in a **top-left mini stage** (sky + grass drawn in code). Pose follows spatial stroke progress (`live_stroke_u`), not the 3:1 ratio meter.

This is **not** the idle coach cue (`ui_tempo_coach_idle` / `ui_putt_coach_idle`). Coach stays an abstract takeaway chevron; golfer is a separate overlay.

**Two swing sets:**
- **Full / chip** — shoulder turn, long club
- **Putt** — short putter stroke; arms stay waist–chest height

Required frames per set (in stroke order):
- ADDRESS – club grounded, ready
- MID – halfway back
- TOP – top of backswing / stroke
- IMPACT – contact / hands through
- FOLLOW – finish

---

## 2. Technical Constraints

- Style: Strictly art/STYLE.md (Crunchy Pixel — visible pixels, hard outlines, dither OK)
- View: Flat UI overlay, side/¾ facing **right** (toward center lane)
- Resolution: **128×192** per frame (taller silhouette)
- Palette: STYLE neutrals + greens; skin `#D4BB92` / `#BA986B`; shirt light accent `#E8F0E8`; pants `#2E342E` / `#1A1F1A`; club near-black
- Edges: Hard. No anti-aliasing. Transparent background (stage is code-drawn).
- Same character proportions / pivot across frames within a set (feet planted)
- Naming (full):
  - `ui_golfer_address.png` / `_mid` / `_top` / `_impact` / `_follow`
- Naming (putt):
  - `ui_golfer_putt_address.png` / `_mid` / `_top` / `_impact` / `_follow`

---

## 3. Generation Guidance

- Readable at ~100–130px on-screen (Filter Off), top-left of pad.
- Full: arms + long club carry a big arc.
- Putt: short shaft; takeaway/top stay roughly waist–chest (no over-shoulder).
- Facing the lane (right). Leave margin so outline survives nearest scaling.
- No face detail mush — simple cap + body blocks.

---

## 4. Master Prompt Addition

```
flat UI overlay, crunchy true pixel golfer silhouette 128x192, side view facing right,
hard outline, transparent background, mobile golf [full swing|putt stroke] pose,
[address|mid|top|impact|follow-through], same character across frames, limited STYLE palette
```

---

## 5. Output

`art/generated/ui_golfer_*.png` → cleaned → `assets/ui/`. Wire in `TempoGesture._draw_golfer` / `_golfer_pose_pair` (`_is_putt()` picks set). Stage = `_draw_golfer_stage`.

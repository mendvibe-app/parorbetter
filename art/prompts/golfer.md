# Prompt Skill: Pad Golfer (Swing Sync)

**Status**: Active  
**Depends on**: `art/STYLE.md` (**Pixel Kit Golf**) + `art/prompts/kit.md`  
**Purpose**: Discrete pose frames for the input-area golfer that tracks the thumb stroke.

Any agent generating golfer art must follow this file, STYLE.md, and the **character pipeline** in kit.md.

---

## 1. Context

Side/¾ silhouette in a **reserved column beside the swipe lane** (~34% pad width; RH left / LH right via `flip_h`, not a second art pack). Sky + grass stage is drawn in code. Pose follows spatial stroke progress (`live_stroke_u`), not the 3:1 ratio meter. Engine snaps to nearest of 8 keyframes (crossfade ghosts at this size).

**Locked facing:** chest toward camera, face in profile looking **right**. Paper-doll — torso stays, only arms + club move. Do not show the back or bring the left shoulder to camera (that reads as swinging the wrong way). Left-handed is the engine mirror; do not author a second pack.

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
- View: Flat UI overlay, side/¾ facing **right** (LH is a horizontal flip)
- Resolution: **128×192** per frame (fit-centered in the reserved column)
- Palette: STYLE neutrals + greens; skin `#D4BB92` / `#BA986B`; shirt `#E8F0E8`; pants `#2E342E` / `#1A1F1A`; club near-black
- Transparent background (stage is code-drawn)
- Same proportions / pivot across frames (feet planted)
- Naming (full; putt/chip same suffixes with `_putt_` / `_chip_`):
  - `ui_golfer_address|takeaway|mid|late|top|early_down|impact|follow.png`

---

## 3. Generation Guidance

- Readable at column scale, Filter Off, fit-centered in the left/right stage (not planted in a corner)
- Full: arms + long club big arc — leave headroom so the top-pose shaft is not clipped
- Putt: short putter; compact arc (peak at waist/thigh, not the cap); impact = putter **at the ball**; follow = short finish **right**, still low
- Chip: wedge head (lofted, longer than putter); slightly bigger compact arc than putt; impact still at the ball. Pitch + flop reuse this pack; punch uses full
- Downswing is only three snaps (`top → early_down → impact`) — those plus follow must be glance-distinct
- Simple cap + body blocks — no face mush
- Leave margin so outline survives nearest scale (3–4×)
- Do not author a left-handed pack; the engine flips
- Next density if the 8-pose snap feels steppy: 12 frames (in-betweens of the same identity) — not PixelLab `create_character`

**Derisk:** lock address from the full-swing identity, then paper-doll the other seven. Gate each pack on the pad before starting the next.

---

## 4. Master Prompt Addition

```
pixel art game kit character, flat UI overlay 128x192, side view facing right,
hard outline, transparent background, mobile golf [full|putt|chip] pose,
[address|mid|top|impact|follow], same character identity, limited STYLE palette
```

---

## 5. Output

`art/generated/wave_E/imagine/` → `plant_imagine.py --pack full|putt|chip` → gate → `assets/ui/`.  
Wired in `TempoGesture._draw_golfer` / `_golfer_pose_pair` (`_is_putt()` / `_uses_chip_golfer()` pick the set).

# Wave C — HUD icons (Pixel Kit Golf)

**Date:** 2026-07-29  
**Status:** Clubs / lives / confirm **promoted** to `assets/ui/` (hard-pixel kit)

## Approach

Old HUD clubs/lives were soft AI silhouettes (anti-aliased, off-palette).  
**Ship path:** procedural hard-pixel icons via `gen_hud_icons.py` — same kit language as pad golfer (hard outline, limited palette, transparent 64×64).

## Promoted set

| File | Role |
|------|------|
| `club_{driver,wood,hybrid,iron,wedge,putter}.png` | Glance club icon |
| `life_{full,empty}.png` | Lives row |
| `confirm_aim_button[_pressed].png` | Aim confirm chevron |
| `lie_{tee,fairway,rough,sand,green}.png` | Glance lie (64×64) |
| `lie_widget_{tee,fairway,rough,sand,green}.png` | Side-on diorama ground (256×96) |
| `lie_widget_ball.png`, `lie_widget_tee_peg.png` | Diorama ball + peg |

Gate strips: `wave_C_hud_strip_x2.png`, `wave_C_lie_glance_strip_x2.png`, `wave_C_lie_widget_strip.png`, `wave_C_pad_chrome_strip_x2.png`

## Pad chrome (promoted)

Hard-pixel family for full / putt / chip:
- lanes = **fat white swing corridor** (path-of-stroke); dark rim + motion
  chevrons; family tint only as a whisper on the edge. Draw width ~64px full / ~72 putt-chip
- landmarks: start ring · top chevron · through diamond · follow ring
- coach takeaway chevrons
- tempo meter track + needle

Regen: `python art/generated/wave_C/gen_pad_chrome.py`

## Club-head drag cursor (promoted)

Pad input follows a **club head** (not yellow dot):  
`ui_club_head_{driver,wood,hybrid,iron,wedge,putter}.png` via `gen_club_heads.py`  

| Club / stroke | Head |
|---------------|------|
| Putt | putter |
| Chip / pitch | wedge |
| Driver (~260) | driver |
| 3-Wood (~235) | wood |
| Hybrid (~210) | hybrid |
| 5–9 iron | iron |
| PW / gap-sand | wedge |

`ShotRoutine` always sets `tempo_gesture.club_max_yards` so full swings pick the right head.

## Strike faces (promoted)

Hard-pixel launch-monitor faces: `strike_face_{wood,iron,putter}.png`  
via `gen_strike_faces.py` — sweet-spot marks + grooves; same layout for StrikeMap dots.

## Typeface (promoted)

**Pixel Operator** CC0 → `assets/fonts/PixelOperator.ttf`  
Theme + `UiScale.FONT`. See `art/prompts/typeface.md`.

## Wave D start screen

Moved to `art/generated/wave_D/` — kit plate + chrome promoted.

## Regen

```bash
python art/generated/wave_C/gen_hud_icons.py
python art/generated/wave_C/gen_lie_icons.py
python art/generated/wave_C/gen_pad_chrome.py
# then copy named PNGs → assets/ui/
```

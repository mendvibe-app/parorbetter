# Prompt Skill: HUD Icons

**Status**: Active  
**Depends on**: art/STYLE.md (**Pixel Kit Golf**) + `art/prompts/kit.md` (Wave C)  
**Purpose**: Club, lie, lives, aim-confirm icons, and strike-map faces.

---

## Constraints

- Flat UI, **64×64** (strike faces may be 128×96), transparent, **hard pixels**, hard 1px outline
- Style: **Pixel Kit Golf** — chunky, limited palette, no soft AA / no photo-derived blur
- Clear silhouettes at small HUD sizes (squint-test at ~32px)
- Prefer procedural / modular kit (`art/generated/wave_C/gen_hud_icons.py`, `gen_lie_icons.py`) over freeform AI one-offs
- Naming (replace in place under `assets/ui/`):
  - `club_driver.png`, `club_wood.png`, `club_hybrid.png`, `club_iron.png`, `club_wedge.png`, `club_putter.png`
  - `lie_tee.png`, `lie_fairway.png`, `lie_rough.png`, `lie_sand.png`, `lie_green.png` (64×64 glance)
  - `lie_widget_{tee,fairway,rough,sand,green}.png` (256×96 side-on strips) + `lie_widget_ball.png` / `lie_widget_tee_peg.png`
  - `life_full.png`, `life_empty.png`
  - `confirm_aim_button.png`, `confirm_aim_button_pressed.png`
  - `strike_face_wood.png`, `strike_face_iron.png`, `strike_face_putter.png`

## Master append

```
pixel art game kit UI icon, hard outline, chunky visible pixels, limited palette,
transparent background, mobile golf HUD, [specific icon]
```

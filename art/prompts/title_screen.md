# Prompt Skill: Title / Start Screen

**Status**: Live (kit redo)  
**Depends on**: `art/STYLE.md` + Wave A terrain/trees  

## Live

| | |
|--|--|
| Plate | `assets/background/title_dusk.png` (kit procedural) |
| Gen | `art/generated/wave_D/gen_title_bg.py` |
| Shell | `scenes/ui/start_screen.tscn` — square kit buttons, golfer accent |

## Constraints

- Full-bleed portrait, **no baked UI text** on the plate  
- STYLE palette + live fairway/tree/pin assets  
- Hard pixels, Filter Off (`texture_filter = 0` on rects)  
- Buttons match `game_theme` (no rounded soft chrome)

## Regen

```bash
python art/generated/wave_D/gen_title_bg.py
```

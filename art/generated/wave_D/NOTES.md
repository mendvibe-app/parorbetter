# Wave D — Start / title screen

**Date:** 2026-07-29  
**Status:** Kit plate + chrome **promoted**

## Plate

Procedural hard-pixel course plate (`gen_title_bg.py`):
- STYLE sky bands + rough ground  
- Fairway corridor stamps live `fairway_tile_a`  
- Green oval + bunker fleck + pin  
- Live canopy trees (`tree_round/dark/cluster/broad`)  
- Ship: `assets/background/title_dusk.png` (1080×1920, nearest-scaled)  

Regen: `python art/generated/wave_D/gen_title_bg.py`

## Chrome

`scenes/ui/start_screen.tscn`:
- Square kit buttons / record panel (match `game_theme` greens, hard edges)  
- Pixel Operator inherits from theme  
- Golfer address sprite under title  
- Lighter dim so plate reads  

## Brief

`art/prompts/title_screen.md`

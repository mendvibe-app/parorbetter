# Wave B — Pad golfer (kit identity)

**Date:** 2026-07-29  
**Status:** Staged live for gate — full / putt / chip sets

## Approach

PixelLab `create_character` produced **RPG/chibi** output (hair, proportions) that does not match Pixel Kit Golf pad language. Those packs are **research only**:

- `golfer_flat/` · `golfer_address_state/` · `char1/`
- IDs in `CHARACTER_IDS.txt`

**Ship path:** kit-authored modular sprites matching live address identity (cap, dotted shirt, flat blocks, hard outline, 128×192, transparent).

## Identity lock

| Part | Spec |
|------|------|
| Cap | Olive green + right brim |
| Skin | `#D4BB92` |
| Shirt | `#E8F0E8` + dark dots (chip: warm sand shirt) |
| Pants / outline / club | Near-black kit neutrals |
| Pivot | Feet planted ~y=178, facing right |

## Sets staged → `assets/ui/`

**8 keyframes** (crossfaded in `tempo_gesture._golfer_pose_pair`):
`address → takeaway → mid → late → top → early_down → impact → follow`

**Three identities** (not recolors):
| Set | Look | Used when |
|-----|------|-----------|
| Full | Upright, long club, big arc | `shot_type == full` |
| Putt | Crouched, narrow stance, short putter | `putt` |
| Chip | Open lean, warm shirt, thick wedge | `chip` **and** `pitch` |

Compare: `swing_types_address_x2.png`

Strip: `full_swing_8_strip_x2.png`  
Backup: `backup_live_golfer/`  
Contract: `scripts/shot/golfer_keyframes_check.py`

## Next

- In-game pad gate (smoother stroke read)
- Hole map widget · hole-end feel (product todos)

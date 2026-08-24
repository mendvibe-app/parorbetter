# Green true-scale density (G1 pilot)

**Why:** Post putt true-scale zoom, 128² greens showed ~40–80 screen px per texel.  
**Pilot:** `green_oval` → **768×768**, same mow-stripe motif, finer columns (period 3), kit palette from source.

## Files

| Path | Role |
|------|------|
| `green_oval_768.png` | Pilot output |
| `green_oval_128_backup.png` | Pre-G1 asset copy |
| `densify_green_oval.py` | Procedural densifier (silhouette NN + fine stripes) |
| `green_oval_768_center_8x.png` | Peep |

**Promoted to:** `assets/greens/green_oval.png` (768).

## Density check (53 ft green, 15 ft putt, z≈93)

- Was (128): ~**68** screen px / texel  
- Now (768): ~**11** screen px / texel (memo target ≤8–12)

## Playtest gate

Reload Godot project (reimport texture). Putt on a **large** oval green — stripes should read as kit mow, not Minecraft slabs.  
PixelLab 512 pro candidate optional (async); procedural is the ship path (PL max square 512 < 768 target).

## G2 (oval playtest passed)

Densified remaining shapes with `densify_green.py`:

- `green_kidney`, `green_tiered`, `green_long`, `green_island` → 768, promoted to `assets/greens/`
- 128 backups: `*_128_backup.png` in this folder

Reload Godot and spot-check each shape on a large green.

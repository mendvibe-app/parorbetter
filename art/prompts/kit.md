# Prompt Skill: PixelLab Kit Pipeline

**Status**: Active  
**Depends on**: `art/STYLE.md` (**Pixel Kit Golf**)  
**Purpose**: Map game assets to PixelLab strengths. Prefer kit tools over freeform texture clones.

---

## 1. Rule of thumb

| If you need… | Use… | Not… |
|--------------|------|------|
| Terrain fills / transitions | `create_topdown_tileset` or `create_tiles_pro` (tileset) | pixflux img2img from `ref_*.png` |
| Green / bunker / tree / cup / pin | 1-dir object / map object / cutout pixflux | Full scenic frames |
| Golfer identity + poses | `create_character` (v3) then pose variants from same ID | Independent pixflux per pose |
| HUD icons (clubs, lives) | pixen / pixflux set + shared style | Unrelated one-offs |
| Tiny ball / FX | cheap pixflux | Pro for every variant |

**Cost:** derisk cheap; one pro tileset for the course spine is OK.

---

## 2. Wave order

0. STYLE + this file locked  
A. Course kit (tileset fills + core props)  
B. Character (identity → address/impact → rest)  
C. UI set (+ typeface readability)  
D. Polish — **start/title screen kit redo**, optional Wang integration  
   (title: `art/prompts/title_screen.md`)  

Outputs → `art/generated/wave_A/` etc. Promote to `assets/` only after wave gate.

---

## 3. Course kit (Wave A)

### Terrain

1. Generate topdown tileset: e.g. rough (lower) → fairway (upper); optional water→rough.
2. Extract anonymous **fill** tiles (no edge-only pieces for Phase 1 stamps).
3. Nearest-neighbor to **64×64** if source is 16/32.
4. Ship names: `fairway_tile_a`, `rough_tile_a`, `rough_tile_b` (darker variant), `water_tile`.
5. **Mandatory** 2×2 tile test — reject landmark clumps / wallpaper motifs.

Prompt language: golf course grass, mowed fairway vs longer rough, pond water — **kit-coherent**, not “clone this PNG.”

**Aerial scale (engine: ~64px tile / 300 world-px):**  
- Fairway: **many thin** mow stripes (~16 dark/light pairs per 64px), jagged edges, noise inside bands — never 4–6 fat bars.  
- Rough: fine 1–2px grain/tips, not large camo blobs.  
- Water: small-cell caustics.  
If a generator only outputs fat features, author denser fills procedurally (see `art/generated/wave_A/scale2_*`) rather than accepting wrong scale.

### Props

Cutouts with transparency: green oval (+ other shapes as needed), bunker blob/crescent, trees, cup, pin_flag, water pond/creek.  
Same palette language as fills. Silhouette-first.

---

## 4. Character (Wave B)

1. **Pad golfer is kit-authored modular sprites** (flat blocks matching STYLE). PL `create_character` tends RPG/chibi — research only unless style-locked to kit base.
2. Lock identity (cap, dotted shirt, pants, pivot) before multi-pose expansion.
3. Pad frames: **128×192**, facing right, transparent BG (see `golfer.md`).
4. Full / putt / chip: **same character**; club length differs (putt short, chip wedge, full long).

Do not freeform a new person per pose.

---

## 5. UI (Wave C)

Generate as a **set** (shared style/seed language): clubs, lives, strike faces, landmarks.  
Lie widgets: leave until course palette locked.

---

## 6. Engine integration (Phase 1)

- Keep `hole_controller.gd` preloads and stamp model.
- Swap PNGs under `assets/` after gate — **no gameplay code** for Wave A/B.
- Wang / TileMap = Phase 2 only if fills alone seam badly.

---

## 7. Master kit prompt fragment

```
pixel art game kit, top-down mobile golf, chunky pixels, limited palette,
hard edges, coherent tileset style, high value contrast, [subject]
```

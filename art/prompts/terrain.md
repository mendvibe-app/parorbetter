# Prompt Skill: Course Terrain & Props

**Status**: Active  
**Depends on**: `art/STYLE.md` (**Pixel Kit Golf**) + `art/prompts/kit.md`  
**Purpose**: Seamless terrain fills and course props for `hole_controller.gd`.

---

## 1. Context

Top-down course surfaces and props. Strong fairway / rough / bunker / water distinction is mandatory.

**Source of truth:** Pixel Kit Golf + PixelLab kit tools — not pixel-matching `art/references/`.  
Refs may inform value/hue only.

---

## 2. Technical Constraints

- Style: Pixel Kit Golf (chunky pixels, hard edges, limited palette)
- View: Top-down (pin_flag: slight side OK)
- Fills: **64×64**, seamless X/Y (upscale NN from PL 16/32 if needed)
- Props: 64×64 or 128×128; transparency outside silhouette
- Palette: STYLE.md anchors
- Naming (replace in place):
  - `fairway_tile_a.png`, `rough_tile_a.png`, `rough_tile_b.png`, `water_tile.png`
  - `green_oval.png`, `green_kidney.png`, `green_tiered.png`, `green_long.png`, `green_island.png`
  - `bunker_blob.png`, `bunker_crescent.png`, `bunker_cluster.png`
  - `water_creek.png`, `water_pond.png`
  - `tree_round.png`, `tree_pine.png`, `tree_cluster.png`
  - `cup.png`, `pin_flag.png`

---

## 3. Guidance

| Surface | Look | Prefer tool |
|---------|------|-------------|
| Fairway | Lighter greens; optional soft mow banding; anonymous | Topdown tileset upper / fill extract |
| Rough | Darker, coarser; b denser | Tileset lower / darker variant |
| Water | Mid–deep blue; simple caustic/ripple | Tileset or fill extract |
| Sand bunkers | Warm grain inside silhouette | Prop cutout + sand fill |
| Greens | Quieter than rough; clear shape | Prop / silhouette |
| Trees / cup / pin | Simple readable cutouts | 1-dir object / pixflux cutout |

**Reject:** repeating landmark clumps, soft AA, photo-texture mush, “only good in isolation.”

---

## 4. Master Prompt Addition

```
pixel art game kit, top-down mobile golf, chunky pixels, limited palette,
hard edges, seamless if fill tile, high value contrast, [subject]
```

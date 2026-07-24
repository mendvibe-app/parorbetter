# Prompt Skill: Course Terrain & Props

**Status**: Active  
**Depends on**: art/STYLE.md (**Crunchy Pixel**) + art/references/  
**Purpose**: Seamless terrain tiles and course props (greens, bunkers, trees, cup, pin).

---

## 1. Context

Top-down course surfaces and props used by `hole_controller.gd`. Strong fairway / rough / bunker / water distinction is mandatory. Match playtest references in `art/references/`.

---

## 2. Technical Constraints

- Style: Crunchy Pixel (visible pixels, dither OK, no AA)
- View: Top-down (except pin_flag: slight side orthographic OK)
- Tiles: **64×64**, seamless on X and Y
- Props: 64×64 or 128×128; bunker/green silhouettes with transparency outside shape
- Palette: STYLE.md course anchors (+ ref neighbors)
- Naming (replace in place):
  - `fairway_tile_a.png`, `rough_tile_a.png`, `rough_tile_b.png`, `water_tile.png`
  - `green_oval.png`, `green_kidney.png`, `green_tiered.png`, `green_long.png`, `green_island.png`
  - `bunker_blob.png`, `bunker_crescent.png`, `bunker_cluster.png`
  - `water_creek.png`, `water_pond.png` (carry / edge water props)
  - `tree_round.png`, `tree_pine.png`, `tree_cluster.png`
  - `cup.png`, `pin_flag.png`

---

## 3. Guidance

- Fairway → `ref_fairway.png`: vertical mow stripes, jagged edges, noisy dither inside bands
- Rough → `ref_rough_a.png` / `ref_rough_b.png`: tuft clumps, dark bases, light tips; b darker
- Water → `ref_water.png`: coarse caustic lattice over dark pools
- Sand bunkers → `ref_sand.png`: diagonal ripple fill inside silhouette
- Greens: quieter fairway cousin (striped/noise), not tufts
- Trees: simple crunchy canopy silhouettes

---

## 4. Master Prompt Addition

crunchy true pixel, visible pixels, dithered, seamless if tile, match art/references, top-down golf [subject]

# Wave A probe notes

**Date:** 2026-07-29  
**Status:** Research / gate — **not promoted** to `assets/`

## Jobs

| Job | ID | Result |
|-----|-----|--------|
| `create_tiles_pro` square fills | `2a67f923-bd16-44b7-8393-b628ca047630` | **Winner for Phase 1 stamps** — 4 materials × 4 variants @ 64px |
| `create_topdown_tileset` rough→fairway | `9ab6d412-9023-4f78-857e-7282ab2a0502` | Strong **transition/island** kit; pure fills neon/flat; keep for Phase 2 Wang |

Base tile IDs (Wang chain):  
- lower rough: `a9fbac5e-37d8-48a3-8f69-ba65e7b8bd83`  
- upper fairway: `cdec1d41-93c5-4c55-bfdf-be661fb33e5c`

## Phase 1 ship candidates (pro pack)

| Ship name | Source index | Look |
|-----------|--------------|------|
| `fairway_tile_a.png` | v0 | Vertical mow stripes |
| `rough_tile_a.png` | v4 | Olive mottled |
| `rough_tile_b.png` | v8 | Dark dense |
| `water_tile.png` | v12 | Blocky caustics |

Alts: `*_alt.png` (v1/5/9/13).

## Learning

1. **Round hole fit:** `create_tiles_pro` + numbered materials + `square_topdown` + `tile_view_angle=90` + `segmentation` → usable seamless fills on first try.
2. **Wang tileset** is not a drop-in for current stamp fills; it wants elevated terrain transitions. Great later, wrong primary tool for “four PNG stamps.”
3. Stop pixflux-from-ref for terrain.

## Scale lesson (from in-game screenshots)

User feedback: PL pro fills felt wrong because of **aerial feature frequency**, not just palette.

- Engine: `texture_scale = tile_w / 300` → ~one 64px tile per 300 world-px.
- Fairway ~200 world wide → only ~half a tile of UV across the strip.
- PL fairway had **~5 fat stripes / 64px** → ~2–3 mow bands across whole fairway (“5 mowers wide”).
- PL rough had **large camo clumps** → reads as giant pixels/bushes from altitude.

**Fix staged (procedural `scale3_*`):** ~2px half-bands (~16 pairs/tile), fine rough flecks, small-cell water. Documented in STYLE.md §3 aerial scale.

**User gate (2026-07-29): scale PASS** — “scale is much better and we can work with this now.”

Canonical fills (also live in `assets/terrain/`):
- `fairway_tile_a.png` / `rough_tile_a.png` / `rough_tile_b.png` / `water_tile.png`
- (source: `scale3_*`)

## Props pack (2026-07-29)

**Approach:** Keep live **silhouettes** (lie/alpha) for greens/bunkers; refill interiors with aerial-scale kit textures. Trees/cup/pin/water props authored procedural to match density.

| Asset | Method |
|-------|--------|
| `green_*.png` | Silhouette preserve + dense ~2px mow fill + fringe |
| `bunker_*.png` | Silhouette + fine diagonal sand grain |
| `tree_*` | New simple canopies, fine flecks |
| `cup` / `pin_flag` | Simple kit icons |
| `water_pond` / `water_creek` | Fine caustic bands |

Outputs: `art/generated/wave_A/props/` → staged live (backup: `backup_live_props/`).

## Tree pass D (2026-07-29)

Replaced lollipops with aerial canopies. First density was **hedge-wall** (user screenshot `assets/ui/new_trees.png`).

**Fix:** 8 variety sprites + sparse scatter (~42% skip side, y step 95–165, mostly single canopy).

**Later:** tee box prop/surface (noted — still missing).

## Trees as hazards (2026-07-29)

Trees are hole-design specs (`kind: tree` in `hazards`), not belt decoration:
- Generator `_build_trees` by archetype density (open long_bear vs chute/parkland)
- Roles: edge line, landing clump, greenside
- Collision group `tree` — stops flight/roll → lie **Trees** (punch-out clubs, short carry)
- Still later: tee box

## Tee box (2026-07-29)

`_add_tee_box` — short-grass pad at `_tee_pos` (`tee_tile.png` + group `tee`). Replaces yellow debug disc. Classify lie returns **Tee** on pad.

## Next

- Playtest tee + trees
- Wave B character

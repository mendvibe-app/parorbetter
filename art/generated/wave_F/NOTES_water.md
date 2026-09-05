# Wave F — water tile + shoreline (review only)

**Date:** 2026-09-01  
**Status:** Review — **not promoted**. Output lives only on the box under `/workspace/parorbetter-art/wave_F_water/`.  
**Gate:** After Wave F 256 fairway/rough, next ranked miss is water + shoreline stretch.  
**Tool:** Python/Pillow procedural kit (no AI image generator, no AA, Filter-Off language).  
**Stamp:** Island fill authored **256×256 @ 300** to match Wave F fills (~85 texels / 100 world-px). Live island uses `tile_px = 260` in `_place_island_ring`.

---

## What we measured on live

### `water_tile.png` (64×64, 7 colors, opaque)

| Hex | Role | Live % |
|-----|------|--------|
| `#457A9C` | STYLE mid | 22.07% |
| `#3C667C` | STYLE dark pool | 21.83% |
| `#86C2CD` | STYLE highlight | 17.46% |
| `#5D8FA0` | 1-step (mid/hi) | 11.28% |
| `#2A4A5C` | STYLE deep | 11.04% |
| `#629AB2` | 1-step (mid/hi) | 10.82% |
| `#53808E` | 1-step (pool/mid) | 5.52% |

- Diagonal **twill / hatch** (↘), horiz runs 1px 2577 / 2px 755 / 3px 3. Value masses ~4 px half-bands.
- `#E8F4F6` (STYLE highlight 2) is **not** on live. Not used here (14–56 px white squares at z=12, same failure as rough lime).
- Live wrap edges are **not** identical (mismatch X=35 Y=33 of 64) — hatch does not toroidally close.
- **Island:** Polygon2D, `texture_scale = width/260`, `TEXTURE_REPEAT_ENABLED`. 64@260 at z=12 ≈ **48.8 px/texel**. A 4 px band → ~195 px puzzle pieces.
- **Shoreline (the miss):** `_add_water_sprite` stretches the **same 64×64** to `(segment_length * 1.05, SHORE_WIDTH=52)`. A ~480 world-px Cape panel → scale X=7.50 Y=0.812. At z=12 a texel is **90×9.8 screen-px** (anisotropic smear).

### `water_pond.png` (96×80, 5 colors, cutout)

Opaque 5477 / 7680 (71.3%), alpha 0/255 only. Schematic hatched oval, bbox 93×77. World span `size*1.6 × size*1.2` with size 40–58 → **~64–93 × 48–70**.

### `water_creek.png` (128×48, 3 colors, cutout)

Opaque 2748 / 6144 (**44.7%**). Wavy band, thickness ~19–23 of 48. World: carry `fairway*2+80 × 22–36`, diagonal slightly narrower.

---

## What Wave F water authored

Did **not** nearest-upscale the 64 (that keeps 8 fat diagonal pairs across 256). Authored at native size with the **same ↘ twill at 4× world frequency**: 64 pairs of irregular 1–3 px half-bands on 256 (width hist from seed `{1: 32, 2: 64, 3: 32}`).

### Island fill `water_tile.png` — 256×256 seamless X/Y

- Palette **only** STYLE water + live 1-steps: `#86C2CD` `#457A9C` `#3C667C` `#2A4A5C` `#53808E` `#5D8FA0` `#629AB2`.
- No `#E8F4F6`. No other hexes. No AA.
- Mix (percent of 65536 px):
  - `#457A9C` 15327 (23.39%)
  - `#3C667C` 14332 (21.87%)
  - `#86C2CD` 11520 (17.58%)
  - `#5D8FA0` 7419 (11.32%)
  - `#2A4A5C` 6923 (10.56%)
  - `#629AB2` 6219 (9.49%)
  - `#53808E` 3796 (5.79%)
- Unique colors: **7**. Extra/AA: **none**.
- Wrap luma-delta (edge − interior): (-0.23, -0.9).
- Wrap edge mismatch (not required to be 0 — nicks; torus by construction): X=208 Y=206.
- HI `#86C2CD` components (4-connected, wrap): n=7515 max=13 px.
- Horiz runs: {1: 44716, 2: 7919, 3: 1284, 4: 202, 5: 49, 6: 7, 7: 5}. Vert runs: {1: 44691, 2: 7911, 3: 1321, 4: 194, 5: 41, 6: 12, 7: 1}.

**Stamp:** prefer **256@300** (~85 texels / 100 world-px, 14.1 px/texel at z=12). Live island is 260. A Phase-1 PNG swap into 260 would be ~98 texels / 100 world-px (12.2 px/texel at z=12) — slightly denser, still tiles via Polygon2D.

### Shore strip `water_shore.png` — 512×64, seamless **X**

- Same twill language, period 512 (128 pairs, mean 2 px). Y does not wrap (it is a bank, not a fill).
- Designed so **64 texels → SHORE_WIDTH=52 world-px** (texel = 0.8125 world-px square).
- X repeat period = 416.0 world-px.
- Mix:
  - `#457A9C` 7553 (23.05%)
  - `#3C667C` 7412 (22.62%)
  - `#86C2CD` 5481 (16.73%)
  - `#5D8FA0` 3701 (11.29%)
  - `#2A4A5C` 3598 (10.98%)
  - `#629AB2` 3032 (9.25%)
  - `#53808E` 1991 (6.08%)
- Unique colors: **7**. Extra/AA: **none**.
- X-wrap by construction (band array period 512, `u=(x+y)%512`).

**Engine note:** today's `_add_water_sprite` **stretches**. This strip only kills the smear if the sprite **repeats** along hole length (or a Polygon2D with `texture_repeat` and scale `height/52`). PNG-swapping `water_tile` 256 into the current Sprite2D still smears, just with finer texels.

### Pond `water_pond.png` — 192×160 cutout

- Hard ellipse (2× live 96×80), 1 px hash nicks, alpha 0/255 only.
- Interior = same 1–3 px twill (period 192). World size **unchanged** (~80×60 mid).
- Opaque 22558 / 30720 (73.4%). Partial alpha: 0. Unique colors: **7**. Extra: **none**.

### Creek `water_creek.png` — 384×96 cutout

- Long thin wave, thickness ~37–47 on 96. Target ~45% opaque like live (paint gate).
- Opaque 16578 / 36864 (45.0%). Partial alpha: 0. Unique colors: **7**. Extra: **none**.
- World: still a long thin band (carry ~220×28). Density only.

---

## Why it should read better at z=12

| | Live 64@260 island | Wave F 256@300 island | Live shore stretch | Wave F shore tile |
|--|--------------------|------------------------|--------------------|-------------------|
| Texels / 100 world-px | ~25 | ~85 | X: 13.3  Y: 123 | ~123 |
| Screen-px / texel @ z=1.24 | 5.04 | 1.45 | X 9.3 | 1.01 |
| Screen-px / texel @ z=12 | **48.8** | **14.1** | **90×9.8** | **9.8 square** |
| Screen-px / texel @ z=130 | 528 | 152 | 975×106 | 106 |
| Half-bands / 300 world-px | ~8 fat | ~64 thin | 8 smeared | ~185 |

Green-book is the money shot: live island hatch becomes ~195 px stripes; Wave F still shows 1–3 px twill at ~14 px/texel. Live shore is a melted 64. New shore keeps square texels and **repeats**.

---

## What we did NOT change

- Locked Pixel Kit Golf language (chunky hard pixels, limited palette, no photo water, no Filter On, no AA).
- Did not invent a new look — same ↘ twill as live, 4× frequency, same 7 hexes (STYLE + live 1-steps).
- Did not use `#E8F4F6`.
- Live island `tile_px = 260` and `GROUND_TILE_PX = 300` in engine. Did not edit `hole_controller.gd`.
- Shore still **stretch** in live engine until a repeat pass. This folder is the strip to tile.
- Pond/creek world-size language (still sprites scaled to the same spans). Paint-gate alpha still binary.
- Fairway / rough / green / bunker / tee / trees / UI / golfer.
- Live files on disk and anything under `assets/`.
- No git commit. No writes to the user computer.
- Did not upscale 64→256.

---

## Leftover risk (putt 130)

256@300 still yields **~152 screen-px per texel** at putt-cam 130 (same as Wave F fills). A 2 px caustic band is ~305 px. Shore at 64→52 is **~106 px/texel** — 4× finer than live island, still LEGO if you putt next to water.

PNG-swap of the 256 fill into island 260 does **not** fix Cape shoreline; that path is Sprite2D stretch. Next engine lever is tiling `water_shore` (or a Polygon2D) along hole length.

If putt-cam water still feels like slabs after this gate, the next art lever is 512 fill / 128-tall shore — not more palette.

---

## Files

| File | Role |
|------|------|
| `water_tile.png` | 256×256 seamless island fill |
| `water_shore.png` | 512×64 tileable strip (seamless X) |
| `water_pond.png` | 192×160 cutout |
| `water_creek.png` | 384×96 cutout |
| `tile_1x.png` | native + 4× NN trap + 2×2 wrap + cutouts |
| `sim_tee.png` | in-engine z=1.24 island + shoreline |
| `sim_greenbook.png` | in-engine z=12 money shot |
| `sim_stretch.png` | live stretch vs new tiled repeat at hole-length |
| `gen_wave_F_water.py` | recipe (reproducible, seeded) |

Seeds: fill `20260931`, shore `20260941`, pond `20260951`, creek `20260961`.

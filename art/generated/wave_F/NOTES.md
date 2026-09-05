# Wave F — fairway / rough 256 fills (review only)

**Date:** 2026-09-01  
**Status:** Review — **not promoted**. Output lives only on the box under `/workspace/parorbetter-art/wave_F/`.  
**Gate:** Matthew + Mobile Bob Ross approved starting rough + fairway tiles for review.  
**Tool:** Python/Pillow procedural kit (no AI image generator, no AA, Filter-Off language).  
**Stamp:** `GROUND_TILE_PX = 300` (one tile per 300 world-px). Ship **256×256**.

Greens already went 128→768. This is the fill equivalent: 64→256 (4× texel density at the same 300 stamp → ~85 texels / 100 world-px, ~14 screen-px/texel at z=12).

---

## What we measured on live 64

### `fairway_tile_a.png` (64×64, 4 colors, opaque)

| Hex | Role | Live % |
|-----|------|--------|
| `#546835` | mid | 45.70% |
| `#3D5228` | dark | 36.47% |
| `#647E3D` | light | 13.50% |
| `#4A5F2F` | extra (1-step between mid/dark) | 4.32% |

- **Exactly 16 luma pairs** of **2+2 columns** (dark, dark, mid, mid) wrapping the tile.
- Horizontal runs: 1px 1571 / 2px 870 / 3px 182 (mean 1.53, max 7). Vertical mean 2.06.
- Language: vertical mow, jagged 1–3px grain *inside* 2-column half-bands. Anonymous. No landmark clump.

### `rough_tile_a.png` (64×64, 4 colors)

| Hex | Role | Live % | Components |
|-----|------|--------|------------|
| `#49573E` | base | 82.74% | — |
| `#1A2418` | stem | 8.15% | 283, mostly 1px |
| `#3C4C36` | 1-step dark | 7.28% | 266, mostly 1px |
| `#7A9A4A` | **lime highlight** | 1.83% | 72 (69×1px, 3×2px) |

Lime is a ~40–55 luma jump off the base. At green-book z≈12 a live texel is **~56 screen-px**, so those 1px limes become Minecraft squares (see device screenshot + `sim_greenbook.png`).

### `rough_tile_b.png` (64×64, 3 colors)

| Hex | Role | Live % |
|-----|------|--------|
| `#30412E` | base | 86.91% |
| `#1A2418` | stem | 10.18% |
| `#7A9A4A` | lime | 2.91% (117 comps, almost all 1px) |

Denser/darker than A. Same lime problem, worse because the jump off `#30412E` is even larger.

Live 64@300 at z=12 ≈ **56 px/texel**. At putt 130 ≈ **609 px/texel**. That is the failure mode, not the palette count.

---

## What Wave F authored (256×256)

Did **not** nearest-upscale the 64s (that would turn 2px half-bands into 8px fat bars and keep 16 pairs stretched across 256). Authored at native 256 with the **same language at 4× frequency**.

### Fairway `fairway_tile_a.png`

- Palette **only**: `#647E3D` `#546835` `#3D5228` `#4A5F2F` (live extra kept).
- **64 authored pairs** of irregular 1–3 px half-bands (width hist `{1: 32, 2: 64, 3: 32}`). Luma-crossing pairs measured on the image: **64**.
- Mix after noise (percent of 65536 px):
  - `#546835` 31743 (48.44%)
  - `#3D5228` 25703 (39.22%)
  - `#647E3D` 6056 (9.24%)
  - `#4A5F2F` 2034 (3.10%)
- Vertical persistence via wrap-safe 3-tap hash (short blades, not photo grass).
- Sparse ±1 px edge nicks so bands are not a barcode; Y wrap is hashed (no flattened belt).
- Unique colors: **4**. Extra/AA: **none**.

### Rough A `rough_tile_a.png` (first-cut / lighter)

- Base `#49573E`, dark `#30412E`, stem `#1A2418`.
- Highlight is **not** `#7A9A4A`. 1-step neighbors only: `#5A6A48` and `#3C4C36`.
- Sparse 1px flecks, rare 2px **vertical** tips. Neighbor-reject on highlight so no 2×2 lime-like blocks.
- Mix:
  - `#49573E` 52926 (80.76%)
  - `#1A2418` 5626 (8.58%)
  - `#3C4C36` 3769 (5.75%)
  - `#30412E` 2639 (4.03%)
  - `#5A6A48` 576 (0.88%)
- Highlight comps: n=576 max=1 px=576
- Stem comps: n=5130 max=4 px=5626
- Unique colors: **5**. Extra/AA: **none**.

### Rough B `rough_tile_b.png` (base rough, darker/denser)

- Base `#30412E`, stem `#1A2418`, same quiet highlights (no lime).
- Denser stem than A, still 1px grain — not bushes from altitude.
- Mix:
  - `#30412E` 55687 (84.97%)
  - `#1A2418` 7046 (10.75%)
  - `#3C4C36` 2465 (3.76%)
  - `#5A6A48` 338 (0.52%)
- Highlight comps: n=338 max=1 px=338
- Stem comps: n=6488 max=4 px=7046
- Unique colors: **4**. Extra/AA: **none**.

Wrap luma-delta (edge − interior; ~0 is good):  
fairway (4.13, 3.90) · rough A (0.46, -0.78) · rough B (0.41, 0.18).

---

## Why it should read better at z=12

| | Live 64@300 | Wave F 256@300 |
|--|-------------|----------------|
| Texels / 100 world-px | ~21 | ~85 |
| Screen-px / texel @ z=1.24 | 5.81 | 1.45 |
| Screen-px / texel @ z=12 | **56.3** | **14.1** |
| Screen-px / texel @ z=36 | 169 | 42.2 |
| Screen-px / texel @ z=130 | **609** | **152** |
| Fairway pairs / 300 world-px | 16 | ~64 |
| Pairs across a 160-wide fairway | ~8.5 fat | ~34 thin |
| Rough highlight | lime `#7A9A4A` @ 56 px | 1-step `#5A6A48` @ 14 px |

Green-book is the money shot: live mow becomes 8 wide slabs; Wave F still shows many 1–3 px half-bands at 14 px/texel. Lime squares collapse to quiet 14 px grain.

---

## What we did NOT change

- Locked Pixel Kit Golf language (chunky hard pixels, limited palette, no photo grass, no Filter On, no AA).
- Stamp model (`one tile / 300 world-px`). Did not ask for engine `GROUND_TILE_PX` changes.
- Green / bunker / water / tee / trees / UI / golfer.
- Live files on disk and anything under `assets/`.
- No git commit. No writes to the user computer.
- Did not introduce new palette families. Did not keep `#7A9A4A` on the new roughs (that *is* a deliberate 1-step substitution; STYLE still lists lime as the readability anchor — Wave F treats it as unusable at zoom).
- Did not upscale 64→256.

---

## Leftover risk (putt 130)

256@300 still yields **~152 screen-px per texel** at putt-cam 130. You will see individual fairway half-bands as ~150–450 px slabs and the occasional stem/highlight as a large hard square. That is **4× finer than live** (~609 px/texel) so the apron is readable as “mow vs first-cut” rather than four giant pixels, but it is **not** green-768 density. If putt-cam still feels like LEGO after this gate, the next lever is a 512 (or green-like 768) fill **or** a higher-res apron-only stamp — not more palette.

---

## Files

| File | Role |
|------|------|
| `fairway_tile_a.png` | 256×256 master |
| `rough_tile_a.png` | 256×256 master |
| `rough_tile_b.png` | 256×256 master |
| `tile_1x.png` | native + 4× NN trap + 2×2 wrap |
| `sim_tee.png` | in-engine z=1.24 strip |
| `sim_greenbook.png` | in-engine z=12 + lime crop |
| `sim_putt_apron.png` | in-engine z=36 and z=130 apron |
| `gen_wave_F.py` | recipe (reproducible, seeded) |

Seeds: fairway `20260901`, rough A `20260911`, rough B `20260921`.

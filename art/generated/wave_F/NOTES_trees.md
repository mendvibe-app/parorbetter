# Wave F — tree canopies 4× (review only)

**Date:** 2026-09-01
**Status:** Review — **not promoted**. Output lives only on the box under `/workspace/parorbetter-art/wave_F_trees/`.
**Gate:** Matthew said water looking good, trees next. Art lead: Mobile Bob Ross. Scale polish for punch-in zoom.
**Tool:** Python/Pillow procedural kit (no AI image generator, no AA, Filter-Off language).
**Ship names unchanged:** `tree_round.png` `tree_pine.png` `tree_cluster.png` `tree_oak.png` `tree_airy.png` `tree_dark.png` `tree_broad.png` `tree_tall.png`.

---

## Engine scale (quoted — do not change world radius)

`hole_controller.gd` `_add_tree`:

```
const TREE_TEXTURES := [
    preload("res://assets/background/tree_round.png"),
    preload("res://assets/background/tree_pine.png"),
    preload("res://assets/background/tree_cluster.png"),
    preload("res://assets/background/tree_oak.png"),
    preload("res://assets/background/tree_airy.png"),
    preload("res://assets/background/tree_dark.png"),
    preload("res://assets/background/tree_broad.png"),
    preload("res://assets/background/tree_tall.png"),
]
var max_dim := maxf(float(tex.get_width()), float(tex.get_height()))
spr.scale = Vector2.ONE * (radius * 2.15 / max_dim)
_trees.append({"c": center, "r": radius * 0.72, "canopy_h": canopy})  # collision
```

`hole_generator.gd` `_build_trees` `size` (then `r := size * randf_range(0.72, 1.05)`):

| role | size |
|------|------|
| edge | `lerpf(26, 36, dens)` |
| opposite edge | `28` |
| landing | `lerpf(30, 42, dens)` |
| greenside | `lerpf(24, 34, dens)` |
| chute | `30` |

So `size` ≈ **24–42**. Visual world diameter = `r × 2.15` ≈ **52–90** if r≈size (with jitter, Ø ≈ 37–95). Collision uses `r × 0.72`, not the sprite. **Do not enlarge world radius.** A 4× texture has 4× `max_dim` → Sprite2D.scale becomes ¼ → **same world Ø, denser flecks.**

Bunker sprites use `radius * 2.3 / max_dim` — trees are **2.15**. Not this wave.

---

## What we measured on live

All eight live files: hard alpha **0/255 only**, **5 RGB**, **no `#7A9A4A`**, no trunk, no lollipop. Top-down canopy masses. Interior holes are mostly **1px** (airy swiss-cheese). Outline is 1px dark/shadow on solid variants; airy flecks to the edge.

### `tree_round.png` (96×96, 5 colors, opaque 3814 / 9216 = 41.4%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#284824` | 44.23% | dark |
| `#385C30` | 26.90% | mid |
| `#4A723C` | 15.94% | light |
| `#182C14` | 9.20% | shadow |
| `#5C8848` | 3.72% | hi |

- bbox 79×75 aspect 1.053. Interior holes 182 px / 88 comps (max 17). Lime `#7A9A4A` count: **0**.

### `tree_pine.png` (96×96, 5 colors, opaque 4219 / 9216 = 45.8%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#1A3218` | 46.48% | dark |
| `#244222` | 25.88% | mid |
| `#32542C` | 14.41% | light |
| `#122412` | 10.48% | shadow |
| `#406636` | 2.75% | hi |

- bbox 67×96 aspect 0.698. Interior holes 214 px / 130 comps (max 7). Lime `#7A9A4A` count: **0**.

### `tree_cluster.png` (112×112, 5 colors, opaque 7214 / 12544 = 57.5%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#284824` | 42.11% | dark |
| `#385C30` | 27.18% | mid |
| `#4A723C` | 17.42% | light |
| `#182C14` | 8.47% | shadow |
| `#5C8848` | 4.81% | hi |

- bbox 98×112 aspect 0.875. Interior holes 271 px / 147 comps (max 10). Lime `#7A9A4A` count: **0**.

### `tree_oak.png` (104×104, 5 colors, opaque 4512 / 10816 = 41.7%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#2C3C1C` | 42.13% | dark |
| `#3C5028` | 28.12% | mid |
| `#506634` | 17.35% | light |
| `#1C2814` | 8.00% | shadow |
| `#647A40` | 4.39% | hi |

- bbox 88×78 aspect 1.128. Interior holes 179 px / 92 comps (max 10). Lime `#7A9A4A` count: **0**.

### `tree_airy.png` (96×96, 5 colors, opaque 4864 / 9216 = 52.8%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#345224` | 35.79% | dark |
| `#486C32` | 31.31% | mid |
| `#5E8640` | 19.82% | light |
| `#223818` | 7.20% | shadow |
| `#729C50` | 5.88% | hi **lime-like — swapped on new** |

- bbox 79×93 aspect 0.849. Interior holes 478 px / 356 comps (max 6). Lime `#7A9A4A` count: **0**.

### `tree_dark.png` (88×88, 5 colors, opaque 3830 / 7744 = 49.5%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#1A3218` | 45.43% | dark |
| `#244222` | 26.21% | mid |
| `#32542C` | 15.22% | light |
| `#122412` | 9.35% | shadow |
| `#406636` | 3.79% | hi |

- bbox 74×84 aspect 0.881. Interior holes 133 px / 79 comps (max 8). Lime `#7A9A4A` count: **0**.

### `tree_broad.png` (110×110, 5 colors, opaque 4021 / 12100 = 33.2%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#345224` | 43.62% | dark |
| `#486C32` | 26.51% | mid |
| `#5E8640` | 16.31% | light |
| `#223818` | 10.10% | shadow |
| `#729C50` | 3.46% | hi **lime-like — swapped on new** |

- bbox 88×75 aspect 1.173. Interior holes 176 px / 92 comps (max 10). Lime `#7A9A4A` count: **0**.

### `tree_tall.png` (90×90, 5 colors, opaque 4826 / 8100 = 59.6%)

| Hex | Live opaque % | role guess |
|-----|---------------|------------|
| `#1E3A2E` | 40.45% | dark |
| `#2A4E3C` | 29.94% | mid |
| `#38624A` | 17.45% | light |
| `#142820` | 8.37% | shadow |
| `#487858` | 3.79% | hi |

- bbox 70×90 aspect 0.778. Interior holes 184 px / 104 comps (max 11). Lime `#7A9A4A` count: **0**.

Live flecks are already 1px-class, but at typical r=32 a 96px canopy is `scale = 32×2.15/96 = 0.717` world-px/texel. At green-book **z=12** that is **~8.6 screen-px/texel** — sandy 8px blobs. Tee z=1.24 is already ~0.89 px/texel (fine).

---

## What Wave F authored

Did **not** nearest-upscale the RGB (that keeps fat flecks). NN-upscaled the **filled silhouette**, jittered the 4px stairs back to 1px nicks, re-scattered interior holes as 1–2px, then filled with high-frequency flecks biased by the live color lobes (so oak stays oak, pine stays oval, cluster stays multi-blob). No 16px value lattice (a first cut of square cells read as camo bushes from tee).

| file | live | new | unique | hi max px | opaque % |
|------|------|-----|--------|-----------|----------|
| `tree_round.png` | 96×96 | 384×384 | 5 | 1 | 41.4 |
| `tree_pine.png` | 96×96 | 384×384 | 5 | 1 | 45.8 |
| `tree_cluster.png` | 112×112 | 448×448 | 5 | 1 | 57.5 |
| `tree_oak.png` | 104×104 | 416×416 | 5 | 1 | 41.7 |
| `tree_airy.png` | 96×96 | 384×384 | 5 | 1 | 52.7 |
| `tree_dark.png` | 88×88 | 352×352 | 5 | 1 | 49.4 |
| `tree_broad.png` | 110×110 | 440×440 | 5 | 1 | 33.2 |
| `tree_tall.png` | 90×90 | 360×360 | 5 | 1 | 59.6 |

### `tree_round.png`

| Hex | new % |
|-----|-------|
| `#284824` | 41.25% |
| `#385C30` | 34.85% |
| `#4A723C` | 17.01% |
| `#182C14` | 6.18% |
| `#5C8848` | 0.73% |

- unique **5**. extra/AA/lime: none. hi comps n=443 max=1 mean=1.00.

### `tree_pine.png`

| Hex | new % |
|-----|-------|
| `#1A3218` | 43.23% |
| `#244222` | 34.20% |
| `#32542C` | 15.24% |
| `#122412` | 6.72% |
| `#406636` | 0.60% |

- unique **5**. extra/AA/lime: none. hi comps n=404 max=1 mean=1.00.

### `tree_cluster.png`

| Hex | new % |
|-----|-------|
| `#284824` | 38.26% |
| `#385C30` | 36.12% |
| `#4A723C` | 19.17% |
| `#182C14` | 5.59% |
| `#5C8848` | 0.87% |

- unique **5**. extra/AA/lime: none. hi comps n=1008 max=1 mean=1.00.

### `tree_oak.png`

| Hex | new % |
|-----|-------|
| `#2C3C1C` | 38.56% |
| `#3C5028` | 36.50% |
| `#506634` | 18.77% |
| `#1C2814` | 5.35% |
| `#647A40` | 0.83% |

- unique **5**. extra/AA/lime: none. hi comps n=599 max=1 mean=1.00.

### `tree_airy.png`

| Hex | new % |
|-----|-------|
| `#486C32` | 44.37% |
| `#5E8640` | 26.43% |
| `#345224` | 25.80% |
| `#223818` | 2.12% |
| `#6A8C4C` | 1.28% |

- unique **5**. extra/AA/lime: none. hi comps n=995 max=1 mean=1.00. Highlight `#729C50` replaced with `#6A8C4C` (1-step, not `#7A9A4A`).

### `tree_dark.png`

| Hex | new % |
|-----|-------|
| `#1A3218` | 39.85% |
| `#244222` | 36.51% |
| `#32542C` | 17.38% |
| `#122412` | 5.49% |
| `#406636` | 0.77% |

- unique **5**. extra/AA/lime: none. hi comps n=472 max=1 mean=1.00.

### `tree_broad.png`

| Hex | new % |
|-----|-------|
| `#345224` | 41.52% |
| `#486C32` | 35.23% |
| `#5E8640` | 16.63% |
| `#223818` | 5.98% |
| `#6A8C4C` | 0.63% |

- unique **5**. extra/AA/lime: none. hi comps n=407 max=1 mean=1.00. Highlight `#729C50` replaced with `#6A8C4C` (1-step, not `#7A9A4A`).

### `tree_tall.png`

| Hex | new % |
|-----|-------|
| `#2A4E3C` | 37.35% |
| `#1E3A2E` | 37.34% |
| `#38624A` | 19.12% |
| `#142820` | 5.36% |
| `#487858` | 0.83% |

- unique **5**. extra/AA/lime: none. hi comps n=638 max=1 mean=1.00.

Seeds: round `20261001`, pine `20261011`, cluster `20261021`, oak `20261031`, airy `20261041`, dark `20261051`, broad `20261061`, tall `20261071`.

---

## Screen-px / texel (typical r=32, 96→384)

| z | live 96 | Wave F 384 |
|---|---------|------------|
| 1.24 tee | 0.89 | **0.22** |
| 12 green-book | **8.6** | **2.15** |
| 36 | 25.8 | 6.4 |
| 130 putt | 93 | **23** |

Target met: 1–2px flecks at z=12 → ~2–8 screen-px grain, not sandy 8px blobs.

---

## AD note — beat live at z=12 without becoming bushes from tee

**Yes at z=12.** Live 1px flecks become ~8–9 px squares on a 96px canopy. Authored 1–2px flecks on a 384px canopy become ~2–5 px grain with the same silhouette and same world Ø. Cluster/oak/pine identities hold because the live alpha mass (and its coarse color lobes) were kept.

**Tee z=1.24 should not read as bushes.** New texels are subpixel (~0.22 px/texel); the eye gets the mean canopy value plus the irregular dark blob. Live-color lobe bias (no square cell lattice) keeps a readable mass instead of TV-static camo. Interior holes were re-authored as 1px (not 4×4 NN holes, which *would* look moth-eaten). Compare `sim_tee.png`. If a variant looks softer/smoother than live from altitude, that is the intended trade for punch-in grain — not a new look.

**Putt 130 leftover exists (~23 px/texel if 4×).** Do not chase 768 unless green-book silhouettes fall apart. Collision / world radius unchanged.

---

## What we did NOT change

- Pixel Kit Golf language (chunky hard pixels, limited palette, no photo, no Filter On, no AA).
- World radius, collision `r×0.72`, `TREE_CANOPY_H`, placement.
- Ship filenames / preload list.
- Live files, `assets/`, user computer, git.
- Did not NN-upscale RGB. Did not introduce `#7A9A4A`. Did not add trunks or side-view lollipops.

---

## Files

| File | Role |
|------|------|
| `tree_round.png` | 4× authored canopy (same ship name) |
| `tree_pine.png` | 4× authored canopy (same ship name) |
| `tree_cluster.png` | 4× authored canopy (same ship name) |
| `tree_oak.png` | 4× authored canopy (same ship name) |
| `tree_airy.png` | 4× authored canopy (same ship name) |
| `tree_dark.png` | 4× authored canopy (same ship name) |
| `tree_broad.png` | 4× authored canopy (same ship name) |
| `tree_tall.png` | 4× authored canopy (same ship name) |
| `tile_1x.png` | live native vs new native vs NN-upscale trap |
| `sim_tee.png` | z=1.24 three trees on Wave F rough |
| `sim_greenbook.png` | z=12 greenside cluster |
| `sim_putt_greenside.png` | z=36 and z=130 canopy-edge crop |
| `gen_wave_F_trees.py` | recipe (reproducible, seeded) |

Live copies for this review: `/workspace/parorbetter-art/trees_live/`.


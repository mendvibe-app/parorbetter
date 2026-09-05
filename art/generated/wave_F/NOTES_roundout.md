# Wave F roundout — tee 256 + bunkers 4× (review only)

**Date:** 2026-09-01  
**Status:** Review — **not promoted**. Output lives only on the box under `/workspace/parorbetter-art/wave_F_roundout/`.  
**Gate:** Matthew: "let's round it out with anything left" after fills, water, trees. Art lead: Mobile Bob Ross.  
**Tool:** Python/Pillow procedural kit (no AI image generator, no AA, Filter-Off language).  
**Do not swap greens / HUD / putt camera / cup / pin / ball / fog / golfer.**

---

## Inventory — every PNG the course actually stamps

`hole_controller.gd` preloads + `assets/terrain`, `hazards`, `greens`, `background`. HUD `ui_club_bag.png` listed only to exclude it.

| PNG | live size | stamp math | z=12 px/texel | this wave? |
|-----|-----------|------------|---------------|------------|
| `fairway_tile_a.png` | 64 | Polygon2D `texture_scale = width/300` (`GROUND_TILE_PX`) | 56.3 live / **14.1 Wave F 256** | already Wave F |
| `rough_tile_a.png` | 64 | same 300 (first-cut halo **reuses A**, no separate art) | 56.3 / 14.1 | already Wave F |
| `rough_tile_b.png` | 64 | same 300 + OOB strips at 220 | 56.3 / 14.1 | already Wave F |
| `tee_tile.png` | **64** | Polygon2D **`tile_px = 180`** (not 300). Active pad **56×62** | **33.8** | **YES 256** |
| `water_tile.png` | 64 | island Polygon2D `tile_px = 260` | 48.8 / 14.1 Wave F 256@300 | already Wave F water |
| `water_pond.png` | 96×80 | Sprite2D world ~64–93 × 48–70 | coarse live | already Wave F water 192×160 |
| `water_creek.png` | 128×48 | Sprite2D carry band | coarse live | already Wave F water 384×96 |
| `bunker_blob.png` | **128** | Sprite2D `scale = r×2.3 / max_dim`, r 32–52, Ø 74–120 | **~8.2 at r=38** | **YES 512** |
| `bunker_crescent.png` | **128** | same; **940 unique RGB** (photo/AA) | ~8.2 | **YES 512 + 3-hex kit** |
| `bunker_cluster.png` | **128** | same; 3-lobe identity | ~8.2 | **YES 512** |
| `tree_*.png` ×8 | 88–112 | `scale = r×2.15 / max_dim` | ~8.6 live / 2.2 Wave F 4× | already Wave F trees |
| `green_oval/kidney/tiered/long/island.png` | **768** | `scale = (r×2 / 0.85) / tex` | **~2.1** putting rx=56; **~16.7 at putt 130** with rx=42 | **SKIP** — already the zoom pass |
| `cup.png` | 64 | `scale = (CUP_RADIUS×2) / width`, `CUP_RADIUS = 0.198` | 0.80 at z=130 | SKIP true-scale |
| `pin_flag.png` | 64×96 | `PIN_FLAG_SCREEN_PX = 40` (world = 40/zoom) | always ~0.42 px/texel | SKIP screen-constant |
| `fog_overlay.png` | 1536×640 | Sprite2D scale `(1240/w, 0.4)` modulate a=0.5 | haze, all partial alpha | SKIP — not punch-in grain |
| `sky_gradient.png` / `title_dusk.png` | 1024×1536 / title | **not** stamped by `hole_controller` | — | not course |
| `assets/ui/ui_club_bag.png` | HUD | chrome | — | out of scope |

**No extra leftover coarse course prop** (not HUD/golfer) besides tee + three bunkers. First-cut is `rough_tile_a`. `water_shore.png` exists in Wave F water but is **not** a live preload (engine still stretches `water_tile` along Cape panels).

Live copies for this review: `wave_F_roundout/_live/`.

---

## Engine scale (quoted — do not change world sizes)

`hole_controller.gd`:

```
const TEX_TEE := preload("res://assets/terrain/tee_tile.png")
const BUNKER_TEXTURES := [
    preload("res://assets/hazards/bunker_blob.png"),
    preload("res://assets/hazards/bunker_crescent.png"),
    preload("res://assets/hazards/bunker_cluster.png"),
]
const GROUND_TILE_PX := 300.0

func _add_tee_boxes() -> void:
    var w := 56.0 if active else 44.0
    var h := 62.0 if active else 50.0
    _add_rect(course_root, rect, fill, "tee", TEX_TEE, 180.0)

func _add_bunker(center, radius, variant) -> void:
    var max_dim := maxf(float(tex.get_width()), float(tex.get_height()))
    spr.scale = Vector2.ONE * (radius * 2.3 / max_dim)

func _add_rect(..., tile_px: float = 300.0) -> Area2D:
    poly.texture_scale = Vector2.ONE * (float(texture.get_width()) / tile_px)
```

`hole_generator.gd` sand `size` (then `_add_bunker(c, size, art)`):

| role | size |
|------|------|
| greenside | `lerpf(32, 44, t)` (sometimes 30 cluster) |
| landing | `lerpf(38, 52, t)` (fallback 42) |

Visual world diameter = `r × 2.3` ≈ **74–120**. A 4× texture has 4× `max_dim` → Sprite2D.scale becomes ¼ → **same world Ø, denser grain.** Tee pad stays 56×62; only texel density changes (`256/180` vs `64/180`).

---

## What we measured on live

### `tee_tile.png` (64×64, 3 colors, opaque)

| Hex | Live % | role |
|-----|--------|------|
| `#5E763C` | 50.05% | paler mid |
| `#4A5E32` | 34.86% | dark ≈ fairway extra `#4A5F2F` |
| `#728E48` | 15.09% | worn highlight (not `#7A9A4A`) |

- **16 pairs of 2+2 columns** (dark, dark, light, light) wrapping the tile — fairway-adjacent mow, paler.
- Horiz runs mean 1.63 max 9. Vert mean 2.29 max 18.
- Wrap mismatch X=47 Y=28 of 64 — **live is not seamless**. Authored torus.
- At z=1.24: `1.24 × 180 / 64` = **3.49 px/texel**. Pad 56 wide → ~20 texels across.

### Bunkers 128×128, alpha 0/255, no interior holes except cluster (3 / 43 px)

| file | opaque | unique RGB | bbox | identity |
|------|--------|------------|------|----------|
| blob | 31.2% | **3** STYLE sand | 97×69 oval | flattened oval |
| crescent | 34.6% | **940** photo | 99×84 | C opening to +X |
| cluster | 23.4% | **3** STYLE sand | 85×71 | three touching lobes |

Blob/cluster mix ≈ mid 43–46 / shadow 31–35 / light 22. Horiz runs mean ~1.5 (already 1px-class). **Failure is texel size**, not palette count — except crescent, which is a photo/AA STYLE break even at tee.

At r=40: live `scale = 40×2.3/128 = 0.719` world-px/texel → z=12 **8.63 px/texel** (sandy 8px squares). Tee z=1.24 is already ~0.89 (fine).

Greens 768 @ putting rx=42, `surface_frac=0.85`: `130 × (84/0.85)/768` ≈ **16.7 px/texel** at putt 130 — **not coarse vs Wave F fills** (~152). Skip.

---

## What Wave F roundout authored

Did **not** nearest-upscale RGB (that keeps 8px mow / sandy 8px). Tee authored native 256. Bunkers: NN **silhouette** only, 1px nicks, then 1–2px STYLE sand grain. Crescent quantized to the three STYLE sand hexes.

### `tee_tile.png` — 256×256 seamless X/Y, still stamped at **180**

- Palette: STYLE fairway `#647E3D` `#546835` `#3D5228` `#4A5F2F` plus live worn `#728E48`. **No lime.**
- **64 authored pairs** of irregular 1–3 px half-bands (width hist from seed; sum 256). Same 4× world frequency as Wave F fairway, on a tighter 180 stamp → tee stays a finer mow than the landing strip (live already was 16 pairs / 180 vs 16 / 300).
- Worn language: paler light-band mix, `#728E48` catch-lights, sparse 1px dark divots, slightly more ±1 nicks than fairway.
- Mix (percent of 65536 px):

| Hex | n | % |
|-----|---|---|
| `#4A5F2F` | 24724 | 37.73% |
| `#647E3D` | 14972 | 22.85% |
| `#546835` | 14802 | 22.59% |
| `#728E48` | 7436 | 11.35% |
| `#3D5228` | 3602 | 5.50% |

- Unique colors: **5**. Extra/AA/lime: **none**. Opaque 100%.
- Wrap luma-delta (edge − interior): `(-1.51, -0.40)`. Torus by construction.

`256/180` texels per world-px. z=1.24 → **0.87 px/texel**. z=12 → **8.44**. z=130 → **91.4**.

### Bunkers — 512×512 cutouts, same world Ø

- Palette **only** STYLE sand `#D4BB92` `#BA986B` `#8B6B45`. Hard silhouette, alpha **0/255**.
- Light sand is 1px with rare 2px vertical tips (neighbor-reject). Edge biased to shadow so the lip reads against grass.
- Identities: blob oval, crescent C, cluster three lobes. Cluster interior holes re-scattered as 1px (not 4×4 NN moth holes).

### `bunker_blob.png`

Live 128×128, unique RGB **3**, opaque 5109 (31.2%), interior holes 0 / 0 px, lime 0, partial alpha 0.
New 512×512, unique RGB **3**, opaque 81712 (31.2%), light comps n=7297 max=2 mean=1.27. Extra/AA/lime: **none**.

| Hex | n | % |
|-----|---|---|
| `#BA986B` | 48761 | 59.67% |
| `#8B6B45` | 23676 | 28.97% |
| `#D4BB92` | 9275 | 11.35% |

### `bunker_crescent.png`

Live 128×128, unique RGB **940**, opaque 5664 (34.6%), interior holes 0 / 0 px, lime 0, partial alpha 0.
New 512×512, unique RGB **3**, opaque 90561 (34.5%), light comps n=8336 max=2 mean=1.27. Extra/AA/lime: **none**.

| Hex | n | % |
|-----|---|---|
| `#BA986B` | 54594 | 60.28% |
| `#8B6B45` | 25380 | 28.03% |
| `#D4BB92` | 10587 | 11.69% |

### `bunker_cluster.png`

Live 128×128, unique RGB **3**, opaque 3834 (23.4%), interior holes 3 / 43 px, lime 0, partial alpha 0.
New 512×512, unique RGB **3**, opaque 61303 (23.4%), light comps n=5173 max=2 mean=1.26. Extra/AA/lime: **none**.

| Hex | n | % |
|-----|---|---|
| `#BA986B` | 34445 | 56.19% |
| `#8B6B45` | 20323 | 33.15% |
| `#D4BB92` | 6535 | 10.66% |


Seeds: tee `20261101`, blob `20261111`, crescent `20261121`, cluster `20261131`. Band widths seed-order: {3: 32, 1: 32, 2: 64}.

---

## Screen-px / texel

### Tee 64@180 vs 256@180

| z | live 64 | Wave F 256 |
|---|---------|------------|
| 1.24 tee | **3.49** | **0.87** |
| 12 | **33.8** | **8.44** |
| 36 | 101 | 25.3 |
| 130 | **366** | **91.4** |

### Bunker r=40, 128 vs 512 (`scale = r×2.3/max_dim`)

| z | live 128 | Wave F 512 |
|---|---------|------------|
| 1.24 tee | 0.89 | **0.22** |
| 12 green-book | **8.63** | **2.16** |
| 36 | 25.9 | 6.47 |
| 130 putt | **93.4** | **23.4** |

Green-book is the money shot: live sand becomes 8px squares; Wave F 1–2px grain → ~2–5 screen-px. Crescent also stops being a photo smear.

---

## AD note — is the course-scale kit complete?

**Yes, for a Phase-1 PNG swap of course stamps** after this gate:

- Fills 256@300 (fairway / rough A / rough B) — Wave F
- Water island 256 + shore strip + pond/creek 2× — Wave F water *(shore still needs an engine repeat; PNG-swap of 256 into today's stretch Sprite2D still smears)*
- Trees 4× canopies — Wave F trees
- Tee 256@180 + bunkers 512 — this folder

**Do NOT swap** (already correct density, or not course-scale grain):

- **Greens 768** — ~16–22 px/texel at putt 130; finer than Wave F fills. Swapping them is a new look, not this polish.
- **Putt camera** (`PINCH_ABS_ZOOM_MAX = 130`, putt aim zoom) — leftover slabs at 130 are a zoom × stamp problem, not a missing PNG. Do not retune the camera to hide art.
- **Cup / pin / ball** — true-scale / screen-constant. Cup at z=130 is **0.80 px/texel**.
- **HUD / pad golfer / `ui_club_bag`** — out of scope.
- **Fog overlay** — stretched haze, partial alpha, not a 64/128 punch-in stamp.
- **Title / sky** — not stamped on the hole.

Putt-130 leftover remains on tee (~91 px/texel) and bunkers (~23). Bunkers match tree 4× leftover; tee is denser than live by 4× but still LEGO if you putt on the box. Next lever would be 512 tee / 768 bunker — not more palette.

---

## What we did NOT change

- Pixel Kit Golf language (chunky hard pixels, limited palette, no photo, no Filter On, no AA).
- World pad 56×62, bunker r, collision paint-alpha, `tile_px = 180`, `GROUND_TILE_PX = 300`.
- Ship filenames / preload list.
- Live files, `assets/`, user computer, git.
- Did not NN-upscale RGB. Did not introduce `#7A9A4A`. Did not author a new bunker silhouette language (blob/crescent/cluster kept).
- Did not include an extra leftover prop — inventory found none besides tee + bunkers.

---

## Files

| File | Role |
|------|------|
| `tee_tile.png` | 256×256 seamless tee fill |
| `bunker_blob.png` | 512×512 cutout |
| `bunker_crescent.png` | 512×512 cutout (3 STYLE hexes, was 940) |
| `bunker_cluster.png` | 512×512 cutout |
| `tile_1x.png` | live native vs authored vs NN-upscale trap |
| `sim_tee.png` | z=1.24 tee pad on Wave F fairway + bunker in rough |
| `sim_greenbook.png` | z=12 greenside bunker + fringe |
| `sim_putt_bunker.png` | z=36 and z=130 bunker grain leftover |
| `gen_wave_F_roundout.py` | recipe (reproducible, seeded) |
| `_live/` | copied live tee/bunkers/greens/fog/cup/pin for measurement |


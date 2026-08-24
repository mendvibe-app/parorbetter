# Findings — Ground art detail density vs true-scale putting zoom

**Recon brief:** `plans/recon-ground-art-scale.md`  
**Status:** FINDINGS ONLY (recommendations live in the decision memo / session plan).  
**Method:** Formula trace of Phase 2 putt zoom + asset inspection (not live Debug logs).  
**Peeps (8× nearest-neighbor):**  
- `plans/recon_green_oval_8x_nearest.png`  
- `plans/recon_green_oval_center_8x.png`

---

## 1. Distance → zoom → window → which asset

Constants: `PUTT_ZOOM_CAP=130`, span `0.65/2/3.5`, view frac `0.72`, object blend 8→48 ft.  
`PX_PER_FT = 2.25/3`. Viewport design **1080×1920**.

| Dist | Zoom ≈ | Half-view W×H (ft) | Inside typical green (37–53 ft radius)? | Asset filling frame |
|------|--------|--------------------|----------------------------------------|---------------------|
| 3 ft | 130 | ~5.5 × 9.8 | Yes | **Green sprite only** |
| 9 ft | 122 | ~5.9 × 10.5 | Yes | **Green sprite only** |
| 15 ft | 93 | ~7.7 × 13.8 | Yes | **Green sprite only** |
| 26 ft | 76 | ~9.5 × 16.8 | Yes | **Green sprite only** |
| 40 ft | 48 | ~15.0 × 26.7 | Yes (edge of small greens) | **Green sprite** (apron possible on tiny greens) |

**Conclusion A:** Pure putt framing is a **green-only** problem. Fairway/rough tiles are not in the putt window for normal greens.

**Chip caveat:** `_is_putt_context()` also when `pin_yards ≤ 28` — short chips can share this camera and expose apron/fairway. Separate blast item.

---

## 2. Feet-per-pixel / on-screen texel size

### Green (stretched 128×128)

`_add_green`: scale ≈ `(2 * r / surface_frac) / 128` with `surface_frac` 0.85 (non-island) or 0.62 (island) → texture covers **more** than the detection ellipse (extra stretch).

Bare (optimistic) ft per source px ≈ `(2 × radius_ft) / 128`:

| Green radius | ft / src px | 15 ft putt: screen px / src texel ≈ |
|--------------|-------------|--------------------------------------|
| 37 ft | 0.58 | ~**40** (z≈93) |
| 45 ft | 0.70 | ~**49** |
| 53 ft | 0.83 | ~**58** |

With `surface_frac=0.85`, multiply by **~1.18** (worse). Island `0.62` worse still.

At **9 ft** (z≈122) on a **53 ft** green: on the order of **~70–80 screen px per source texel**.

### Fairway / rough (tiled)

`GROUND_TILE_PX := 300`, tile **64×64** → **~6.25 real ft per texel**.  
At putt zoom, if visible: **~225–600 screen px per texel** (3–40 ft). Not in normal putt frame.

---

## 3. Source peep — green_oval has real structure

`green_oval.png` is **not** a flat low-info blob.

8× nearest peeps show **alternating light/dark mow-stripe columns** with deliberate dither; fringe/collar ring; silhouette alpha. Mid-band column light/dark transitions are frequent (~40+ across the putting disc) — motif is intentional kit language.

**Implication:** later art work should **refine this motif to a finer ground scale** (stripes as inches, not feet), not invent a new grass language.

All listed greens are **128×128**: oval, kidney, tiered, long, island.

---

## 4. Blast radius

| Asset | Res | Mechanism | Typical view | Risk at putt/chip zoom |
|-------|-----|-----------|--------------|------------------------|
| Green shapes | 128² | Stretch one sprite | Putt / green | **Primary** |
| Fairway / rough / tee / water tiles | 64² | Tile @ 300 world-px | Tee / approach; chip if frame leaves green | **High if in frame**; deferred for pure putt |
| Cup | 64² | Stretch to `CUP_RADIUS` | Putt | True-scale already |
| Ball | 64² | Stretch to `BALL_R_PUTT` | Putt | Same |
| Bunker sprites | ~128 | Stretch to hazard radius | Approach / greenside | Medium if greenside in chip zoom |
| Water creek/pond | varies | Stretch / place | Approach | Medium |
| Pin / course pin | vector/sprite | Plant on cup | Putt | OK / separate |
| Fog overlay | large | Stretch band | Wide shots | Low for putt |

---

## 5. Pipeline conventions

From `art/STYLE.md` (**Pixel Kit Golf**, locked):

- Fill tiles ship **64×64** seamless; Filter **Off**; hard edges; chunky kit, not photo.
- Aerial stamp: ~**one 64px tile per 300 world-px** (`GROUND_TILE_PX`).
- Fairway: many thin mow pairs per tile; rough = fine flecks.
- Greens today are **feature sprites** (silhouettes) that already carry a **mow-stripe** language compatible with kit fairway intent.
- PixelLab kit prompts: `art/prompts/kit.md`.

---

## 6. Explicit non-contents

No fix proposal in this file. Direction: session decision memo (revised) — greens regen pilot **~768**, worst-case large green playtest; fairway deferred; no filter; camera zoom-in after density.

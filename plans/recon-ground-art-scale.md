# Recon — Ground art detail density vs. true-scale putting zoom

**Deliverable path (on approve):** `plans/recon-ground-art-scale.md` (brief) → agent produces `plans/recon_findings_ground_art_scale.md` (findings)
**Status:** RECON ONLY. No code changes, no art changes. Do not touch any constant, shader, or asset.
**Why:** post true-scale Phase 1+2, putting green ground reads as "zoomed into the texture" / blocky. Two candidate assets could be responsible and they need different fixes — this recon settles which, before any art or tuning work starts.

---

## 1. Context (already established, don't re-derive)

- `PX_PER_YARD := 2.25` → 0.75 world-px per real foot, used everywhere (yardage, wind, aim, putt "N ft" label).
- Putt camera zoom (`_desired_camera_zoom()`, putt branch) now reaches up to `PUTT_ZOOM_CAP := 130` for short putts (was 24 pre-Phase-2).
- At a 9 ft putt, computed visible half-span ≈ 8.5 real feet (≈17 ft window). At longer putts the window opens up per `PUTT_SPAN_COEFF`/`PUTT_SPAN_FLOOR`.
- Green radius (per green-sizing design) is ~37–53 ft (4,300–9,000 sq ft range) — so **short/mid putts are viewed through a window entirely inside the green**, never reaching the fairway/rough boundary.
- Two separate ground-art mechanisms exist and were NOT touched by the true-scale epic:
  - **Green surface**: one 128×128 sprite per green shape (`assets/greens/green_oval.png` etc.), *stretched* (not tiled) to cover the full green radius (`_add_green()`, `hole_controller.gd:836-850`).
  - **Fairway/rough surround**: `TEX_FAIRWAY`/`TEX_ROUGH`, 64×64, *tiled* at `GROUND_TILE_PX := 300` world-px per tile (~400 real ft/tile) (`hole_controller.gd:115`, `:706-707`, `:1294-1303`).

These need separate fixes if both are contributing — a tiling-density fix does nothing for a stretched sprite, and vice versa. This recon exists to find out which one(s) are actually on screen and by how much they're over-magnified, with real numbers, before any fix gets scoped.

---

## 2. What to establish

### A. Which asset is actually visible, at the putt distances that prompted this

For putt distances **3 ft, 9 ft, 15 ft, 26 ft, 40 ft** (cover short through the `PUTT_OBJ_BLEND_END_FT := 48` band):
- Compute actual `_desired_camera_zoom()` output at each distance (log it in-game via Debug, or trace the formula with real green radius for a couple of actual holes).
- Compute the real-feet half-span visible at that zoom.
- Compare to that hole's actual green radius (`green_radius_x`/`green_radius_y` — pull real values from a few generated holes, don't assume the 37–53 ft design range holds everywhere).
- Report: at each distance, is the visible window entirely inside the green sprite, does it cross into the fairway apron, or both (edge case)?

### B. Real-world detail density of each candidate asset, as currently used

For the **green sprite** (`green_oval.png` and at least one other shape):
- Source resolution (already confirmed 128×128) — confirm others match.
- At current stretch (`spr.scale` in `_add_green()`), compute real feet per source pixel for a typical green (use the same real green radii pulled in step A).
- Report whether the source image has meaningfully fine detail baked in, or if it's largely flat/low-frequency color (i.e., would finer stretching even reveal more detail, or is the source itself low-information at native res). Attach a straight pixel-peep crop of the source PNG at, say, 8x nearest-neighbor zoom so we can eyeball this without opening Godot.

For **fairway/rough tiling**:
- Real feet per source pixel at current `GROUND_TILE_PX := 300` (already computed as ~6.25 ft/texel — confirm).
- Confirm whether fairway/rough tiling is ever actually visible during putt-zoom framing given finding A, or only during chip/approach zoom (`_is_putt_context()` also triggers for `pin_yards <= 28`, so short chips share the putt camera — check whether *those* views cross into fairway tiling territory even if pure putts don't).

### C. Blast radius — other assets at risk of the same mismatch

List every other stretched-single-sprite or tiled-texture ground/hazard asset (bunker sand, water, tee box, OOB rough) with: resolution, stretch or tile mechanism, and the real feet-per-pixel each one renders at in its typical viewing context (tee/approach zoom vs. the new putt/short-chip zoom range). Flag any that share the putt-zoom camera band (pin_yards ≤ 28) the same way fairway/rough might.

### D. Existing art pipeline conventions

Pull whatever style/resolution conventions the PixelLab-generated icon set already follows (palette size, base tile resolution, any style-guide doc in the repo). We'll need this if new putting-green-specific art gets commissioned later — not to design it now, just so we're not starting blind.

---

## 3. Deliverable

A findings doc (`plans/recon_findings_ground_art_scale.md`) with:
1. A table: distance → zoom → visible half-span (ft) → which asset(s) fill frame.
2. Real feet-per-pixel for green sprite (stretched) and fairway/rough (tiled), at the zoom levels that actually matter per (1).
3. The pixel-peep crops from step B.
4. The blast-radius list from step C.
5. Pipeline conventions from step D.
6. No recommendation, no fix proposal — just the numbers and images. Direction gets decided after this comes back.

---

## 4. Out of scope — do not touch

- No edits to `GROUND_TILE_PX`, `_add_green()`, `_desired_camera_zoom()`, or any texture/sprite constant.
- No new art generation via PixelLab yet.
- No commits — this is a read-only investigation. If it's easier to log/print values via a temporary debug branch, fine, but don't merge it.

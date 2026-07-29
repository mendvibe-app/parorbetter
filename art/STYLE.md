# Art Style Skill: Pixel Kit Golf

**Status**: Locked (redesign)  
**Last updated**: 2026-07-29  
**Applies to**: All visual assets (tiles, props, UI, tempo/putt pad, HUD, ball, effects, characters).

This document is the single source of truth. Any AI agent or human generating or modifying art **must** follow these rules.

**Tool pipeline**: Prefer **PixelLab-native kit tools** (tilesets, character, map props). See `art/prompts/kit.md`.  
Do **not** force freeform generators to pixel-clone hand texture refs.

---

## 1. Core Description

**Pixel Kit Golf**

A coherent top-down **pixel game kit** for mobile golf — chunky, limited palette, readable at phone distance.  
Feels like a small indie sports kit that tiles and matches itself, not like photo-derived grass samples.

Visible square pixels are desired. Not soft. Not photoreal. Not “modern refined polish.”

**Key feelings:** chunky • kit-coherent • silhouette-clear • playful • glance-readable

**What changed (2026-07-29):**  
Former direction (“Crunchy Pixel” + mandatory `art/references/` material clones) fought PixelLab’s strengths. We redesign the *art system* to want kit packs, not reverse-engineered playtest textures.

---

## 2. Design Principles

1. **Kit over material clone** — course = small matched set of generated pieces, not four hand-ref seamless masters we recreate via img2img.
2. **Silhouette first** — greens, bunkers, water bodies, trees, pin: clear cutouts; fill texture is secondary.
3. **Value contrast > micro-dither** — fairway / rough / sand / water separate by value and hue first; tuft authenticity is optional.
4. **Character pipeline, not pose collage** — one PixelLab character identity; poses derive from that identity.
5. **Fewer textures, more reuse** — 1–2 fairway fills, rough, sand, water; props share the same palette language.
6. **Refs are mood only** — `art/references/` may guide value/hue targets. They are **not** pixel-perfect masters.

---

## 3. Technical Rules

- **Fill tiles**: **64×64** seamless on X and Y (ship format for current stamp renderer). Source may be 16/32 PL tiles upscaled with nearest-neighbor.
- **Aerial feature scale (critical)**: Camera is top-down as if flying over a course. Engine stamps fills with ~**one 64px tile per 300 world-px** (`texture_scale = width/300`). A fairway is only ~160–240 world-px wide → about **half a tile** of texture across the landing strip.
  - **Fairway mow stripes**: ~**16 pairs** (thin dark/light, ~2px half-bands) per 64px tile → ~8–12 bands visible across a real fairway. **Never** 4–6 fat stripes (reads as “5 mowers wide”).
  - **Rough**: fine grain / 1–2px flecks and tiny tips — **not** large camo blobs (those read as bushes from altitude).
  - **Water**: small-cell caustics, not huge puzzle pieces.
- **Pixel density**: Chunky but **high frequency** for terrain fills. Value masses at the *band* scale, not the *whole-tile* scale.
- **Edges**: Hard. No anti-aliasing on material or prop boundaries.
- **Filtering in Godot**: `Filter = Off`
- **Format**: PNG. Transparency on props / bunker / green silhouettes.
- **Noise / dither**: OK inside bands/flecks; must still read at phone distance.
- **No landmark motifs** on seamless fills (no single clump that repeats in every quadrant).

---

## 4. Color Palette (Core)

Keep the palette limited. Hexes are **readability anchors** (not photo-sample locks). Neighbor shades OK if the kit stays coherent.

**Greens (terrain)**
- Fairway light: `#647E3D`
- Fairway mid: `#546835`
- Fairway dark: `#3D5228`
- Rough ground: `#49573E`
- Rough dark: `#30412E`
- Rough highlight: `#7A9A4A`
- Rough stem: `#1A2418`

**Sand**
- Light: `#D4BB92`
- Mid: `#BA986B`
- Shadow: `#8B6B45`

**Water**
- Highlight: `#86C2CD` / `#E8F4F6`
- Mid: `#457A9C`
- Dark pool: `#3C667C`
- Deep: `#2A4A5C`

**Neutrals / character**
- Near-black: `#1A1F1A`
- Dark gray: `#2E342E`
- Light accent / shirt: `#E8F0E8`
- Skin: `#D4BB92` / `#BA986B`

UI accents may use limited extras; do not casually expand course palettes.

---

## 5. Do’s and Don’ts

### Do
- Generate course pieces as a **matched kit** (same tool pass / style language)
- Prefer PixelLab tileset / prop / character tools over freeform texture clones
- Keep strong value contrast between surface types
- Tile-test every fill PNG (2×2 composite)
- Silhouette-test props on dark and light backgrounds
- Lock character identity before multi-pose packs

### Don’t
- Require pixel-matching `art/references/ref_*.png`
- Soft blur, painterly strokes, or high-res polish
- Seamless fills with one recognizable repeating clump
- Independent freeform gens per golfer pose (identity drift)
- Soft AA edges or Filter On for course/UI sprites

---

## 6. Asset-Specific Guidelines

### Terrain fills
- **Fairway**: lighter greens; optional soft mow banding; anonymous scatter
- **Rough**: darker than fairway; coarser texture; `rough_tile_b` denser/darker variant
- **Water**: mid/deep blues with simple caustic or ripple language
- **Sand**: warm mid tones; simple grain/ripples inside bunker silhouettes

Preferred source: PixelLab topdown tileset / tiles_pro → extract fills → 64×64 ship.

### Props (greens, bunkers, trees, cup, pin)
- Clear silhouettes, transparent outside shape
- Shared kit palette; greens quieter/smoother than rough
- Prefer object/prop tools; not full scenic frames
- **Trees (aerial):** top-down **canopy mass** — irregular dark blobs with fine flecks, no trunk/lollipop side-view. Cluster for tree-line density. Mood: `art/references/hole_example.png`

### UI / HUD / tempo pad
- Same kit language and limited palette as course
- High contrast; thick readable marks
- Typeface: **Pixel Operator** (CC0) — clear HUD digits; `assets/fonts/PixelOperator.ttf`

### Characters (pad golfer)
- Flat kit silhouette (not PL RPG/chibi): green cap, dotted light shirt, dark pants, hard outline
- Discrete poses for stroke sync — same identity across full / putt / chip sets
- Specs: `art/prompts/golfer.md`; Wave B baseline in `art/generated/wave_B/`
- Hard outline, limited palette, transparent BG 128×192, Filter Off

---

## 7. Master Prompt Template

```
pixel art game kit, top-down mobile golf, chunky visible pixels, limited palette,
hard edges no anti-aliasing, high value contrast, coherent tileset/prop style,
[top-down fill tile | cutout prop | UI icon | character], [subject]
```

Append subject, size, and tool-specific constraints. Do **not** append “match ref_fairway.png pixel-for-pixel.”

---

## 8. Naming & Folders

| Path | Role |
|------|------|
| `art/generated/wave_*/` | Raw kit waves (review before promote) |
| `assets/terrain/` etc. | Live game art only after wave gate |
| `art/references/` | Mood / value reference only |
| `art/prompts/kit.md` | PixelLab tool map + pipeline |
| `art/prompts/*.md` | Per-domain briefs |

Ship names unchanged (engine preloads):  
`fairway_tile_a.png`, `rough_tile_a.png`, `rough_tile_b.png`, `water_tile.png`,  
`green_*.png`, `bunker_*.png`, `ui_golfer_*.png`, etc.

App icon: `icon.png` (512); design mood: `art/references/ref_app_icon_*.png`.

---

## 9. Godot Notes

- Terrain/sprites: Filter = Off
- Phase 1: keep stamp preloads in `hole_controller.gd` — **PNG swap only**
- Phase 2 (optional): Wang / TileMap transitions if kit quality needs it
- Test on phone-sized viewports early

---

## 10. Research archive

`art/generated/wave_1/` (pixflux-from-ref attempts) is **research only** — do not promote without re-gate under this STYLE.

**Wave A fill baseline (gated):** `art/generated/wave_A/` scale3 → live `assets/terrain/{fairway,rough_a,rough_b,water}_tile*.png`. Aerial frequency locked; props/character must match this density language.

---

**This style is locked.**  
Significant deviation requires an explicit update to this document.

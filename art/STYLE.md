# Art Style Skill: Crunchy Pixel

**Status**: Locked  
**Last updated**: 2026-07-24  
**Applies to**: All visual assets (tiles, props, UI, tempo/putt pad, HUD, ball, effects). Characters when authored.

This document is the single source of truth. Any AI agent or human generating or modifying art **must** follow these rules. Course surfaces also use `art/references/`.

---

## 1. Core Description

**Crunchy Pixel**

Truly pixelated golf game art (course + UI).  
Visible square pixels are desired. Not soft. Not “refined modern polish.” Not photoreal.

The goal is readable material and UI language on mobile: fairway / rough / bunker / water must separate at a glance, and HUD/pad chrome must share the same crunchy hand-authored feel.

Key feelings: chunky • dithered • material-clear • playful

**References (source of truth for surfaces):**
- `art/references/ref_fairway.png`
- `art/references/ref_rough_a.png` / `ref_rough_b.png`
- `art/references/ref_water.png`
- `art/references/ref_sand.png`

---

## 2. Technical Rules

- **Base resolution for tiles**: **64×64**, seamless on X and Y
- **Pixel density**: Chunky and readable. Prefer fewer, larger value clumps over micro-detail mush.
- **Edges**: Hard. No anti-aliasing on material boundaries.
- **Filtering in Godot**: `Filter = Off`
- **Format**: PNG. Power-of-two preferred. Transparency on props/bunker silhouettes.
- **Noise / dither**: Allowed and expected on terrain (controlled scatter inside bands/tufts). Must still read at phone distance — value masses first, speckles second.

---

## 3. Color Palette (Core)

Keep the palette limited. Hexes below are anchors; neighbor shades sampled from references are OK if documented here when locked in.

**Greens (terrain)** — from playtest refs + anchors
- Fairway light / noise: `#647E3D`
- Fairway mid stripe: `#546835`
- Fairway dark: `#3D5228`
- Rough ground: `#49573E`
- Rough dark ground: `#30412E`
- Rough tip / highlight: `#7A9A4A`
- Rough stem / shadow: `#1A2418`

**Sand**
- Light / crest: `#D4BB92`
- Mid: `#BA986B`
- Shadow / trough: `#8B6B45`

**Water**
- Highlight / caustic: `#86C2CD` / `#E8F4F6`
- Mid: `#457A9C`
- Dark pool: `#3C667C`
- Deep: `#2A4A5C`

**Neutrals**
- Near-black: `#1A1F1A`
- Dark gray: `#2E342E`
- Light accent: `#E8F0E8`

UI accents may use limited extras; do not casually expand course palettes.

---

## 4. Do’s and Don’ts

### Do
- Match `art/references/` material language for fairway / rough / water / sand
- Use vertical mow stripes + per-pixel noise for fairway
- Use tall tuft clumps (dark base, light tips) for rough
- Use coarse caustic lattice for water
- Use diagonal ripple ridges for sand
- Keep strong value contrast between surface types
- Tile-test every terrain PNG

### Don’t
- Soft blur, painterly strokes, or high-res “modern indie” polish on course tiles
- Flat unbanded fairway or empty rough without tufts
- Smooth water gradients without a blocky caustic web
- Make tiles that only look good in isolation

---

## 5. Asset-Specific Guidelines

### Terrain Tiles
- **Fairway**: Alternating vertical stripes, jagged edges, heavy dither inside bands (`ref_fairway.png`)
- **Rough**: Scattered grass tufts over darker speckled ground (`ref_rough_*.png`); `rough_tile_b` denser/darker
- **Water**: Light caustic web over darker ovals (`ref_water.png`)
- **Sand / bunkers**: Diagonal ripples filling bunker silhouettes (`ref_sand.png`)

### Greens / trees / cup
- Quieter cousins of fairway (striped/noise), not rough tufts
- Simple silhouettes; same crunchy pixel rules

### UI / HUD / tempo pad
- Same crunchy pixel language and palette as course
- High contrast; thick readable marks (no hairline UI)
- Tempo landmarks: distinct silhouettes, dither OK on fills, hard outlines
- Strike faces: chunky grooves, hard outline, limited shades
- Typeface: Pixelify Sans (OFL) — pixel-adjacent UI type

### Characters
- Pad golfer: discrete swing poses (`ui_golfer_*.png`) — see `art/prompts/golfer.md`
- Same crunchy rules (hard outline, limited palette, Filter Off); not a soft animated sheet

---

## 6. Master Prompt Template

Use this as the base for generation requests:

```
Crunchy true pixel art, visible square pixels, limited palette, dithered fills,
no anti-aliasing, mobile golf game asset, [top-down tile|flat UI overlay],
seamless if tile, match art/references when terrain, [specific subject]
```

Always append the specific subject and constraints after the template.

---

## 7. Naming & Folder Conventions

- Raw generations → `art/generated/`
- Final cleaned assets → `assets/terrain/`, `assets/hazards/`, `assets/greens/`, etc.
- References → `art/references/`
- App icon → `icon.png` (512; `icon_1024.png` for store exports). Design refs: `art/references/ref_app_icon_*.png`
- Naming: `fairway_tile_a.png`, `rough_tile_a.png`, `bunker_blob.png`, etc.

---

## 8. Godot Notes

- Terrain/sprites: Filter = Off
- Test readability on phone-sized viewports early
- Seamless tiles must not show seams when repeated

---

**This style is locked.**  
Any significant deviation requires an explicit update to this document (and new reference images for surfaces).

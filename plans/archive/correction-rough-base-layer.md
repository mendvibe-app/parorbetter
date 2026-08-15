# Correction: Rough should be the base surface, not two strips

**Status: SHIPPED 2026-08-15** (P0+P1 in one commit on `feature/rough-pacing-greens-stack`).
**Scope:** Terrain painting only. No gameplay/lie changes.
**Risk:** Low — verified that no lie, physics, or scoring path reads the belts.

---

## 1. The complaint

The course reads as *speckled background → two dark rectangles → fairway ribbon*. That
implies rough is "a thing that exists in two places." Real aerial golf is the other way
around: rough is the base surface covering the whole corridor, and the fairway is **mown
into it** as a shape.

## 2. Investigation result: this is 100% an art problem

Gameplay already models it correctly. Confirmed by reading source, not assumed.

**`scripts/course/hole_controller.gd:3292` — `_classify_lie()`**

```gdscript
var along := clampf(inverse_lerp(GREEN_Y, _tee_back_pos.y, pos.y), 0.0, 1.0)
var fx := absf(pos.x - _fairway_center_at(along).x)
if fx <= _fairway_half + 20.0:
    return "Fairway"
if fx <= _fairway_half + 80.0:
    return "Rough"
return "Rough"          # <- both branches identical
```

Everything not Fairway / Green / Sand / Tee / Trees is `"Rough"`, at any distance. The
`+ 80.0` split is dead code — both arms return the same string.

**`scripts/course/hole_controller.gd:1184` — `_add_side_belts()`** passes `""` as the
group argument, and `_add_rect()` (line ~3390) only calls `add_to_group()` when
`group != ""`. The belts have **no group, no gameplay meaning**. They are paint.

Also worth noting: **the minimap already tells the correct story.**
`scripts/ui/hole_map.gd:110` fills the entire map field with rough, then draws the
fairway ribbon on top. The world view contradicts our own minimap.

## 3. Why it reads wrong — three specific causes

### 3a. Value inversion (the main offender)

| Layer | Texture | Base color | Tint | Effective |
|---|---|---|---|---|
| Base rough (`:566`) | `rough_tile_a` | (73,87,62) | ×(0.92,0.98,0.92) | **(67,85,57)** |
| Side belt (`:1199`) | `rough_tile_b` | (48,65,46) | ×(0.85,0.9,0.85) | **(41,58,39)** |
| Fairway (`_add_bent_fairway`) | `fairway_tile_a` | (84,104,53) | white | **(84,104,53)** |

Moving outward from the centerline, brightness goes **light → dark → medium-light**.
Real aerials go light → dark monotonically. A dark band with a lighter field beyond it
is exactly the silhouette of *a stripe painted on a lawn*, which is what the eye reports.

### 3b. Hard rectangular edges

`_add_side_belts()` stamps axis-aligned rects `SIDE_BELT_W` wide in 36 px vertical
slabs. On a straight hole the outer boundary is a perfectly straight vertical line. Real
cut transitions are a *mow line* — a visible width step with slight irregularity — and
the outer edge of primary rough into native is ragged, never ruled.

### 3c. No texture language for grass length

`rough_tile_a` and `rough_tile_b` are the same per-pixel speckle noise at two
brightnesses. Nothing encodes *length*. Fairway is the only surface with directional
information (mow stripes). So brightness is the only cut cue we have — and 3a breaks it.

Minor: tile magnification differs per surface. Sources are 64 px; `tile_px` is 340
(rough a) / 280 (rough b) / 300 (fairway), so each source pixel renders at 5.31 / 4.38 /
4.69 world px. Adjacent surfaces have visibly different pixel densities, which subtly
breaks the "one world" read.

## 4. ⚠ The trap: `SIDE_BELT_W` is doing three unrelated jobs

Do **not** change `SIDE_BELT_W` (`:86`) without splitting it first. It currently drives:

1. **Art width** — `_add_side_belts()` `:1201`, `:1209`
2. **Camera framing** — `_play_corridor_width()` `:1159` → `_corridor_zoom_level()`
   `:1163`. Shrinking the belt shrinks the corridor, which *zooms the camera in*.
3. **Tree placement** — `_place_tree_group()` `:1240`,
   `lat := _fairway_half + size * ... + SIDE_BELT_W * 0.35`. Shrinking the belt walks
   the tree line inward onto the fairway edge.

**Required first step (Phase 0):** split into three named constants so each job can move
independently.

```gdscript
const FIRST_CUT_W   := 14.0   ## PLAYTEST TARGET — art only: first-cut halo width, px
const CORRIDOR_PAD  := 58.0   ## camera framing pad each side (was SIDE_BELT_W)
const TREE_LINE_PAD := 20.0   ## lateral tree offset beyond fairway edge (was SIDE_BELT_W * 0.35)
```

Then update `_play_corridor_width()` to use `CORRIDOR_PAD` and `_place_tree_group()` to
use `TREE_LINE_PAD`. **Camera and trees must be pixel-identical after Phase 0.** That is
the whole point of Phase 0 — it is a pure refactor with zero visible change.

---

## 5. The fix

### Phase 0 — Split the overloaded constant (no visible change)

As above. Ship and playtest to confirm nothing moved.

### Phase 1 — Invert the layer story

Target read: **dark rough everywhere → lighter first-cut halo → lightest striped
fairway.** Monotonic brightness outward from the centerline.

`hole_controller.gd:566` — base becomes the *dark* tile, untinted-down:

```gdscript
# BEFORE
_add_rect(course_root, Rect2(0, GREEN_Y - 140, 1080, course_len + 220),
    Color(0.92, 0.98, 0.92), "", TEX_ROUGH, 340.0)

# AFTER — rough is the world. Dark tile, neutral tint, shared tile_px.
_add_rect(course_root, Rect2(0, GREEN_Y - 140, 1080, course_len + 220),
    Color(1, 1, 1), "", TEX_ROUGH_DARK, GROUND_TILE_PX)
```

`_add_side_belts()` → rename `_add_first_cut()`, and flip it from a dark deep-rough band
to a light first-cut halo, `FIRST_CUT_W` wide, drawn *between* base and fairway:

```gdscript
_add_rect(
    course_root,
    Rect2(cx - half - FIRST_CUT_W, y, FIRST_CUT_W, h),
    Color(1, 1, 1),
    "",
    TEX_ROUGH,          # the LIGHTER tile is now the first cut
    GROUND_TILE_PX
)
```

Add one shared constant so all ground surfaces share pixel density:

```gdscript
const GROUND_TILE_PX := 300.0  ## PLAYTEST TARGET — one density for all ground surfaces
```

and pass it to the fairway polygon's `texture_scale` too.

**Ordering requirement:** base rough → first cut → fairway → green. `_add_first_cut()`
must still be called before `_add_green()`, as `_add_side_belts()` is today (`:571`).

### Phase 2 — Texture language for length (PixelLab, separate PR)

Current tiles differ only in brightness. Generate a proper set against the existing
palette (`life_full.png` / `life_empty.png` density reference):

- `rough_tile_long.png` — coarser, clumpier noise with short directional wisps. Reads
  as *unmown*, not just *darker*.
- `first_cut_tile.png` — intermediate: faint stripe direction, tighter noise.
- Keep `fairway_tile_a` as-is (mow stripes are already correct).

Palette must stay inside the existing greens; this is a shape/frequency change, not a
hue change.

### Phase 3 — Mow line irregularity (polish, optional)

The fairway/first-cut boundary is currently ruled straight. Options, cheapest first:

- Add ±3–5 px per-slab jitter to the `FIRST_CUT_W` edge, seeded on
  `hash(hole.hole_number)` so it's stable per hole.
- Or draw a 2 px lighter mow line along the fairway polygon edge.

Do not attempt until Phases 1–2 are playtested.

---

## 6. Real-golf grounding

At `PX_PER_YARD = 2.25`:

- Current `SIDE_BELT_W = 58 px` = **25.8 yd** of "deep rough" band each side. Real first
  cut is 2–3 yd. Current band is ~10× a first cut.
- Proposed `FIRST_CUT_W = 14 px` = **6.2 yd**. Still ~2× real, deliberately — it needs to
  survive the corridor zoom and read as a deliberate halo on a phone screen. Flagged as a
  playtest target, not a truth claim.
- Fairway widths in `hole_generator.gd` (`160 / 200 / 240 px` = 71 / 89 / 107 yd) are far
  wider than real (25–45 yd). **Out of scope here** — likely load-bearing for thumb aim
  precision. Noted only so nobody "fixes" it inside this epic.

---

## 7. Out of scope — do not touch

- `_classify_lie()` and any lie/physics/friction path. Gameplay is already correct.
- `hole_generator.gd` fairway widths, bends, or hazard placement.
- `hole_map.gd` — the minimap is already correct.
- The OOB rects at `:597` / `:598`.
- Camera constants `CORRIDOR_SCREEN_FRAC`, `_approach_pin_zoom`, `GRAVITY_PX`.
- The dead `+ 80.0` branch in `_classify_lie()`. Leave it. If deep rough ever becomes a
  real lie, it must read the same constant the art uses — but that is a future epic, and
  paint and play must be wired together in one change, not drifted apart in two.

---

## 8. Acceptance criteria

**Phase 0**
- Screenshot from the Red tee on Hole 1 (Par 3, 182 yds) before and after is
  pixel-identical. Camera zoom and tree positions unchanged.

**Phase 1**
- On any hole, sampling brightness along a horizontal line from fairway centerline
  outward is **monotonically decreasing**: fairway > first cut > base rough. No dark band
  with a lighter field beyond it.
- The fairway reads as a shape cut into a continuous surface. The frame no longer has two
  visible full-height rectangles.
- All three ground surfaces show the same pixel-block size (one `GROUND_TILE_PX`).
- Dogleg holes: the first-cut halo follows the bend and stays flush to the fairway edge
  with no gap or overlap at the corner. Test on the sharpest `corner_position` hole.
- Island green: base rough must not show through between the apron tongue and the water
  ring. (`_add_bent_fairway` has a specific island branch — verify it.)

**Regression**
- Hit 10 shots into the left rough and 10 into the right rough on Hole 1. Lie widget
  reports `Rough` every time, and rough severity still rolls Buried/Average/SittingUp.
  Nothing about lie behavior may change.
- Ball rolling from fairway into first cut reports `Rough`, not a new lie string.
- Approach and putt camera framing unchanged from pre-Phase-0 baseline.

---

## 9. Handoff notes for the coding agent

- Read this doc and confirm understanding before writing code.
- **Phase 0 and Phase 1 are separate PRs with a device playtest between them.** Do not
  bundle. Phase 0 is a no-op refactor; if it changes anything visible, it's wrong, and we
  need to know that in isolation.
- Touch only `scripts/course/hole_controller.gd`. No other file is in scope for Phases
  0–1. Phase 2 touches `assets/terrain/` only.
- Every new constant gets a `## PLAYTEST TARGET` comment. These are starting numbers.

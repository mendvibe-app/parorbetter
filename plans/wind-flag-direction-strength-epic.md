# Epic: Wind flag — directional legibility + strength tautness

## Status: SHIPPED
Closed: 2026-08-09 — landed in `02facf3` (wind cloth flags + shared `paint_flag`). Kept for history; do not re-implement.

**File:** `scripts/ui/wind_flag.gd`
**Scope:** The HUD "wind glance" widget only (the `WindFlag` control shown via `hole_controller.gd`). Does **not** touch the in-world pin flag sprite (`hole_controller.gd` `_pin_flag`, `TEX_PIN_FLAG` at line 42) — that's a separate, unrelated sprite and stays as-is.

---

## Problem

Today `WindFlag` renders `assets/greens/pin_flag.png` inside a `TextureRect` and expresses wind entirely as **rotation of the whole flagstick**:

- Crosswind (`wind.x`) rotates the flag up to ~35° (`MAX_LEAN`, line 8; applied at line 117).
- Head/tail wind (`wind.y`) keeps the flag upright and only distinguishes into vs. downwind via a text label (`_axis`, "↑ INTO" / "↓ HELP", lines 124–138).

Two real-golf problems with that:

1. **A flagstick is anchored in the ground.** The pole doesn't lean — the wind bends the cloth. Rotating the whole texture reads as a leaning stick, not a flag catching wind.
2. **Into wind and downwind are visually identical** (both upright, same silhouette). The only way to tell them apart is reading a small caption — that fails the "legible at a glance" bar the tempo and distance work has been held to.

## Design resolved with Matt (mockups approved)

- **Pole is rigid and always vertical.** Only the cloth reshapes.
- **Left/right wind** — cloth streams sideways off the pole like a windsock.
- **Into wind** — cloth billows full and bright, rendered in front of the pole (reads as coming toward the player).
- **Downwind** — cloth shrinks and tucks mostly behind the pole, muted color (reads as blowing away from the player).
- **Tautness = wind strength**, independent of direction: droopy and short at low wind, straight-edged and fully extended at high wind. Downwind is the inverse on size — stronger wind hides more of it behind the pole, not less.
- Diagonal wind (both axes significant) is **out of scope for this epic** — see Out of scope below.

## New rendering model

Replace the single rotated `TextureRect` with a hand-drawn pole + flag polygon in `_draw()`, so the cloth shape can actually change instead of just rotating a static sprite. Direction picks one of two draw modes by whichever wind axis dominates; strength drives a `lerp` between "droopy/small" and "taut/full" within whichever mode is active.

```
use_crosswind := abs(wind.x) >= abs(wind.y)

if use_crosswind:
    side      = sign(wind.x)                         # -1 left, +1 right
    cross_amt = clamp(abs(wind.x) / STRENGTH_NORM, 0, 1)
    reach     = lerp(CROSS_REACH_MIN, CROSS_REACH_MAX, cross_amt)
    droop     = lerp(CROSS_DROOP_MAX, CROSS_DROOP_MIN, cross_amt)   # more sag at low strength
    → flag tip = pole_top + (side * reach, droop), drawn in front, bright color

else:
    fwd_amt = clamp(abs(wind.y) / STRENGTH_NORM, 0, 1)
    if wind.y < 0:   # into wind
        scale = lerp(1.0, INTO_SCALE_MAX, fwd_amt)     # grows with strength
        → flag drawn in front of pole, bright color, sized by scale
    else:            # downwind
        scale = lerp(1.0, DOWN_SCALE_MIN, fwd_amt)     # shrinks with strength
        → flag drawn behind pole (pole drawn after, occludes part of it), muted color, sized by scale
```

## File changes — `scripts/ui/wind_flag.gd`

### Remove
- Line 6: `const TEX_FLAG := preload(...)` — no longer using the static sprite for the glance widget.
- Line 8: `const MAX_LEAN := 0.61` — rotation-based lean is gone.
- Lines 15, 24–33: the `_flag` `TextureRect` and its setup in `_ready()`.
- Lines 94–100: `_layout_flag_pivot()` — was only needed to keep the texture's rotation pivot correct; custom `_draw()` uses local coordinates directly, no pivot needed.
- Calls to `_layout_flag_pivot()` at lines 75, 83, 104.
- Lines 103–118 body (the rotation/lean/wave logic in `_process`) — replaced below.

### Add — new tunables (all provisional, confirm by playtest)

```gdscript
const STRENGTH_NORM := 40.0  ## mph at which tautness maxes out

const POLE_TOP_Y := 10.0
const POLE_BOTTOM_Y := FLAG_H - 6.0
const ATTACH_Y := POLE_TOP_Y + 6.0
const FLAG_LOCAL_H := 24.0

const CROSS_REACH_MIN := 14.0
const CROSS_REACH_MAX := 46.0
const CROSS_DROOP_MIN := 2.0
const CROSS_DROOP_MAX := 10.0

const BILLOW_BASE := 10.0
const INTO_SCALE_MAX := 1.9
const DOWN_SCALE_MIN := 0.25

const COLOR_FRONT := Color(0.886, 0.294, 0.290)   ## bright red — crosswind + into wind
const COLOR_BEHIND := Color(0.639, 0.176, 0.176)  ## muted red — downwind
```

### Add — new draw path (replaces old `_process` rotation logic + old flag texture)

```gdscript
func _process(delta: float) -> void:
    _t += delta
    queue_redraw()
    _refresh_axis_glyph()
    if _tip.visible and Time.get_ticks_msec() >= _tip_until_msec:
        _tip.visible = false


func _draw() -> void:
    var base_x := (size.x if size.x > 1.0 else custom_minimum_size.x) * 0.5
    var pole_from := Vector2(base_x, POLE_TOP_Y)
    var pole_to := Vector2(base_x, POLE_BOTTOM_Y)

    var use_crosswind := absf(_wind.x) >= absf(_wind.y)
    var strength_amt := clampf(_wind.length() / STRENGTH_NORM, 0.0, 1.0)
    var flutter := sin(_t * (1.5 + strength_amt * 3.0)) * 1.5 * strength_amt

    if use_crosswind:
        var side := signf(_wind.x) if absf(_wind.x) > 0.5 else 0.0
        var cross_amt := clampf(absf(_wind.x) / STRENGTH_NORM, 0.0, 1.0)
        var reach := lerpf(CROSS_REACH_MIN, CROSS_REACH_MAX, cross_amt)
        var droop := lerpf(CROSS_DROOP_MAX, CROSS_DROOP_MIN, cross_amt)
        draw_line(pole_from, pole_to, Color.WHITE, 4.0)
        _draw_flag(
            Vector2(base_x, ATTACH_Y),
            Vector2(base_x, ATTACH_Y + FLAG_LOCAL_H),
            Vector2(base_x + side * reach + flutter, ATTACH_Y + FLAG_LOCAL_H * 0.35 + droop),
            COLOR_FRONT
        )
    else:
        var fwd_amt := clampf(absf(_wind.y) / STRENGTH_NORM, 0.0, 1.0)
        if _wind.y < -0.5:
            var scale := lerpf(1.0, INTO_SCALE_MAX, fwd_amt)
            draw_line(pole_from, pole_to, Color.WHITE, 4.0)
            _draw_flag(
                Vector2(base_x, ATTACH_Y),
                Vector2(base_x, ATTACH_Y + FLAG_LOCAL_H * scale),
                Vector2(base_x + BILLOW_BASE * scale + flutter, ATTACH_Y + FLAG_LOCAL_H * 0.5 * scale),
                COLOR_FRONT
            )
        else:
            var scale2 := lerpf(1.0, DOWN_SCALE_MIN, fwd_amt)
            _draw_flag(
                Vector2(base_x, ATTACH_Y),
                Vector2(base_x, ATTACH_Y + FLAG_LOCAL_H * scale2),
                Vector2(base_x + BILLOW_BASE * scale2 + flutter, ATTACH_Y + FLAG_LOCAL_H * 0.5 * scale2),
                COLOR_BEHIND
            )
            draw_line(pole_from, pole_to, Color.WHITE, 4.0)


func _draw_flag(top: Vector2, bottom: Vector2, tip: Vector2, color: Color) -> void:
    draw_colored_polygon(PackedVector2Array([top, tip, bottom]), color)
```

### Unchanged
- `show_wind()` / `set_wind_vector()` / `hide_wind()` public API (lines 70–91) — same signatures, callers in `hole_controller.gd` (lines 1357, 1486, 1798, 1812, 1814) need no changes. Swap their body's `_layout_flag_pivot()` call for `queue_redraw()`.
- `_refresh_axis_glyph()` (lines 124–138) — kept as-is. It's no longer the *only* way to read direction, but it's a fine redundant cue (helps colorblind players, and confirms the mph reading), so no reason to rip it out.
- `_on_gui_input()` / `_show_tip()` (lines 141–164) — unchanged.

## Acceptance criteria

- Pole never rotates, at any wind vector — always drawn as a vertical line.
- Left/right wind: cloth bends sideways off the pole; short and droopy at low wind, long and straight-edged at high wind.
- Into wind: cloth is drawn in front of the pole, bright, and grows larger with wind strength.
- Downwind: cloth is drawn behind the pole (pole occludes part of it), muted color, and shrinks toward a sliver as wind strength increases.
- All four pure directions are identifiable without reading the "↑ INTO / ↓ HELP" caption.
- Strength is readable from tautness alone in all four directions.

## Out of scope (flagged, not blocking this epic)

- **Diagonal wind blending.** Right now the mode is chosen by whichever axis (`wind.x` vs `wind.y`) is larger — a wind vector with both components significant will snap to one mode rather than blend a sideways bend with a billow/tuck. That's a real gap; solving it properly (compositing both signals into one polygon) needs its own playtest pass and isn't part of what was mocked up.
- **Art pass.** The flag is currently a flat-color polygon (`draw_colored_polygon`), not the pixel-art `pin_flag.png`. That's intentional — a static sprite can't reshape into windsock/billow/tuck silhouettes — but it does trade away the hand-drawn look. A textured/pixel-art version of the same silhouette is a fine future polish pass, not needed to validate the mechanic.
- **`STRENGTH_NORM` and all `CROSS_*` / `INTO_SCALE_MAX` / `DOWN_SCALE_MIN` values** are starting points, not finals — confirm against how they read on-device before locking them in.

## Playtest order

1. Crosswind bend alone — left and right, each at low/medium/high strength. Confirm reach + droop reads as intended before touching anything else.
2. Into wind billow alone — low/medium/high. Confirm it reads as "coming at you," not just "bigger."
3. Downwind tuck alone — low/medium/high. Confirm it reads as "going away," not just "smaller" — the pole occlusion is doing real work here, check it's actually visible at phone size.
4. Rapid wind changes (hole transitions, wind gust variance) — check there's no rotation/flutter pop now that the draw model changed.
5. A few real diagonal wind vectors, just to see how ugly the dominant-axis snap looks in practice — informs whether the blending follow-up is urgent or can wait.

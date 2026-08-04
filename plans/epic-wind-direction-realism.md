# Epic: Wind Direction Realism

**Status:** Ready for implementation
**Repo:** `mendvibe-app/parorbetter`
**Source:** Playtesting observation — wind always reads as left-right (crosswind), never head/tailwind

---

## 1. Problem

Wind in *Par or Better* is supposed to come from any direction, the way it does on a real course. In practice, players only ever feel crosswind. Two separate issues combine to cause this:

1. **Generation bias.** Wind is generated at a genuinely random angle, but the down-course (head/tail) component is then deliberately suppressed relative to the crosswind component.
2. **UI blindness.** Even the (small) amount of head/tailwind that does get generated has no visual representation on the wind flag — only the numeric mph readout reflects it.

Net effect: wind *feels* left-right-only, even though the underlying data isn't 100% left-right-only — it's just heavily skewed and then partially hidden.

This matters for real-golf grounding specifically because head/tailwind is often the *more* important read for a golfer (it changes club selection directly), while crosswind mostly affects shot shape/aim. Suppressing it removes a core "read the conditions, pick the right club" skill from the game.

---

## 2. Root Cause

### 2a. Generation — `scripts/course/hole_generator.gd` (~line 341-347)

```gdscript
var wind_mag := lerpf(4.0, 52.0, t) * float(mods.get("wind_mult", 1.0))
wind_mag *= rng.randf_range(0.85, 1.15)
var wind_angle := rng.randf_range(0.0, TAU)
var wind := Vector2(cos(wind_angle), sin(wind_angle)) * wind_mag
# Prefer crosswind-ish Y components for readable UI (horizontal on portrait).
wind.x = clampf(wind.x, -60.0, 60.0)
wind.y = clampf(wind.y * 0.35, -20.0, 20.0)
```

`wind_angle` is a genuine full-circle random value, so the *intent* was always omnidirectional wind. But the clamp step afterward scales `wind.y` (head/tail, in this coordinate space) down to 35% strength and caps it at ±20, while `wind.x` (crosswind) is capped at ±60 — nearly 3x the ceiling. The comment confirms this was an intentional UI-readability tradeoff, not a bug: *"Prefer crosswind-ish Y components for readable UI (horizontal on portrait)."*

### 2b. Wind flag visualization — `scripts/ui/wind_flag.gd` (~line 89-94)

```gdscript
var strength := _wind.length()
...
var side := signf(_wind.x) if absf(_wind.x) > 0.5 else 0.0
```

The flag's lean direction is driven entirely by `_wind.x`. `_wind.y` (head/tail) is never read for the visual — only folded into the mph number via `_wind.length()`. So today, even a hole with meaningful headwind shows a flag that leans as if there's only crosswind, with the total strength number quietly including the head/tail contribution the player has no way to attribute.

### 2c. Confirmed NOT a problem — downstream physics

`scripts/ball/ball_physics.gd`, `recommended_power()` (~line 323-337):

```gdscript
wind_yards = -wind.y * 0.35 + absf(wind.x) * 0.08
```

Both axes are already correctly wired into club/power recommendation — `wind.y` (head/tail) has a larger coefficient than `wind.x` (crosswind), which is the correct real-golf weighting (headwind changes required carry more than crosswind does). **No changes needed here.** The bug is entirely upstream (generation) and in the UI (flag), not in how wind affects the shot.

---

## 3. Fix

### 3a. Generation — remove the axis bias

**File:** `scripts/course/hole_generator.gd`

```gdscript
# Before:
var wind_angle := rng.randf_range(0.0, TAU)
var wind := Vector2(cos(wind_angle), sin(wind_angle)) * wind_mag
# Prefer crosswind-ish Y components for readable UI (horizontal on portrait).
wind.x = clampf(wind.x, -60.0, 60.0)
wind.y = clampf(wind.y * 0.35, -20.0, 20.0)

# After:
var wind_angle := rng.randf_range(0.0, TAU)
var wind := Vector2(cos(wind_angle), sin(wind_angle)) * wind_mag
# Full-circle wind, matching real golf — no axis bias.
wind.x = clampf(wind.x, -60.0, 60.0)
wind.y = clampf(wind.y, -60.0, 60.0)
```

Both axes now share the same ceiling and no attenuation. `wind_angle` was already uniformly random across the full circle — this just stops throwing away the head/tail portion of it.

### 3b. Wind flag — surface head/tailwind visually

**File:** `scripts/ui/wind_flag.gd`

Add a visual cue for the head/tail component alongside the existing crosswind lean. The lean (`_wind.x`-driven) stays as-is — this is additive, not a redesign. Two implementation options for the agent to choose based on what fits the existing art/animation approach:

- **Option A (billow/silhouette):** flag appears flatter/thinner against the pole when wind is blowing into the camera (headwind) and fuller/more extended when blowing away (tailwind), using the sign and magnitude of `_wind.y`.
- **Option B (icon overlay):** a small directional glyph (↓ "into" / ↑ "helping") near the mph readout, driven by `_wind.y`, shown whenever `absf(_wind.y) > 0.5` (matching the existing dead-zone threshold pattern used for `side` on line 94).

Option B is lower-risk (no new animation curves) and is the recommended default unless the agent judges Option A is a small lift given existing texture/animation infrastructure.

**Acceptance criteria (flag):**
- A player can tell at a glance whether wind is helping, hurting, or purely crossing — not just its strength — without tapping for the advice tooltip.
- Existing crosswind lean behavior is unchanged.
- No changes to `_wind.length()` / mph readout — that's already correct.

---

## 4. Out of Scope

- Any change to `ball_physics.gd` wind coefficients — already correct, do not touch.
- Any change to how wind affects aim assist / shot shape — not part of this epic.
- Redesigning the flag widget beyond adding the head/tail cue.
- Per-hole wind "themes" (e.g. always-into-the-green closing holes) — future idea, not this epic.

---

## 5. Acceptance Criteria (Epic-level)

- Across many generated holes, wind direction is uniformly distributed around the full circle — headwind and tailwind occur with similar frequency and strength to crosswind, not suppressed to a fraction of it.
- The wind flag visually communicates head/tail as well as crosswind.
- Club/power recommendation behavior is unchanged (no physics regressions) — headwind should still call for more club, tailwind less, same as today's correct-but-underused logic.

---

## 6. Playtest Order

1. **Generation fix in isolation.** Play or debug-generate several holes in a row; confirm wind direction feels genuinely random, not always left-right. Use `debug_controls.gd`'s existing wind debug hooks if available to spot-check distribution rather than relying on feel alone.
2. **Flag UI fix on top.** With generation fixed, confirm you can read into/helping/crossing at a glance on holes with strong head/tailwind, without checking the mph number or advice tooltip.
3. **Full swing pass.** Hit shots into headwind and downwind on the same club/distance to confirm the power recommendation swing feels appropriately different (headwind shots should call for materially more club).

---

## 7. Notes / Tuning Flags

- The ±60 ceiling on both axes is carried over unchanged from the existing crosswind cap — not a new tunable, just now applied symmetrically. If headwind ends up feeling too punishing relative to crosswind once it's no longer suppressed, the fix is to revisit the `wind_yards` coefficients in `ball_physics.gd` (`-wind.y * 0.35` vs `wind.x * 0.08`), not to re-suppress generation.
- If Option A (billow) is chosen for the flag and proves too subtle to read at a glance during playtesting, fall back to Option B (icon overlay) rather than exaggerating the billow animation — legibility over cleverness.

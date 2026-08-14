# Correction — Suggested Shape Must Follow Real Hole Geometry

**Track:** correction, outside the numbered phase tracks
**Branch:** `fix/suggested-shape-geometry`, from main after `fix/remove-hole-shape-bias`
**Found by:** Matt noticing a suggested-shape cone bend on a hole that looks straight.
**Depends on:** `fix/remove-hole-shape-bias` (already shipped) — that fix stopped the
suggestion from *forcing* curve on the ball. This fix stops the suggestion from *existing*
when there's no real reason for it.

---

## The bug

```gdscript
// hole_generator.gd:1108-1123
static func _suggested_shape(
	layout: HoleData.LayoutStyle,
	bias: HoleData.HazardBias,
	rng: RandomNumberGenerator
) -> HoleData.SuggestedShape:
	match layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			return HoleData.SuggestedShape.FADE
		HoleData.LayoutStyle.DOGLEG_LEFT:
			return HoleData.SuggestedShape.DRAW
		_:
			if bias == HoleData.HazardBias.RIGHT:
				return HoleData.SuggestedShape.FADE if rng.randf() < 0.65 else HoleData.SuggestedShape.STRAIGHT
			if bias == HoleData.HazardBias.LEFT:
				return HoleData.SuggestedShape.DRAW if rng.randf() < 0.65 else HoleData.SuggestedShape.STRAIGHT
			return HoleData.SuggestedShape.STRAIGHT
```

The two dogleg cases are correct — `LayoutStyle.DOGLEG_LEFT`/`DOGLEG_RIGHT` are real fairway
geometry, and suggesting a matching shape is exactly what real golf does.

**Every non-dogleg layout (`STANDARD`, `ISLAND`, `CHUTE`, `BI_TIER`) falls into the default
branch**, which ignores geometry entirely and keys off `hazard_bias` — a value generated
independently, one coin flip earlier:

```gdscript
// hole_generator.gd:376
hazard_bias = HoleData.HazardBias.LEFT if rng.randf() < 0.5 else HoleData.HazardBias.RIGHT
```

`hazard_bias` just means "a hazard exists somewhere on this side of the hole." It carries no
information about fairway curvature. So on a perfectly straight hole with a bunker on one
side, `_suggested_shape` still has a **32.5% chance** (50% hazard-side roll × 65% shape roll)
of suggesting DRAW or FADE for no geometric reason at all.

**This is exactly the case Matt caught: a straight 416-yard hole suggesting a shape, purely
because a bunker happened to spawn on one side.**

---

## Why this matters even after the physics fix

`fix/remove-hole-shape-bias` correctly made the suggestion advisory-only — it no longer
forces curve on the ball. But an advisory suggestion is only useful if it's *true*. Real golf
coaching material is unanimous that shape suggestions come from fairway curvature or hazards
directly in the shot's line — never from an unrelated hazard on an otherwise straight hole.
A cone that bends for no visible reason doesn't read as advice; it reads as a bug, which is
exactly how Matt found this.

---

## The fix

Only suggest a shape when there's a real geometric or line-of-play reason:

```gdscript
static func _suggested_shape(
	layout: HoleData.LayoutStyle,
	bias: HoleData.HazardBias,
	rng: RandomNumberGenerator
) -> HoleData.SuggestedShape:
	match layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			return HoleData.SuggestedShape.FADE
		HoleData.LayoutStyle.DOGLEG_LEFT:
			return HoleData.SuggestedShape.DRAW
		_:
			# Non-dogleg layouts: no fairway curvature to play around. A hazard existing
			# somewhere on the hole is not, by itself, a reason to shape a shot — real golf
			# only suggests shaping around a hazard that's actually in the shot's direct
			# line, which this generator does not currently model. PLAYTEST TARGET: if hazard
			# placement is later made line-aware, this can key off that instead of returning
			# STRAIGHT unconditionally.
			return HoleData.SuggestedShape.STRAIGHT
```

**Simplest correct fix: non-dogleg layouts always return STRAIGHT.** The alternative —
keeping some probabilistic hazard-based suggestion — would require `hazard_bias` (or a new
signal) to actually mean "hazard is in my direct line," which it doesn't today and isn't in
scope to build here. Report if you see a cheap way to make that real; otherwise STRAIGHT is
the honest answer for what the generator currently knows.

---

## Out of scope

- `hazard_bias` itself, hazard placement, or bunker/water generation. Untouched.
- The dogleg cases — already correct, don't touch.
- `fix/remove-hole-shape-bias`'s physics change. Already shipped, unrelated layer.
- Building line-of-play hazard detection to make a smarter non-dogleg suggestion. Flagged as
  a possible future improvement in the code comment, not this fix.

---

## Acceptance criteria

1. Every `STANDARD`/`ISLAND`/`CHUTE`/`BI_TIER` hole generates with `suggested_shape ==
   STRAIGHT`, unconditionally — confirm across a large generated sample, not just a few holes.
2. `DOGLEG_LEFT`/`DOGLEG_RIGHT` holes are unaffected — still DRAW/FADE respectively.
3. The aim cone no longer bends on any non-dogleg hole.
4. All `*_check.py` pass.

---

## Playtest verification

1. Generate or find several straight (`STANDARD`) holes, including ones with hazards on one
   side. Confirm the cone renders symmetric on all of them.
2. Confirm a `DOGLEG_LEFT`/`DOGLEG_RIGHT` hole still shows the correct bend.

---

## Notes for the agent

- This should be a small, contained change — one function.
- Read this document and confirm understanding before writing code.
- Confirm there are no other callers of `_suggested_shape` or consumers of
  `HazardBias` that assumed the old probabilistic behavior before removing it.

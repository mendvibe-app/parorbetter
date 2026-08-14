# Correction — Target/Pocket Marker Visual Clarity

**Track:** swing-input, ahead of the formal Phase 6 feel pass
**Branch:** `fix/marker-visual-clarity`, from main
**Size:** one draw function, no new data, no mechanic change.
**Prompted by:** two live repro shots this session — a lob wedge pitch that flew 51 yd
carrying (aim implied ~40%, actual pull 98% of lane) and, worse, a pitch that flew clean over
the green into the far rough on the same pattern. Both hit despite "Pure"/PERFECT contact.

---

## The bug, found in the actual draw code

```gdscript
// tempo_gesture.gd:857-861
var pocket := clampf(full_pocket_frac, 0.0, 1.2)
var tgt := clampf(full_target_frac, 0.0, 1.2)
// Pocket — amber, shorter tick (mash threshold).
draw_line(pocket_pt + Vector2(-16, 0), pocket_pt + Vector2(16, 0), Color(1.0, 0.72, 0.2, 0.9), 3.0, true)
// Target — cool tick (suggested pull for this aim).
draw_line(tgt_pt + Vector2(-22, 0), tgt_pt + Vector2(22, 0), Color(0.55, 0.95, 1.0, 0.95), 3.5, true)
```

**Both marks are the same shape** — a plain horizontal line — differing only by color and 6
pixels of width. There is no glow, no fill, no visual weight difference. Nothing about either
mark's *shape* tells you which one is "aim for this" versus "avoid this."

This matches, independently, two blind playtester findings from earlier research: one
critique tester misread the pocket line as "the sweet spot to land inside," and a generative
tester designing blind from scratch produced a glowing, dominant target versus a harsh,
hazard-striped ceiling — the correct hierarchy, arrived at with zero exposure to this code.

**And it explains the live repro directly.** On pitch/flop's short lane (`0.50` vs full
swing's `0.62`), `tgt_pt` and `pocket_pt` sit close together in absolute screen space. Two
nearly-identical ticks, close together, on a lane you're not staring at during a natural
swing motion — there's very little chance either one registers before your thumb sails past
both.

---

## Why this is the right first move, and what it won't fix alone

This is cheap, safe, and it's the fix both independent testers converged on. It should help
the player who glances at the pad. **It will not fully solve "I swung naturally and it went
way past the target"** — a natural, confident motion isn't something a player is consciously
reading a mark against mid-swing. The deeper fix for that is haptic feedback at the
target/pocket crossing (already scoped in `epic-contact-quality-haptics.md`, blocked on
Android Custom Build setup) and possibly the amplitude curve itself. Both are explicitly out
of scope here — this correction is the fast, low-risk piece, not the whole answer.

---

## The fix

Differentiate by shape, not just color, and make the target visually dominant since it's the
mark relevant on every non-max-power shot, while the pocket is a warning relevant mainly when
pushing for max distance.

```gdscript
func _draw_full_amplitude_markers() -> void:
	var start := address_hint()
	var top := top_hint()
	var pocket := clampf(full_pocket_frac, 0.0, 1.2)
	var tgt := clampf(full_target_frac, 0.0, 1.2)
	var pocket_pt: Vector2 = start.lerp(top, minf(pocket, 1.0))
	var tgt_pt: Vector2 = start.lerp(top, minf(tgt, 1.0))

	# Pocket — hazard-striped, harsh amber/red. A warning to avoid, not a target.
	# PLAYTEST TARGET: exact stripe pattern and color.
	_draw_hazard_tick(pocket_pt, Color(0.95, 0.35, 0.25, 0.9))

	# Target — dominant glow + solid tick. The mark relevant on nearly every shot.
	# PLAYTEST TARGET: glow radius and intensity.
	draw_circle(tgt_pt, 14.0, Color(0.55, 0.95, 1.0, 0.18))
	draw_line(tgt_pt + Vector2(-24, 0), tgt_pt + Vector2(24, 0), Color(0.6, 1.0, 1.0, 1.0), 4.5, true)
```

`_draw_hazard_tick()` is a small new helper — a short dashed/barred line rather than a solid
one, so the shape itself reads as "caution" independent of color (colorblind-safe, matches
real hazard signage conventions rather than relying on color alone).

**Apply this to every shot type that uses these markers** — full, pitch, flop, punch all share
`_draw_full_amplitude_markers()`, so this one fix covers all four automatically. No per-shot-
type work needed.

**Putt/chip's marker** (`putt_target_frac`, drawn separately around line 693/1205) should get
the same target-dominance treatment for consistency, even though its overswing consequence
differs (smash-long vs mash-tax) — the *target* half of the visual language should look and
feel the same everywhere, only the ceiling/warning styling differs by shot family.

---

## Out of scope

- Haptics. Separate, already-scoped epic, blocked on Android setup — not touched here.
- The amplitude curve, lane length, or floor/ceiling values for any shot type.
- Free-motion path/meter separation, impact/follow-through visualization. Bigger design
  questions from the findings doc, not this pass.
- Any change to `power_from_amplitude`, `force_factor`, or grading.

---

## Acceptance criteria

1. Target and pocket marks are visually distinguishable by shape, not only color.
2. Target marker reads as visually dominant (glow/fill) versus the pocket's plain warning
   styling.
3. Change applies uniformly to full, pitch, flop, punch (all via the shared draw function),
   and consistently to putt/chip's target styling.
4. No change to any gameplay value — pure draw-layer change. Confirm no `*_check.py` needs
   updating (this is visual only, no logic assertions should reference these colors/shapes).
5. Flight and swing-input goldens unaffected — this touches drawing, not calculation.

---

## Playtest verification

1. Hit a pitch or flop and glance at the pad before swinging — can you tell which mark is the
   target and which is the ceiling without reading the hint text?
2. Recreate the repro shot as closely as possible: aim a short pitch, then swing naturally
   without deliberately watching the pad. See if the visual difference registers peripherally
   at all, or if — as predicted — a visual-only fix isn't enough for a genuinely natural
   swing. Report honestly either way; this data point matters for whether haptics needs to be
   unblocked next.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `tempo_gesture.gd` (the draw function and the new hazard-tick helper).
- This is a small, low-risk, visual-only change. If it turns out to need anything beyond the
  draw layer, stop and report before expanding scope.

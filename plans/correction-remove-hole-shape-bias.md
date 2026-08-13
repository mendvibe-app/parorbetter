# Correction — Hole Shape Bias Removal (re-applying the original ruling)

**Track:** correction, outside the numbered phase tracks
**Branch:** `fix/remove-hole-shape-bias`, from main
**Found by:** Matt noticing the aim cone bends on some holes, tracing it back to `suggested_shape`
still contributing to actual shot curve.

---

## This is not a new decision — it's an unmerged one

Early in this project, Matt ruled explicitly: **hole-shape-forcing should not exist at all.**
That ruling produced a stash (`wip shape-forcing-out-of-phase0`) that was reviewed, approved,
and scheduled to land as its own PR. It never merged — lost in the sequence of everything that
happened afterward. `hole_controller.gd`'s `shape_amt = ±0.35` injection is still live on main
today, feeding directly into `shot_routine.gd`'s shape calculation.

This correction re-applies that original ruling, now grounded a second time to confirm it —
both against real golf and against Matt's own stated design principle from this project's
outset: *"Player swipe must own direction. Tempo and hole state may modulate dispersion but
must not generate competing directional signals."*

---

## Grounding

**Real golf gives an unambiguous answer.** A hole's dogleg or hazard placement is a reason a
golfer *chooses* to attempt a draw or fade — it is never a force that curves the ball for
them. There is no physical mechanism connecting course geometry to ball flight; only the
player's actual swing (path, face angle, spin) determines shape. One golf-instruction source
puts the counterfactual plainly: *"If you fail to hit a draw and instead hit the ball
straight, you'll still be on the fairway, albeit further from the pin"* — missing the
suggested shape produces a straight ball, not an automatic bend toward what the hole
"wanted."

**This matches the project's own principle exactly**, stated before this correction was ever
discussed. The hole may inform the player (via the cone bend, or hint text) what shape would
be advantageous. It must never generate curve on its own.

---

## What's actually live today (traced, not assumed)

```gdscript
// hole_controller.gd:2008-2016 — computed every shot on non-Green lies
var shape_amt := 0.0
if lie != "Green":
	match hole.suggested_shape:
		HoleData.SuggestedShape.DRAW:
			shape_amt = -0.35
		HoleData.SuggestedShape.FADE:
			shape_amt = 0.35
		_:
			shape_amt = 0.0
// ...passed into shot_routine.configure(), stored as suggested_shape
```

```gdscript
// shot_routine.gd:569 — the only place suggested_shape reaches live physics
shape = clampf(suggested_shape * 0.45 + modulated * 0.75 * auth, -1.0, 1.0)
path = shape  // path_error == intended_shape for full/pitch/punch
```

**One pipeline, not two competing ones** — confirmed by trace, not assumption. `shape_amt` is
computed once and flows through a single variable to a single formula.

**Two other `suggested_shape` reads in `shot_routine.gd` do not need changing:**
- Line 521 is the pre-branch default, overwritten by every real branch below it.
- Line 546 is inside `GameState.force_perfect`, a debug/QA-only path, not live gameplay.
- Putt/chip (line 524) already ignores `suggested_shape` entirely — direction there comes from
  `PuttStroke`'s `path_error`.

The fix is exactly one line.

---

## The fix

```gdscript
// shot_routine.gd:569 — before
shape = clampf(suggested_shape * 0.45 + modulated * 0.75 * auth, -1.0, 1.0)

// after
shape = clampf(modulated * 0.75 * auth, -1.0, 1.0)
```

`suggested_shape` remains fully alive as data — `hole.suggested_shape`, `shape_amt`, and the
aim cone's `_aim_shape_bend()` visual are untouched. It stops being an input to physics. A
straight swipe on a DRAW-suggested hole now produces a straight shot, the same way a real
golfer who doesn't execute their intended draw just hits it straight.

---

## Out of scope

- The aim cone's visual bend (`_aim_shape_bend()`, `AimControl.make_aim_cone()`). Confirmed
  cosmetic-only already; no change needed or wanted — this is the correct "advisory" version
  of hole shape, matching how real golf informs a player's shot selection.
- `hole.suggested_shape` generation (`hole_generator.gd`). Holes should still have doglegs and
  hazard bias; that's course design, not this correction.
- Any change to swipe/pull/dispersion weighting (`modulated * 0.75 * auth`). Untouched —
  only the removed term changes, not the remaining formula's balance.

---

## Acceptance criteria

1. A straight, well-timed swipe on a DRAW or FADE hole produces a straight shot (`path ≈ 0`),
   not a curved one.
2. The aim cone still bends on DRAW/FADE holes exactly as before — purely visual, unaffected.
3. Putt/chip, punch, and the debug force-perfect/force-mishit paths are unaffected — confirm
   bit-identical, not just "should be fine."
4. All `*_check.py` pass.
5. Flight goldens unchanged (this is upstream of flight, in shot-shape territory, but confirm
   nothing downstream moved).

---

## Playtest verification

1. Hit a straight swipe on a hole with a DRAW or FADE suggestion. Confirm the ball flies
   straight along your aim line, not curved toward the suggestion.
2. Deliberately swipe with a draw/fade shape yourself on the same hole. Confirm your swipe's
   shape still comes through correctly — this fix removes the hole's contribution, not the
   player's.
3. Confirm the cone still visually bends on suggestion holes, so the coaching information
   isn't lost — only its effect on the ball is gone.

---

## Notes for the agent

- This should be a true one-line change plus verification. If tracing reveals a second live
  consumer of `suggested_shape` that this document missed, stop and report before proceeding.
- Read this document and confirm understanding before writing code.

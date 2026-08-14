# Correction — TV Broadcast Feel: Putt Zoom, Hole-Out, Global Pacing

**Track:** correction, found live during playtest
**Branch:** three separate branches recommended — different systems, different risk levels
**Size:** small / small / potentially large. Written up for tomorrow, not implemented tonight.

Three distinct findings from the same playtest note. Kept in one doc because they share a
theme (matching real broadcast golf feel) but they touch different code and should ship as
separate, independently-attributable changes.

---

## 1. Putt camera zoom — smaller than it looks

**Confirmed: this is already more built than the complaint suggests.**
`camera.zoom = _desired_camera_zoom()` runs every frame via `_process()`
(`hole_controller.gd:1645`), and for putts that function computes zoom directly from
`ball.global_position.distance_to(_cup_pos)` — a live distance that shrinks continuously as
the ball rolls. **The zoom is not fixed at address; it's already tightening in real time as
the ball approaches the cup.**

So this isn't "add dynamic zoom" — it's "the existing dynamic zoom doesn't feel dramatic
enough." That's a curve-shape question, not a missing-feature question:

```gdscript
// hole_controller.gd, _desired_camera_zoom(), putt branch
var half_span := maxf(dist * 0.90 + 6.0, 12.0)
z = clampf(view_min * 0.52 / half_span, 2.6, 42.0)
```

Zoom scales roughly linearly with distance today (`half_span` is close to linear in `dist`).
TV broadcast zoom tends to hold wider for longer, then accelerate sharply in the last several
feet — a non-linear curve, not a straight ramp. Worth trying an eased/exponential relationship
between `dist` and `half_span` for the last ~10-15 ft specifically, rather than changing the
overall zoom range.

**Do not touch the 2.6/42.0 clamp bounds without checking they still work at the extremes** —
those were already tuned once per the existing code comment about short putts reading tighter
than 20-40 ft ones.

### 1b. Post-make camera sequence reads as jarring — replace punch-zoom with a clean fade

**Confirmed the exact motion causing this.** `_on_holed_out()` zooms the camera in
(`close_z = 3.15`) over 0.42s, holds briefly, then zooms back out (`hold_z = 2.55`) over
0.55s — an in-then-out camera punch. The code's own comment shows this was already softened
once (*"no jarring 6× punch"*), but the remaining in/out motion is still what's being flagged
now.

**Proposed direction, and it's mostly wiring, not new UI:** replace the zoom-punch with a
clean fade showing the hole result — and the label to do this already exists, unused for
this exact moment:

```gdscript
// hole_controller.gd:159 — already declared, already wired elsewhere
@onready var birdie_label: Label = $UILayer/BirdieBanner
```

Its existing usage (`hole_controller.gd:3183-3195`) already does precisely the pattern
described — set `.text` to `"%s (%+d)" % [Scoring.label(result).to_upper(), diff]`, fade
alpha 0→1 over 0.15s, hold, fade 1→0 over 0.25s. `_on_holed_out()` already computes `result`
and `diff` a few lines below the camera tween — the data needed is already local to the
function, just not connected to this label.

**Concretely:** in `_on_holed_out()`, replace the `close_z`/`hold_z` zoom-punch tween with a
smaller, single settle (or none at all — hold current zoom steady) and trigger
`birdie_label`'s existing fade sequence with the hole's result text. This should be small —
reusing an existing, already-tuned pattern rather than building a new fade system.

**Keep:** `AudioBus.play_putt_drop()`, the `flash_rect` flash (that's a quick sparkle, not the
jarring part), and the camera move to `_cup_pos` — only the in/out zoom punch is what's being
replaced.

---

## 2. Ball doesn't visually drop into the cup

**Confirmed, precisely.** `_try_cup_capture()` in `ball.gd` does this on a make:

```gdscript
velocity = Vector2.ZERO
state = State.SETTLED
set_physics_process(false)
holed_out.emit()
```

**Nothing happens to the ball itself.** All the polish — `flash_rect`, the camera's
zoom-punch tween, `AudioBus.play_putt_drop()` — happens at the camera/screen level in
`hole_controller.gd`'s `_on_holed_out()`. The ball sprite just stops, sitting exactly where it
was, on top of the cup rather than in it. That's the precise cause of "never feels like it
goes in."

**Proposed direction:** a small, fast tween on the ball itself at the moment of capture —
scale down slightly (e.g., 1.0 → 0.4 over ~0.15s) and/or a brief darken (modulate toward black
or reduce alpha) before the camera's existing celebration sequence takes over. This should be
a short, cheap addition to `_try_cup_capture()` or a signal handler on `holed_out`, not a
rebuild of the existing camera work — that part already works well per your own note about it
being "soft" and non-jarring.

**Coordinate timing with the existing camera tween** — `_on_holed_out()`'s camera sequence
starts immediately on the `holed_out` signal; a ball-drop animation should either complete
just before or blend with that, not fight it for visual attention.

---

## 3. Global flight/roll pacing feels fast — revisits a decision you already tested

**This is not a small tweak — flagging that directly before anything else.** `GRAVITY_PX =
535.0` is the master pacing constant from Phase 1, and you confirmed it explicitly on device
after playing full swings, drives specifically included, with the note *"driver felt great."*
This finding says the opposite, now that far more of the game has been played since. Both can
be true — a driver in isolation can feel right while the *aggregate* pace across every shot
type, including roll-out (governed by `roll_friction_for()`'s four lie values: `1.8 / 2.4 /
4.5 / 7.0`), reads as fast once you're comparing it to real broadcast pacing over many holes
rather than a few test swings.

**Before changing anything:** decide whether this is really about `GRAVITY_PX` (flight hang
time) or about roll duration (friction values), or both — they're independent knobs and
"everything feels fast" could be either, or an interaction between them. Real TV golf reads
slow partly because commentary and cutaways fill dead time, not purely because the ball
itself moves slowly — worth being honest that "matching broadcast pacing" is partly a
*presentation* question (camera holds, cuts) as much as a *physics* one. Don't assume the fix
is entirely a physics constant.

**Recommended approach, given the size of this:**
1. Isolate the two knobs — test `GRAVITY_PX` alone (raise hang time) against roll friction
   alone (lower deceleration, longer roll) as separate experiments, not one combined change.
2. Re-confirm on device with the same rigor as the original Phase 1 approval — hit real
   shots, specifically including drivers, since that's the one already explicitly signed off
   and most likely to have an opinion change.
3. If both need adjusting, do it as two small, separately-attributable passes, not one
   sweeping constant change — same discipline as everything else this session.

**Do not implement a global slowdown tonight or without a fresh device confirmation** — this
constant was deliberately marked `PLAYTEST TARGET` for exactly this kind of revision, but
changing it silently would undo a decision you made deliberately and tested carefully.

---

## Out of scope (all three)

- Any change to putt physics itself (`power_from_frac`, contact grading) — camera/visual only
  for items 1 and 2.
- Flight model correctness (apex, carry, hang formulas) — item 3 is about the pacing constant,
  not the model's accuracy, which is settled.
- Camera behavior during full-swing flight (`_flight_camera_zoom()`) — not mentioned in this
  complaint, don't touch incidentally.

---

## Notes for the agent

- These are three separate write-ups bundled in one doc for context. Scope, branch, and
  implement them independently — don't combine into one PR.
- Item 3 in particular: read the Phase 1 approval history in
  `plans/flight-model-rebuild-roadmap.md` before touching `GRAVITY_PX`, and treat any change
  as reopening a confirmed decision, not a routine tweak.
- Confirm understanding of each section before writing code for it.

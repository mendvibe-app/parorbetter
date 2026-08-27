# Epic — Putting green true-scale (ball, hole, catch radius)

**Deliverable path (on approve):** `plans/putt-true-scale-phase1.md`
**Status:** SHIPPED — geometry in build. Camera follow-up: `putt-true-scale-phase2.md`. Next track: `putting-rework-roadmap.md`.
**Track:** epic, found live during playtest (24 ft putt captured well outside the visible dark disc's real-world footprint)
**Scope:** `BALL_R_PUTT`, `CUP_RADIUS`, `CUP_CAPTURE_RADIUS` — geometry only. No break/slope, no camera/zoom.
**Sequencing:** Phase 1 of 2. Phase 2 (camera/zoom rework, tracked separately) must land immediately after — see §6.

---

## 1. Root cause

The game has one real-world ruler used everywhere (yardage, wind, aim, the on-screen "N ft" readout): `PX_PER_YARD := 2.25` (`ball_physics.gd:7`), i.e. **0.75 world-px per real foot**.

`BALL_R_PUTT`, `CUP_RADIUS`, and `CUP_CAPTURE_RADIUS` are all defined in that same world-unit space, but were tuned by eye at the putting camera's zoomed-in framing (`putt-ball-visible-size.md` fixed the ball∶hole *ratio* to a correct 2.53, matching real 4.25″/1.68″ — but never checked the *absolute* size against the real-foot ruler). Converting the current constants back to real feet:

| Constant | Current (world units) | → real feet | → real inches |
|---|---|---|---|
| `CUP_CAPTURE_RADIUS` | 1.9 | 2.53 ft radius | **30.4″ radius** (5.07 ft **diameter**) |
| `CUP_RADIUS` (visible dark disc, 43/64) | 1.9 (same disc — see=catch) | 2.53 ft radius | 30.4″ radius |
| `BALL_R_PUTT` (visible opaque, 33/64) | 0.744 | 0.99 ft radius | 11.9″ radius |

A real cup is 2.125″ radius. **The make/miss test is currently ~14x wider than a real hole.** This is why moderate pace and moderate aim both hole out — the ball only needs to finish within ~2.5 real feet of true center, in any direction.

The ball∶hole *ratio* (2.53) is already correct and does not need to change — this is purely an absolute-scale fix, holding that ratio fixed.

---

## 2. Target constants (derived, not eyeballed)

Anchor: real ball radius 0.84″ = 0.07 ft; real cup radius 2.125″ = 0.1771 ft. Convert through the same `PX_PER_YARD`-derived ruler (0.75 world-px/ft) and back out through the sprite fill fractions already established in `putt-ball-visible-size.md` (ball opaque 33/64, cup dark-disc 43/64):

```text
BALL_R_PUTT_target  = (0.07 * 0.75) * 64 / (33 * 2)  ≈ 0.102
CUP_RADIUS_target    = (0.1771 * 0.75) * 64 / (43 * 2) ≈ 0.198
CUP_CAPTURE_RADIUS_target = (43/64) * CUP_RADIUS_target ≈ 0.133   # see=catch, pure geometric hole radius
```

| Constant | Current | Target | Change |
|---|---|---|---|
| `BALL_R_PUTT` | 1.44 | **0.102** | ÷14.1 |
| `CUP_RADIUS` | 2.8 | **0.198** | ÷14.1 |
| `CUP_CAPTURE_RADIUS` | 1.9 | **0.133** | ÷14.3 |

`CUP_CAPTURE_RADIUS_target` above is the **pure geometric value** — ball-center must land within the true hole radius, zero lip-catch cushion, zero mobile-input forgiveness. Flag as **PLAYTEST TARGET**: if tap-ins and dying putts feel unfairly harsh with zero cushion, the acceptable real-golf range for a generous trickle-catch is **0.080–0.185** world units (hole radius ± ball radius). Do not preemptively widen it — ship the strict value first and let Matt's playtest decide.

---

## 3. Expected consequence — flag, don't "fix" in this PR

At current camera zoom (`PUTT_ZOOM_CAP := 24`), a hole with `CUP_RADIUS = 0.198` world units renders at roughly **6–10 screen px** diameter — a barely-visible dot. The ball will be similarly tiny. **This is expected and correct for Phase 1.** Camera/zoom rework is Phase 2 and is tracked separately; do not touch `PUTT_ZOOM_CAP` or any camera code in this PR to compensate. Verify Phase 1 correctness via the debug ft readout and check-script math, not by eye.

Shadow/glow/spin_fx scale automatically from `r` in `_apply_lie_visual()` (`ball.gd:448-464`) — they will shrink proportionally with no code change needed. Also expected, also out of scope.

---

## 4. Proposed change

**Files:**

1. `scripts/ball/ball.gd`
   ```gdscript
   ## True real-world scale (0.75 world-px/ft, from BallPhysics.PX_PER_YARD).
   ## Real ball radius 0.84" → 0.102 world units through 33/64 sprite fill.
   ## Ratio to CUP_RADIUS held at real 2.53 (see putt-ball-visible-size.md). Visual only.
   const BALL_R_PUTT := 0.102
   ```
   ```gdscript
   ## True real-world scale. Real cup radius 2.125" → 0.133 world units through
   ## 43/64 dark-disc fill. PLAYTEST TARGET — pure geometric radius, zero lip-catch
   ## cushion. Widen toward 0.185 if dying putts feel unfairly harsh; range derives
   ## from hole_radius ± ball_radius, see epic §2.
   const CUP_CAPTURE_RADIUS := 0.133
   ```

2. `scripts/course/hole_controller.gd`
   ```gdscript
   ## True real-world scale. Real cup radius 2.125" → 0.198 world units.
   ## Capture uses CUP_CAPTURE_RADIUS (dark disc, see=catch) — see ball.gd.
   const CUP_RADIUS := 0.198
   ```

3. `scripts/ball/putt_pace_check.py` — update literal assert at line 160 (`"CUP_RADIUS := 2.8" or "CUP_RADIUS := 2.4"`) to accept `0.198`. Ratio-based asserts (lines ~184–197) should pass unchanged since they test the 43/64 relationship, not absolute size — verify after edit.

4. `scripts/ball/cup_lip_out_check.py` — update literal assert (`"CUP_CAPTURE_RADIUS := 1.9"`) to `0.133`.

5. `scripts/course/hole_out_feel_check.py` — update literal assert (`"CUP_CAPTURE_RADIUS := 1.9"`) to `0.133`.

---

## 5. Out of scope — do not touch

- `PUTT_ZOOM_CAP`, `_desired_camera_zoom()`, any camera/zoom code (Phase 2)
- `PUTT_BREAK_LATERAL`, `PUTT_BREAK_ALONG`, or any slope/break tuning — re-evaluate only after Phase 1 + Phase 2 ship, since the current giant catch radius has been masking whatever the break system is actually doing
- `BALL_R := 3.5` (full-flight ball, untouched — putting-only fix)
- Shadow/glow/spin_fx multipliers in `_apply_lie_visual()` — proportional, no change needed
- Lip-in orbit/pour constants (`LIP_ORBIT_MAX`, `LIP_CENTER_OFFSET_MAX`, etc.) — separate system, separate epic if they need retuning post-shrink
- Regenerating `ball.png` / `cup.png`
- Any file not listed in §4

---

## 6. Sequencing note for Matt / next agent

Phase 2 (camera/zoom rework) is not optional polish — until it ships, putting is effectively unplayable by eye (true-scale hole is a few px wide). Phase 1 should be played/verified via the numeric "N ft" readout and make/miss logging, not visual inspection. Do not delay merging Phase 1 waiting for Phase 2 — ship as separate PRs per standing one-phase-per-PR rule, but treat them as a locked pair for playtest purposes (Phase 1 alone will read as a regression, expected).

---

## 7. Acceptance criteria

- [ ] `python scripts/ball/putt_pace_check.py` passes with updated literals
- [ ] `python scripts/ball/cup_lip_out_check.py` passes with updated literal
- [ ] `python scripts/course/hole_out_feel_check.py` passes with updated literal
- [ ] `CUP_CAPTURE_RADIUS` in world units converts to **≤ 2.4″ real radius** (regression test: was 30.4″)
- [ ] Ball∶cup visible ratio unchanged at **2.53 ± 0.06** (regression test against `putt-ball-visible-size.md`)
- [ ] No changes to any file outside §4
- [ ] Make rate on a known-offline 24 ft putt test case drops sharply vs current build (numeric/log verification — not required to be visually confirmable pre-Phase 2)

---

## 8. Handoff

On approve: copy this doc to `plans/putt-true-scale-phase1.md`. Agent reads, confirms understanding, implements §4 only, runs all three check scripts before opening PR. Camera/zoom Phase 2 doc to follow once Phase 1 is merged and playtested (numerically, per §6).

# Plan — Short-game follow camera (chip / pitch / flop)

**Status:** PLAN — recon on `main` (`1d4d8a3`). No code in this PR.  
**Origin:** Putt tracer + remaining-fit roll zoom (`d4c0597`, `dabc3f9`, Survival/18 `fc998e6`).  
**Scope lock:** In-flight camera + roll tracer only. Aim/address camera, physics, landing-circle *sizing*, punch/full-swing “up and in” — untouched. One PR after approve.

**User lock:** Keep the landing indicator visible; follow the tracer with the ball; zoom in until rest — same idea as the putt pass, on chips (and the other short-game types that already share that camera branch).

---

## Phase 0 — Findings

### What the putt pass actually did

Not a new camera type. Three small behaviors, all in `HoleController` + `GolfBall`:

| Piece | Where | What |
|-------|--------|------|
| Ground tracer | `ball.gd` `_sample_putt_trail` | Same `Line2D` as flight. No loft. Wet until settle fade. |
| Impact seed | `_follow_ball` → `_lock_putt_camera` | Capture stroke frame. If already at `PUTT_ZOOM_CAP`, open to `PUTT_IMPACT_ZOOM_FRAC` (0.86) so lerp has room. **Do not tween zoom** (that snapped to cap in 0.2s). |
| Roll ease | `_process` when `_is_putt_context() and _putt_cam_active` | `lerp` look + zoom toward **live** `_desired_camera_look/zoom()` (`PUTT_ROLL_*_LERP` 0.08). Target is remaining **ball→cup** (`_putt_frame_*`). Zoom finishes as the ball dies — not a punch after rest. |

`_is_putt_context()` is **Green lie**, or in-flight if `last_shot_metrics.is_putt`. Comment in code: chips must not enter this during aim. Survival/18 bug was the inverse — apron flicker *dropped* a putt onto the flight camera. Do not reopen that gate for chips.

### What a chip does today

Aim/address (keep this):

- `_greenside_book_frame()` — green ∪ ball, `GREEN_BOOK_ZOOM_CAP` 36. Fringe chips stay on screen with the wash.
- Yellow rest `_aim_circle` + white carry `_aim_land_mark` + roll connector. Hide on strike (`_on_shot_ready` → `_set_aim_visuals_visible(false)`).

Strike onward:

- `_follow_ball` sees `BallPhysics.is_short_game_shot` → `_flight_short_game`. **Holds** live greenside zoom (`FLIGHT_LAND_FRAC_SHORT` 1.06). Look lead × `FLIGHT_LOOK_LEAD_SHORT_MUL` 0.22. Comment: “driver punch crops a 20 yd chip.”
- `_process` uses `_flight_camera_zoom()` (up-and-in), **not** remaining ball→cup.
- Lofted Trackman tracer already runs in `FLIGHT` (tip glued to ball, lift ÷ zoom). On `ROLL` the ribbon **freezes and dries** into the land disc — no ground samples for the roll (the part that is most of a chip).
- In-flight landing indicator is **not** the aim yellow circle. It is `GolfBall._land_mark`: faint planned bounce in air, flash on first bounce, fade on roll. Putts skip it (`_is_putt`).

Net: you keep a wide green-book view, a lofted air ribbon that dies at bounce, and a ball that then rolls most of the shot at postage-stamp size. That is the visibility hole the putt pass already closed on the green.

### Why not `_is_putt_context() = true` for chips

Aim would leave green-book and snap to ball→cup. A 25 yd fringe chip would crop the wash and often the landing circle — the bug `_greenside_book_frame` was written to stop. In-flight remaining-fit is the reuse; aim stays book.

### Pitch / flop

Already on `_flight_short_game`. Punch is not (`is_short_game_shot` = chip/pitch/flop only). One in-flight branch covers all three; chip-only would be an extra check for no gain. Pitch/flop are mostly air + short roll — same pattern, less roll tracer.

### Panel height

Chip execute still uses `SHOT_PANEL_H` 900 (putt is `SHOT_PANEL_H_PUTT` 640). Zoom-in with 47% chrome is the Phase 4 putt problem. Chip pad is already compact. **Include chip in the putt panel height in the same PR** (one line in `shot_routine.layout_shot_chrome`). Pitch/flop stay 900 until playtest says otherwise.

---

## Phase 1 — Diff (after approve)

Reuse, don’t fork. No new camera node, no second tracer type.

### 1. In-flight camera — short-game uses remaining-fit, not up-and-in

`scripts/course/hole_controller.gd`

- `_follow_ball`: if `is_short_game_shot`, take the **putt seed path** (`_lock_putt_camera`, optional cap notch). Do not set `_flight_zoom_base` / tween zoom to launch frac.
- `_process` in-flight: remaining-fit lerp if `_putt_cam_active` and (`_is_putt_context()` **or** `_flight_short_game`).
- `_desired_camera_zoom` / `_desired_camera_look`: when `_flight_short_game and ball_in_flight`, use `_putt_frame_zoom` / `_putt_frame_look` (live ball→cup). `_greenside_book_frame` already false in flight (`not ball_in_flight`).

Do **not** expand `_is_putt_context()`. Aim and pin-flag stay lie-based.

`ponytail:` air frame is ball→cup, not ball∪land AABB. Offline dumps can crop `_land_mark`; upgrade to union if playtest crops the bounce.

### 2. Tracer — keep loft in air; ground-sample the roll

`scripts/ball/ball.gd` `_physics_process` ROLL branch:

- Today: `if not _is_putt` → freeze + `TRACER_DRY_RATE` trim into land disc.
- Short-game ROLL: call `_sample_putt_trail()` (append ground points, stay wet). Full-swing ROLL unchanged (dry).
- Gate on existing `_shot_type` + `BallPhysics.is_short_game_shot`. `_land_mark` unchanged (planned bounce → flash → fade).

Air lofted tracer stays. One `Line2D`; cap still drops the oldest launch points if the ribbon gets long.

### 3. Landing indicator

Keep `_land_mark`. Do not resurrect aim yellow/white during flight (cone + rest + carry is noise on a moving camera). `_on_shot_ready` still hides aim overlays.

### 4. Chip panel

`shot_routine.gd` `layout_shot_chrome`: `SHOT_PANEL_H_PUTT` for `putt` **or** `chip`. `_putt_bottom_chrome` already uses that const when the stroke panel is up — chip remaining-fit then sizes against the shorter chrome, same as putt.

### 5. Check

Extend `scripts/ball/flight_tracer_check.py` (short-game follow seeds remaining-fit, not `FLIGHT_LAND_FRAC_SHORT`; chip ROLL samples trail).  
Extend `scripts/course/putt_camera_zoom_check.py` only if `_process` gate string changes — keep putt asserts intact (`_is_putt_context` still excludes chips at rest).

No new file.

---

## Out of scope

- Aim / green-book / pinch.
- `_is_putt_context()` meaning.
- Full / punch flight camera.
- Landing-circle formula, wind, slope.
- `PUTT_ZOOM_CAP` / span knobs (chips inherit remaining-fit; a 25 yd chip starts as open as a 75 ft lag and tightens).
- Pitch/flop panel height.

---

## PLAYTEST TARGETS (after code)

| Knob | Start | Why |
|------|--------|-----|
| `PUTT_ROLL_*_LERP` | 0.08 (shared) | Same as putt; rest must not punch. |
| `PUTT_IMPACT_ZOOM_FRAC` | 0.86 | Short chips already near cap after a prior putt? Unlikely off-green; keep for greenside tap chips. |
| Chip panel | `SHOT_PANEL_H_PUTT` 640 | Same as putt execute. Raise if chip pad feels cramped. |

Device: Hole 5–style LW chip (~20–25 ft). Confirm Aim (book + yellow/white) → strike (white land mark stays, lofted tracer, camera begins remaining-fit) → bounce flash → ground ribbon + zoom finishes as the ball dies. Compare a 50 yd pitch (more air, short roll) and a punch (must still use full up-and-in).

---

## Acceptance

- Chip/pitch/flop: land mark visible in air; tracer follows the ball; camera tightens through roll and is done at rest (no second punch when the glance panel opens).
- Aim/address greenside book unchanged. Punch/driver unchanged.
- Course Survival/18 putts still use `is_putt` (apron must not steal chip remaining-fit *or* drop putts onto flight cam).
- `python scripts/ball/flight_tracer_check.py` and `python scripts/course/putt_camera_zoom_check.py` pass.

---

## On approve

Implement § Phase 1 only, one PR. Do not start a second camera helper.

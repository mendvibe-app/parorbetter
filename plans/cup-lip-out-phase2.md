# Plan — Phase 2 cup lip-out (presentation on hot rejects)

**Status:** CODE COMPLETE — device playtest pending.  
**Depends on:** Phase 1 lip-in shipped (`e02329e`).  
**Scope lock:** Presentation on hot rejects only. Capture predicates frozen. **Make rate unchanged.**

---

## 1. Understanding

Phase 1 made every **make** read as either a center drop or a rim curl + sink. Hot putts (`speed > CUP_CAPTURE_MAX_SPEED`) still do nothing special: `_try_cup_capture` returns `false` and the ball rolls through with normal putt physics.

Phase 2 adds the third Pelz outcome as **presentation only**:

| Outcome | Condition (unchanged physics gate) | Motion |
|---------|--------------------------------------|--------|
| **Center drop** | Captured; low offset + low speed | Straight sink (Phase 1) |
| **Rim roll / lip-in** | Captured; else | Curl then sink (Phase 1) |
| **Horseshoe lip-out** | Over dark disc **and** `speed > CUP_CAPTURE_MAX_SPEED` | Ride rim, exit offline, **keep rolling** (this plan) |

**Not in scope:** Splitting today's make band so high-offset / high-speed captures become misses. That would change make rate and needs a separate playtest epic.

---

## 2. Current path (verified on `main`)

```text
ROLL tick / area enter cup
  → _try_cup_capture()
       speed > 32  → return false   ← silent pass-through today
       else in dark disc → stash, SETTLED, settled.emit → hole-out + play_cup_drop
```

Key refs:

- `ball.gd` — `CUP_CAPTURE_MAX_SPEED := 32.0` (comment already says "lip out / roll over")
- `ball.gd` — capture; hot reject is a bare `return false`
- `ball.gd` — every-frame re-check so a ball that was hot on enter can still drop when it dies
- `hole_controller.gd` — `holed := dist < CUP_CAPTURE_RADIUS` (untouched if we never emit `settled` on lip-out)

GETTING_STARTED / decisions "lip-out" today means **no hot teleport make**, not horseshoe juice.

---

## 3. Lane — scripted rim ride, then resume ROLL

**Why not visual-only while physics continues:** the node is already moving through the cup; a `visual.position` curl desyncs from the collider and reads as a ghost. Horseshoe needs the ball **on the rim** for a beat, then leaving offline.

**Carrier:**

1. On hot-over-cup (once per crossing): enter a short lip-out presentation (pause normal roll integration for that ball).
2. Stash entry offset, speed, and approach direction (**separate from** Phase 1 `_cup_entry_*` make stash — see §5).
3. Move the **node** along the rim so the collider matches the art.
4. At arc end: set `velocity` to exit tangent × preserved speed scale, `state = ROLL`, clear lip-out stash, resume physics.
5. **Never** emit `settled`. **Never** call `play_cup_drop`. Controllers stay on the miss/continue path.

```gdscript
## PLAYTEST TARGETS — arc length is the legibility metric (not orbit radius).
## Half→¾+ turn so the horseshoe reads; quarter curls read as a nudge.
## Orbit held at rim shelf; ball may overhang grey mid-curl (real lip ride).
const LIP_OUT_ARC_MIN := TAU * 0.55   ## ~198° — above lip-in band
const LIP_OUT_ARC_MAX := TAU * 0.85   ## ~306° horseshoe
const LIP_OUT_DUR_MIN := 0.32
const LIP_OUT_DUR_MAX := 0.62
const LIP_OUT_ORBIT := LIP_ORBIT_MAX  ## reuse 1.55; grey overhang OK
const LIP_OUT_SPEED_KEEP := 0.9

# Inside _try_cup_capture, replace bare hot return:
if velocity.length() > CUP_CAPTURE_MAX_SPEED:
    if _cup_overlap_center_in_disc(...):
        _begin_lip_out(cup_pos)  # once-per-crossing guard inside
    return false
```

Dying settle (`_finish_settle` → `_try_cup_capture` at ~0 speed) must **not** start lip-out — speed gate already prevents that.

---

## 4. Once-per-crossing guard

Without a guard, every ROLL frame while hot-overlapping would restart the tween.

```text
_lip_out_armed: bool   # true when NOT overlapping cup (or after lip-out finishes)
_lip_out_playing: bool # true during scripted ride
```

| Event | Action |
|-------|--------|
| Enter hot + disc + armed + not playing | start lip-out; armed = false |
| Leave cup overlap (dist > cup_r + pad) | armed = true |
| Lip-out tween end | playing = false; resume ROLL; armed stays false until leave |
| `launch` / `reset_at` | clear playing + stash; armed = true |

Re-arm only after leaving the disc so a single pass cannot double-fire. A ball that exits, slows, and comes back cold can still **capture** on a later frame (existing re-check) — desired.

---

## 5. Stash — do not reuse Phase 1 make stash

Phase 1 contract: `_cup_entry_*` survives `reset_at`, cleared only at drop end / `launch()`.

Lip-out that wrote the same fields would poison `cup_drop_total_duration()` / next `play_cup_drop`.

**Use separate fields:**

| Field | Purpose |
|-------|---------|
| `_lip_out_offset: Vector2` | entry offset at hot reject |
| `_lip_out_speed: float` | speed at reject |
| `_lip_out_dir: Vector2` | approach (prefer `velocity.normalized()`, fallback `_launch_dir`) |
| `_lip_out_cup_pos: Vector2` | cup center for orbit |

Clear on: lip-out end, `launch()`, `reset_at()`.  
**Do not** set `_cup_entry_valid` on lip-out.

---

## 6. Exit velocity (PLAYTEST)

After the arc, ball must leave **offline** (not toward cup center).

```text
exit_ang = start_ang + arc_rad
exit_tangent = Vector2.from_angle(exit_ang + sign(arc) * PI/2)
velocity = exit_tangent * _lip_out_speed * LIP_OUT_SPEED_KEEP
```

Default: tangent exit × `LIP_OUT_SPEED_KEEP := 0.9`.

---

## 7. Arc mapping (PLAYTEST) — arc length, not orbit

**Orbit radius is the wrong legibility metric.** The eye reads arc length.
At ~19px screen radius: `0.75 × 2π × 19 ≈ 89px` (~3 ball-widths) reads;
a quarter curl (~30px) is a nudge. Do not “fix” thin curls by shrinking
orbit further — skew **arc angle** toward half→three-quarter+ turns.

Also: do **not** cap the ball inside the dark disc. Real rim rides hang with
the ball proud onto the grey ring; that overhang is the look.

```text
offset_ratio = clampf(offset_len / CUP_CAPTURE_RADIUS, 0, 1)
speed_ratio  = clampf((speed - CUP_CAPTURE_MAX_SPEED) / CUP_CAPTURE_MAX_SPEED, 0, 1)

arc_rad  = lerpf(LIP_OUT_ARC_MIN, LIP_OUT_ARC_MAX, offset_ratio)  ## 0.55τ…0.85τ
arc_rad *= lerpf(0.9, 1.15, speed_ratio)
curl_dur = lerpf(LIP_OUT_DUR_MIN, LIP_OUT_DUR_MAX, offset_ratio)
orbit_r  = LIP_OUT_ORBIT  ## hold at max; grey overhang OK
```

Side of curl: same cross(`offset`, `approach`) sign as `play_cup_drop`.

---

## 8. Controller / scoring — no path changes

Lip-out never emits `settled` and never teleports to cup:

- `_on_ball_settled` holed predicate unchanged
- Practice / short / normal hole-out handlers unchanged
- Coach / Actual yd / recording unchanged

---

## 9. Interaction with dying-on-lip capture

Lip-out must **eject** the ball outside the dark disc (orbit on rim + tangent exit). After lip-out tween, position at `orbit_r` from cup — not at center.

---

## 10. Files + checks

| File | Change |
|------|--------|
| `scripts/ball/ball.gd` | Hot branch → `_begin_lip_out`; once-per-crossing; separate stash; tween; resume ROLL; clears in `launch`/`reset_at` |
| `scripts/course/hole_controller.gd` | **None** (make path frozen) |
| `scripts/course/hole_out_feel_check.py` | Keep Phase 1 asserts; add lip-out contract smoke |
| `scripts/ball/putt_pace_check.py` | Still asserts max-speed gate — must keep passing |
| `scripts/ball/cup_lip_out_check.py` | New: helpers present; no `settled.emit` in lip-out; radius frozen |

Also run: `putt_camera_zoom_check`, `scorecard_check`, `short_game_practice_check`, `practice_reps_check`.

---

## 11. Out of scope (frozen)

- Changing `CUP_CAPTURE_RADIUS`, `CUP_RADIUS`, `CUP_CAPTURE_MAX_SPEED` thresholds
- Make-band outcome split (high offset + speed ≤ 32 → miss)
- `BALL_R_PUTT`, `BALL_R`, `PUTT_ZOOM_CAP`
- Phase 1 rim-in constants except reusing `LIP_ORBIT_MAX` as orbit
- `ball_physics.gd`, pacing / gravity
- Recording / Club Coach / `set_actual`
- Controller hole-out awaits / banner
- New SFX asset (optional follow-up)

---

## 12. Acceptance

- [ ] Make rate unchanged — capture success predicate identical; only the hot `return false` branch gains presentation
- [ ] Hot pass over dark disc: visible rim ride, then ball continues ROLL offline (not sunk, not SETTLED)
- [ ] Cold / captureable putts still make; Phase 1 center vs rim-in unchanged
- [ ] Lip-out never sets `_cup_entry_valid`; Phase 1 stash contract intact
- [ ] Once-per-crossing: one horseshoe per pass
- [ ] Post–lip-out position outside make disc (no false settle-make)
- [ ] `launch` / `reset_at` clear lip-out playing + stash; `visual.position` still zeroed in `reset_at`
- [ ] Listed checks pass
- [ ] Device: screenshot mid-horseshoe on a lag that burns the edge — ball on rim, then leave past the hole

---

## 13. Go / no-go

**Proceed** with scripted rim ride on hot rejects only, separate lip-out stash, tangent exit × `LIP_OUT_SPEED_KEEP`, controllers untouched, capture geometry frozen.

# Plan — Phase 1 cup lip-in / rim roll (presentation only) — REVISED

**Status:** SHIPPED (Phase 1 presentation).  
**Prompt:** `plans/cup-lip-in-phase1-agent-prompt.md`  
**Revision:** stash lifetime, arc-length floor, orbit-cap look call (review notes)

---

## 1. Understanding (unchanged)

Makes all play the same straight `play_cup_drop()` today. Phase 1 adds rim-roll **presentation** for off-center / moderate-speed entries. **Make rate frozen** — no capture geometry moves. Phase 2 lip-out deferred.

---

## 2. Current path (verified)

```text
_try_cup_capture → settled → _on_ball_settled (holed)
  ├── practice → reset_at(_cup) → play_cup_drop
  ├── short_game → reset_at(_cup) → play_cup_drop
  └── normal → reset_at(_cup) → play_cup_drop → banner → await 1.55s
```

`reset_at` clears rotation/shadow/scale/modulate — **not** `visual.position` (latent bug).

---

## 3. Lane + carrier (validated — keep)

**`visual.position` local curl** after `reset_at` teleports the node to cup center. Holds.

**Member stash on the ball** (no call-site signature change):

| Field | Set | Cleared |
|-------|-----|---------|
| `_cup_entry_offset: Vector2` | `_try_cup_capture` **before** zeroing velocity / emitting `settled` | **End of drop tween** and in **`launch()`** — **never in `reset_at`** |
| `_cup_entry_speed: float` | same | same |

**Why not clear in `reset_at`:** all three handlers do `reset_at` **then** `play_cup_drop`. Clearing there would wipe the stash one line before the drop reads it → every make falls to offset 0 → feature is a no-op with no error.

**`visual.position = Vector2.ZERO` stays in `reset_at`** (split from stash clear). Curl sets position afterward; no conflict. Also zero position at end of drop tween.

Unset stash / zero offset → center drop (today’s animation).

---

## 4. Arc mapping — arc length is the legibility metric (REVISED)

Normalize:

```text
offset_len   = _cup_entry_offset.length()
offset_ratio = clampf(offset_len / CUP_CAPTURE_RADIUS, 0.0, 1.0)  # 1.9
speed_ratio  = clampf(_cup_entry_speed / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0)  # 32
```

| Outcome | Condition (PLAYTEST) | Motion |
|---------|---------------------|--------|
| **Center drop** | `offset_ratio < 0.22` **and** `speed_ratio < 0.35` | Straight drop only |
| **Rim roll** | else (still a make) | Curl then drop |
| **Lip-out** | — | Phase 2 deferred |

### Orbit radius — decouple from offset (Correction 2)

**Do not** use `orbit_r = minf(offset_len, MAX)` alone. At the rim-roll boundary (`offset_ratio = 0.22` → `offset_len = 0.42`):

```text
orbit_r = 0.42 → ~10 screen px @ zoom 24
arc ≈ 100° → arc length ≈ 10 × (100π/180) ≈ 17 screen px
ball diameter ≈ 36 screen px
→ travel < half ball width = jitter at band entry
```

**Revise:** hold orbit near max for every rim roll; **arc angle alone** carries the offset signal.

```gdscript
## PLAYTEST — look call: allow ball proud of dark void onto grey rim mid-curl
## (real lip-ins overhang). Cap vs full art edge (57/64)*CUP_RADIUS ≈ 2.49, not void.
const LIP_ORBIT_MAX := 1.55  ## ≈ void radius 1.53; settle on device
orbit_r = LIP_ORBIT_MAX  # every rim-roll; do NOT shrink with offset_len
```

Alternative floor form (if preferred): `orbit_r = maxf(minf(offset_len, LIP_ORBIT_MAX), 0.8)` — still document arc length as the metric.

### Orbit cap — look call, not “stay inside black” (Correction 3)

Keeping the ball fully inside the dark disc makes it look already down and wobbling. Real lip-ins ride the liner **proud of the rim**. Cap against **full visible art** `((57/64)*2.8 ≈ 2.49)`, bias toward void radius (~1.53). Mark `LIP_ORBIT_MAX` as **PLAYTEST TARGET — look call on device**.

### Arc / duration (PLAYTEST)

```gdscript
arc_rad = lerpf(TAU * 0.20, TAU * 0.55, offset_ratio)  ## ~72°–198°
arc_rad *= lerpf(0.85, 1.15, speed_ratio)
curl_dur = lerpf(0.22, 0.48, offset_ratio) + lerpf(0.0, 0.08, speed_ratio)
drop_dur = 0.18
```

**Boundary arc length (rim-roll entry, orbit held at 1.55):**

```text
orbit_r = 1.55 world → ~37 screen px @ zoom 24
arc ≈ 100° (offset_ratio 0.22, mid speed)
arc length = 1.55 × (100π/180) ≈ 2.70 world ≈ 65 screen px
ball diameter ≈ 36 screen px → ~1.8× ball width of travel → readable motion
```

Re-derive after any zoom / `BALL_R_PUTT` change using:  
`arc_len_screen ≈ LIP_ORBIT_MAX * arc_rad * PUTT_ZOOM_CAP`.

### Drop sequence

1. `visual.position` on rim at entry angle, length `orbit_r`  
2. Tween angle by `arc_rad` over `curl_dur`  
3. Collapse to `Vector2.ZERO` + existing scale/darken (`drop_dur`)  
4. Clear stash; emit `cup_drop_finished` if used for awaits  

---

## 5. Call sites — no signature change (keep)

`play_cup_drop()` reads ball members. Practice `:3349`, short `:3369`, normal `:3603` stay one-liners.

---

## 6. Resets — split instructions

| In `reset_at` | Clear stash? |
|---------------|--------------|
| `visual.position = Vector2.ZERO` | **Yes — keep** |
| `_cup_entry_*` | **No** — wipe only at drop end + `launch()` |

---

## 7. Banner / advance timing (unchanged intent)

Await curl+drop before `_show_hole_result_banner` in `_on_holed_out`. Keep total hold sensible vs current `1.55s`.

Practice / short game: both use `await …(0.75)` — change to  
`maxf(0.75, curl_dur + drop_dur + 0.15)` so reset doesn’t cut the curl. **Confirmed.**

---

## 8. Camera (unchanged)

0.38s / 0.2s pan **parallel** with drop — fine. No retiming.

---

## 9. Files + checks

| File | Change |
|------|--------|
| `scripts/ball/ball.gd` | Stash at capture; curl in `play_cup_drop`; `reset_at` zeros `visual.position` only; stash clear at drop end + `launch()` |
| `scripts/course/hole_controller.gd` | Await drop before banner; practice/short await budget |
| `scripts/course/hole_out_feel_check.py` | Assert `visual.position = Vector2.ZERO` inside `reset_at` (BALL already loaded); `play_cup_drop` still in all three handlers; **no** capture-radius edits |

Also run: `putt_pace_check`, `putt_camera_zoom_check`, `scorecard_check`, `short_game_practice_check`, `practice_reps_check`.

---

## 10. Out of scope (frozen)

`CUP_CAPTURE_RADIUS`, `CUP_RADIUS`, `CUP_CAPTURE_MAX_SPEED`, sensor, settle predicate, `BALL_R_PUTT`, `BALL_R`, `PUTT_ZOOM_CAP`, Phase 2 lip-out, recording paths, `ball_physics.gd`.

---

## 11. Acceptance

- [ ] Make rate unchanged — no capture constant / predicate moved  
- [ ] Center-cut: straight drop (below offset/speed thresholds)  
- [ ] Off-center: rim curl then drop; ball may overhang onto grey rim (look call)  
- [ ] **Stash survives `reset_at`**; non-zero at `play_cup_drop` for off-center capture make  
- [ ] `visual.position` zeroed on every `reset_at`  
- [ ] Banner after curl (normal); practice/short await covers curl  
- [ ] Listed checks pass  
- [ ] **Device screenshot mid-curl** on a high-offset make — ball visibly on the rim (opaque bbox can under-predict on-device size ~12–15%; trust the pic)  

---

## 12. Go / no-go

**Proceed** with `visual.position` lane, member stash (not cleared in `reset_at`), orbit held near `LIP_ORBIT_MAX` for rim rolls, cap as a **look PLAYTEST TARGET** allowing rim overhang.

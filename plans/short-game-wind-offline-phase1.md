# Plan — Short-game offline: wind exposure + keep lateral (Phase 1)

**Recon:** `plans/recon_findings_short_game_offline.md` (accepted; one correction below)  
**Deliverable on approve:** `plans/short-game-wind-offline-phase1.md`  
**Status:** CODE COMPLETE — device playtest pending.

**Implementation note:** Wind is applied as **position drift** (`global_position += wind * … * exposure * WIND_DRIFT_SCALE`) rather than velocity+keep-lateral. Pure keep-lateral on velocity made driver crosswind ~98 yd offline. Spin still accumulates on velocity with along-envelope (no full-vector normalize after spin). Same goals: chips nearly wind-immune; no heading steer; driver still drifts.  
**Scope lock (user):** Minimal root-cause PR — **exposure-scaled wind + preserve lateral** (no full-vector renormalize after wind). Preview honesty and telemetry are follow-ups.

---

## 1. Understanding

Clean short-game swings finish wildly offline. Recon discarded shape/RNG/carry-roll heading mismatch. **Root cause is wind in flight:** absolute acceleration + full-vector speed renormalize turns crosswind into a **heading rotation** that hits slow chips hardest (~60° on hole 5 telemetry).

---

## 2. Verified on HEAD (with one recon correction)

### Primary bug — confirmed

`ball.gd` `_process_flight` (~622–634):

```gdscript
var wind_force := 6.0 * sqrt(BallPhysics.GRAVITY_PX / 535.0)
velocity += wind * delta * wind_force
# … spin …
velocity = velocity.normalized() * minf(target_spd, peak_spd * 1.02)
```

1. Wind push is **independent of ball speed** → angular effect ∝ 1/speed.  
2. Renormalize restores magnitude, **keeps steered direction** → pure rotation, no distance cost.

Putts: `wind = Vector2.ZERO` at launch (`ball.gd` ~365). Chips are **not** exempt. No wind term in `_process_roll`.

Aim preview (`_aim_rest_point` / `_aim_carry_land_point`, `hole_controller.gd` ~2658–2678): pure bearing — no lateral wind. Distance solve is wind-aware; **line is not**.

### Correction to recon Finding 1 (roll heading)

Recon claimed roll continues “along whatever heading wind left.” **False on HEAD:**

```gdscript
# ball.gd _begin_roll ~669
velocity = _launch_dir * speed
```

Roll snaps to **original launch direction**. Offline finish = **lateral displacement accumulated in flight**, then roll parallel to aim from that drifted land point — not a 62° roll-out. Qualitative “curve in air, straight on ground” still matches; the 17 yd estimate from `sin(62°)×19 yd` overstates roll’s share. Flight steering remains the bug to fix.

### Deferred (not this PR)

| Item | Why defer |
|------|-----------|
| Phase 0 line-error readout | Tiny but separate; verify Phase 1 with Hole 5 screenshot + F1 hang/launch |
| Phase 2 wind-honest aim preview | Model residual drift only after wind is sane |
| Aim-circle table / live measure | Finding 4 — do not retune `short_game_aim_radius_yards` |
| Archive conflicting epic drafts | Docs hygiene after this PR |

---

## 3. Phase 1 fix — exposure × keep lateral

### 3a. Exposure scale (PLAYTEST)

Wind authority ∝ air exposure vs a full-swing reference — chips near zero; driver ≈ 1.

```gdscript
## PLAYTEST TARGETS — short game nearly wind-immune; driver unchanged.
const WIND_REF_HANG_S := 2.0      ## ~driver hang at current FRAC
const WIND_REF_APEX_PX := 80.0    ## ~driver-ish apex band
const WIND_EXPOSURE_MIN := 0.02   ## floor so literal zero isn’t a special case
const WIND_EXPOSURE_MAX := 1.0

func _wind_exposure() -> float:
	var hang_t := clampf(_air_duration / WIND_REF_HANG_S, 0.0, 1.0)
	var apex_t := clampf(_height_peak / WIND_REF_APEX_PX, 0.0, 1.0)
	# Geometric mean: needs both hang and height (punch low apex → less wind).
	return clampf(sqrt(hang_t * apex_t), WIND_EXPOSURE_MIN, WIND_EXPOSURE_MAX)
```

Then:

```gdscript
var wind_force := 6.0 * sqrt(BallPhysics.GRAVITY_PX / 535.0) * _wind_exposure()
velocity += wind * delta * wind_force
```

Expected: chip 0.93s / ~17px apex → exposure ≪ 1 (near floor). Flop higher apex → more than chip. Punch low apex → less than full. Driver hang+apex → ~1.

Mark constants PLAYTEST; tune on device if driver wind feels soft/hard.

### 3b. Envelope without stealing wind into heading

**Do not** `velocity = velocity.normalized() * target_spd` after wind.

Preferred order in `_process_flight`:

1. Set / keep **along-launch** speed from envelope (`target_spd`).  
2. Apply spin curve (existing, ∝ along_spd).  
3. Apply `wind * delta * wind_force * exposure`.  
4. **Recompose:** `along = clamp(dot(vel, launch), …); lat = vel - along*launch;` restore `along = target_spd` (or min with peak), **keep `lat`**.  
5. Existing stall safety net — preserve lateral intent (already partially does).

Sketch:

```gdscript
var flight_right := Vector2(-_launch_dir.y, _launch_dir.x)
# Envelope on along track first
var along_spd := target_spd
var lat_spd := velocity.dot(flight_right)
velocity = _launch_dir * along_spd + flight_right * lat_spd
# Spin (existing)
if absf(spin) > 0.0001:
	velocity += flight_right * spin * SPIN_CURVE_COEFF * along_spd * delta
# Wind (exposure-scaled) — adds lateral (and a little along if head/tail)
var wind_force := 6.0 * sqrt(BallPhysics.GRAVITY_PX / 535.0) * _wind_exposure()
velocity += wind * delta * wind_force
# Re-assert along envelope; KEEP lateral (wind + spin). No full-vector normalize.
var lat_after := velocity.dot(flight_right)
var along_after := clampf(velocity.dot(_launch_dir), 0.0, peak_spd * 1.02)
# Prefer envelope target on along; do not shrink lat to restore |v|
along_after = minf(target_spd, peak_spd * 1.02)
velocity = _launch_dir * along_after + flight_right * lat_after
```

Head/tail wind: along component of wind is absorbed by the along clamp (slight distance interaction via hang/exits) — acceptable; crosswind becomes real drift.

**Risk:** Full-swing crosswind may feel like more pure lateral displacement and slightly less “curve.” Acceptance #2: driver must still drift meaningfully — exposure≈1 + kept lateral should preserve or improve honesty vs rotation-only.

### 3c. Files

| File | Change |
|------|--------|
| `scripts/ball/ball.gd` | `_wind_exposure()`; wind × exposure; along-envelope + keep lateral (no post-wind full normalize) |
| `scripts/ball/flight_model_check.py` | Mirror new integration; assert chip exposure ≪ driver; assert crosswind adds lateral without only rotating heading; keep `WIND_FORCE` base `6*sqrt(G/535)` |

**Do not touch:** tempo/shape, putt stroke, `short_game_aim_radius_yards`, `GRAVITY_PX` / `FLIGHT_DURATION_FRAC`, roll friction, aim preview geometry, cup/lip, greens.

---

## 4. Out of scope (explicit)

- Phase 0: resting-vs-aim line-error F1 field (follow-up; unlocks easier regression)  
- Phase 2: wind into `_aim_rest_point` / `_aim_carry_land_point`  
- Chip hard-exempt without apex (superseded by exposure)  
- Changing hole wind generation (`hole_generator` random angle/magnitude)  
- Retuning landing-circle table  

---

## 5. Acceptance

- [ ] Clean chip (`blend ~0`) finishes within **~1–2 yd** lateral of aim on **hole 18** (peak wind), not only hole 5  
- [ ] Driver / full-swing crosswind still visibly drifts (wind not neutered)  
- [ ] Same distance: flop drifts more than chip; punch less than full (apex/hang earn exposure)  
- [ ] `flight_model_check` (and related ball checks) pass  
- [ ] Regression: Hole 5 LW chip screenshot + F1 before/after  

Telemetry line-error (#4 in recon) **not** required in this PR; use screenshot + land vs aim visually / temporary print if needed.

---

## 6. Go / no-go

**Proceed** with exposure-scaled wind + along-envelope / keep-lateral in `ball.gd`, check mirror updated, preview/telemetry deferred.

**On approve:** write `plans/short-game-wind-offline-phase1.md`, implement one PR.

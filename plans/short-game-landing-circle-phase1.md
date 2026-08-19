# Plan — Short-game landing circle sizing (Phase 0 + Phase 1)

**Epic:** `plans/epic_short_game_landing_circle.md`  
**Deliverable on approve:** `plans/short-game-landing-circle-phase1.md` (copy of this plan)  
**Status:** CODE COMPLETE — device screenshot pending.  
**Scope lock:** Display radius formula + refresh wiring only. One PR. Physics launch dispersion untouched. No roll-out indicator.

**User lock:** Yellow rest circle scales with **planned rest yards** (ball → rest preview).

---

## Phase 0 — Findings (confirmed on `main`)

### 1. Where is radius computed / who draws it?

| Role | Location |
|------|----------|
| Formula | `GameState.get_aim_radius_yards` — `game_state.gd:327–346` |
| Club bucket | `BallPhysics.lateral_spread_range_yards` — `ball_physics.gd:224–236` |
| Wire-in | `HoleController._aim_radius_for_club` — `hole_controller.gd:1750–1753`; set at `_begin_aim_phase:1815–1816` |
| Draw | `_aim_circle` `Line2D` — create `:315–320`; points `:2782` via `AimControl.make_circle_points` |
| Px scale | `radius_px := BallPhysics.yards_to_pixels(_aim_radius_yd)` — `:2739` (`PX_PER_YARD := 2.25`) |

White **carry** ring `_aim_land_mark` + roll connector already exist (`:2791–2803`).

### 2. Actual formula (as written)

Non-putt:

```text
spread = lateral_spread_range_yards(club_max)     # full-width L–R pattern (yd)
pro_yd  = spread.x * 0.5                          # radius
weak_yd = spread.y * 0.5
r = piecewise form lerp(weak → mid → pro)         # empty form_history → form=0.45
if force > 0: r *= lerpf(1.0, 1.45, force)
```

**Not a function of:** planned yards, pin distance, or shot type.  
**Is a function of:** `club_max_yards` bucket, rolling form, optional club-fit force.

Lob/Sand wedge bucket (`club_max < 95`): `Vector2(8, 18)` → radius **4–9 yd** (12–27 ft).

### 3. Shot-type branch?

**No** in the radius path. Chip / Pitch / Flop / Full share one formula. Changing shot type only calls `_refresh_aim_visuals()` (`:2322–2323`) — does **not** recompute `_aim_radius_*`.

### 4. Floor / clamp?

| Circle | Floor |
|--------|--------|
| Yellow rest | No `maxf` — model floor is wedge half-width (**4 yd** at form=1) |
| White carry | `land_r := maxf(radius_px * 0.38, 6.0 * inv_z)` — at zoom 1: **6 px ≈ 2.67 yd ≈ 8 ft** |

### 5. Same as physics dispersion?

**Display / report only.** `aim_radius_yd` is stored on `ShotRoutine` / `ShotReport` and **never** read by `BallPhysics.launch_velocity`. Lateral miss comes from swipe/tempo shape (`ball_physics.gd` ~930–952).

→ Symptom is a **feedback-model bug**, not launch variance. Fixing the circle does not tighten chip outcomes (acceptance #5: outcomes already independent; circle becomes honest *advice*, not a physics driver).

### 6. Landing only or + roll?

Yellow circle centered on **`rest`** = planned **total** (carry + roll). Carry first-bounce = smaller white ring + roll line. Already communicates land→rest; sizing the yellow ring is this epic; a richer roll-out UI is **flagged, out of scope** (§5 epic).

### 7. Roll-out modeled?

**Yes** — `air_distance_fraction` chip ~0.20–0.33 air (lots of roll); pitch ~0.90; flop ~0.92–0.98. Do not build a new roll indicator here (pacing/friction still playtest-sensitive).

### Hole 5 chip diagnosis (matches playtest)

LW `max=65`, form `0.45`, force `0` (shortest-club short type):

```text
r ≈ lerpf(9, 6.5, 0.9) = 6.75 yd ≈ 20.25 ft radius ≈ 40 ft diameter
pin ≈ 20–25 ft → circle wider than the shot
```

Even form=1.0 → **4 yd / 12 ft radius** — still ≈ shot length. Epic suspicion confirmed: short game inherits full-swing **club-category** spread.

---

## Phase 1 — Proposed fix (one PR)

### Design

1. **Keep full-swing path unchanged** — existing `lateral_spread_range_yards` + form + force. Epic acceptance #4.
2. **Short-game branch** for `chip` / `pitch` / `flop`: radius from **planned rest yards** × shot-type band, then form (+ force if any).
3. **Recompute every aim refresh** so drag / type toggle updates size (today radius is sticky from `_begin_aim_phase`).
4. **Preserve flop > pitch > chip** width at equal rest yards.
5. Constants marked `## PLAYTEST TARGET` with epic table rationale inline.

### Suggested short-game bands (PLAYTEST — from epic ft table ÷ 3)

| Shot | Rest-yard span (scale input) | Radius near→far (yd) | ≈ ft radius |
|------|------------------------------|----------------------|-------------|
| Chip | 5 → 20 | 0.67 → 1.33 | 2 → 4 |
| Pitch | 20 → 50 | 1.67 → 3.33 | 5 → 10 |
| Flop | 10 → 30 | 2.0 → 4.0 | 6 → 12 |

Outside span: clamp to near/far end (do not inherit wedge 4–9 yd floor).

Form: mild widen for weak form, e.g. `r *= lerpf(1.35, 1.0, form)` (PLAYTEST) — sharp form stays on table; wild opens ~35%. Force multiplier keep as today if `force > 0`.

### API shape

```gdscript
# game_state.gd
func get_aim_radius_yards(
	on_green: bool = false,
	club_max_yards: float = 0.0,
	force: float = 0.0,
	planned_rest_yd: float = 0.0,
	shot_type: String = "full",
) -> float:
	if on_green:
		return lerpf(PUTT_RADIUS_WEAK_YD, PUTT_RADIUS_PRO_YD, get_form())
	if shot_type == "chip" or shot_type == "pitch" or shot_type == "flop":
		return _short_game_aim_radius_yards(planned_rest_yd, shot_type, force)
	# existing club-bucket path unchanged
	...
```

Prefer putting the short-game lerp helper next to `lateral_spread_range_yards` in `ball_physics.gd` (single physics authority) **or** private on `GameState` — plan default: **`BallPhysics.short_game_aim_radius_range_yards(shot_type) -> Vector2` near/far radii + distance span constants**, `GameState` does form/force. Avoid duplicating magic numbers in the check.

### HoleController wiring

```gdscript
func _aim_radius_for_club(..., planned_rest_yd: float, shot_type: String) -> float:
	return GameState.get_aim_radius_yards(on_green, club_max, force, planned_rest_yd, shot_type)

# Inside _refresh_aim_visuals (non-putt), before cone/circle draw:
var rest := _aim_rest_point(...)
var rest_yd := BallPhysics.pixels_to_yards(from.distance_to(rest))
_aim_radius_yd = _aim_radius_for_club(lie_now, club_max, wind, severity, rest_yd, flight_st)
# then radius_px from _aim_radius_yd
```

Also update `_begin_aim_phase` initial set to pass pin/aim rest + effective shot type (refresh will overwrite on first draw anyway).

Shot-type toggle already calls `_refresh_aim_visuals` — that becomes sufficient once refresh recomputes radius.

### Carry-ring floor interaction (small, same PR)

After radius shrinks to ~1 yd (~2.25 px), `land_r = max(0.38R, 6/z)` can **exceed** the yellow circle at low zoom. Cap:

```gdscript
land_r = minf(maxf(radius_px * 0.38, 6.0 * inv_z), radius_px * 0.92)
```

So white land ≤ yellow rest. Display-only; no physics.

### Files (only these)

| File | Change |
|------|--------|
| `scripts/ball/ball_physics.gd` | Short-game aim radius span constants + helper (or document if helper lives on GameState) |
| `scripts/autoload/game_state.gd` | Extend `get_aim_radius_yards`; short-game branch |
| `scripts/course/hole_controller.gd` | Pass rest_yd + shot_type; recompute in `_refresh_aim_visuals`; land_r cap |
| `scripts/ball/aim_dispersion_check.py` | Keep full-swing bucket asserts; add short-game band + chip≪wedge + flop>chip; assert refresh passes shot_type / planned yards |

### Out of scope (frozen)

- `tempo_gesture.gd`, `tempo_grade.gd`
- Pacing: `GRAVITY_PX`, `FLIGHT_DURATION_FRAC`, roll friction
- Green sizing, camera/zoom, cup capture, Club Coach recording
- Launch lateral / `launch_velocity` dispersion
- New roll-out indicator epic
- Changing full-swing `lateral_spread_range_yards` buckets

---

## Acceptance (from epic, tied to recon)

- [ ] Hole 5–style chip ~20–25 ft: yellow radius in **~2–4 ft** band; visibly smaller than pin distance
- [ ] Same lie/rest: **Chip < Pitch < Flop** circle size
- [ ] Within type, longer rest → wider circle (20 yd pitch < 40 yd pitch)
- [ ] Full-swing / irons / driver: unchanged vs current club buckets (check asserts)
- [ ] Circle remains display-only (no `aim_radius_yd` in launch path)
- [ ] `aim_dispersion_check` (+ related) pass
- [ ] Screenshot Hole 5 chip pre/post (device)

---

## Go / no-go

**Proceed** with short-game branch on planned rest yards, full-swing frozen, refresh-time recompute, land_r display cap.

**On approve:** write `plans/short-game-landing-circle-phase1.md`, then implement one PR.

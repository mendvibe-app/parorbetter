# Correction — Putt ball visible-size (ball∶cup on-screen ratio)

**Deliverable path (on approve / implement):** `plans/putt-ball-visible-size.md`  
**Status:** SHIPPED — fill fractions in `HoleController` (`PUTT_BALL_FILL` / `PUTT_CUP_FILL`). Absolute scale then moved in `putt-true-scale-phase1.md`.  
**Track:** correction, found live during playtest (`PUTT_ZOOM_CAP` 24)  
**Scope:** `BALL_R_PUTT` + check/comment only. Visual. No physics / make-rate change.

---

## 1. Understanding (confirm back)

Both `assets/ball/ball.png` and `assets/greens/cup.png` are **64×64** with transparent padding. Sprites scale as `(radius * 2) / texture_width`. Different **opaque/dark fill fractions** mean raw constants `BALL_R_PUTT` and `CUP_RADIUS` are **not** visible diameters — padding silently warps the on-screen hole∶ball ratio.

Already shipped and **out of scope:** `PUTT_ZOOM_CAP`, capture→`settled` recording, `CUP_CAPTURE_RADIUS = 1.9` see=catch.

**Proposed lever (validated):** raise `BALL_R_PUTT` only (~1.0 → **1.44**) so visible ratio ≈ real **2.53**, without touching cup capture or make rate.

---

## 2. Re-measured spans (from actual PNGs)

### `assets/ball/ball.png` (64×64)

Opaque bbox (`alpha > 128` and `> 200`, identical):

| | |
|--|--|
| Bounds | x 16–48, y 16–48 |
| **Opaque span** | **33 × 33** |
| Fill | **33 / 64** |

Matches your 33/64.

### `assets/greens/cup.png` (64×64)

| Measure | Span | Notes |
|---------|------|--------|
| Full opaque (shelf+rim+hole) | **57 × 57** | bbox 4–60 |
| Near-black **void only** (`luma ≤ 50`) | **35 × 35** | HOLE ~(12,14,12) |
| Void **+ grey rim** (`luma ≤ 60`) | **43 × 43** | includes RIM ~(55,58,52) |

**See=catch / your table use 43/64** — void **plus** thin grey rim, not void alone. Device ratio 91÷25 = 3.64 aligns with the **43/64** method, so the ratio fix keeps **43** for consistency with `CUP_CAPTURE_RADIUS` and existing see=catch assert.

*(Do not mix 35 and 43 in one PR.)*

---

## 3. Arithmetic — current ratio and exact `BALL_R_PUTT`

```text
visible_cup  = (43/64) * (CUP_RADIUS * 2)
             = (43/64) * (2.8 * 2) = (43/64) * 5.6 = 3.7625

visible_ball = (33/64) * (BALL_R_PUTT * 2)
             = (33/64) * 2.0     # at BALL_R_PUTT = 1.0
             = 1.03125

ratio        = 3.7625 / 1.03125 = 3.648   ≈ 3.65  (device 3.64 ✓)

Real golf    = 4.25″ / 1.68″ = 2.5298 ≈ 2.53
```

Solve visible ratio = 2.53:

```text
visible_ball_target = 3.7625 / 2.53 = 1.48715

(33/64) * (BALL_R_PUTT * 2) = 1.48715
BALL_R_PUTT = 1.48715 * 32 / 33 = 1.4421
```

**Recommend `BALL_R_PUTT := 1.44`** (exact land-on-2.53).  
`1.45` also fine (~2.52 ratio) if you want one-decimal playtest slack.

Check at **1.44**: `vis_ball = (33/64)*2.88 = 1.485` → ratio **2.534** ✓  
Your `33*(2.9/64)` with 1.45 → ratio **2.517** ✓

---

## 4. Is `BALL_R_PUTT` visual-only? **Yes (runtime)**

| Location | Role |
|----------|------|
| `ball.gd:95` | const definition |
| `ball.gd:450` | **only** runtime read — `_apply_lie_visual()` |

```gdscript
# ball.gd:448-464
func _apply_lie_visual() -> void:
	var r := BALL_R_PUTT if _lie == "Green" else BALL_R
	_ball_scale = (r * 2.0) / tex_w
	visual.scale = Vector2.ONE * _ball_scale
	_shadow_scale = ((r + 2.0) * 2.6) / sh_w
	# glow / spin_fx also from r
```

**Not** used in cup capture, settle predicate, physics, or aim.  
Also in `putt_pace_check.py` string assert + comments (`AGENTS.md` / `decisions.md`) — docs only.

**Claim validated:** draw-only; make rate unchanged (capture = center vs `CUP_CAPTURE_RADIUS`).

---

## 5. Answers to numbered questions

### (2) Shadow / glow / spin_fx at r = 1.44

All scale from the same `r` in `_apply_lie_visual()`. vs 1.0:

| FX | Formula | Δ at 1.44 |
|----|---------|-----------|
| Shadow | `(r+2)*2.6/sh_w` | 3.0→3.44 → **+15%** (`+2` softens) |
| Glow | `r*5.2/tex_w` | **+44%** |
| Spin FX | `r*3.4/tex_w` | **+44%** |

**Leave multipliers alone** for v1 — proportional to ball. Retune only if playtest says glow/spin too hot.

### (3) Other `visual.scale` sites

| Site | At larger `_ball_scale` |
|------|-------------------------|
| `:539` `_ball_scale * s`, `s = 1 + _height*0.006` | On green putt `_height→0`, `s≈1`. Safe. |
| `:905` `play_cup_drop` from `start_s := _ball_scale` → `0.38*start_s` | Proportional. Safe. |

### (4) `putt_pace_check.py` — replace literal

Replace `assert "BALL_R_PUTT := 1.0" in BALL` with:

```python
# Visible hole∶ball ≈ real 4.25/1.68. Spans = sprite fill (remeasure if PNG padding changes).
BALL_OPAQUE = 33.0   # assets/ball/ball.png
CUP_DARK = 43.0      # cup.png void+rim (luma≤60); matches see=catch
m_putt = re.search(r"const BALL_R_PUTT\s*:=\s*([0-9.]+)", BALL)
m_cup = re.search(r"const CUP_RADIUS\s*:=\s*([0-9.]+)", HOLE)
assert m_putt and m_cup
vis_ball = (BALL_OPAQUE / 64.0) * (float(m_putt.group(1)) * 2.0)
vis_cup = (CUP_DARK / 64.0) * (float(m_cup.group(1)) * 2.0)
ratio = vis_cup / vis_ball
assert abs(ratio - 2.53) < 0.06, (ratio, vis_cup, vis_ball)
```

Keep existing see=catch assert (`CUP_CAPTURE/CUP_RADIUS ≈ 43/64`).

### (5) Draft comment for `hole_controller.gd:9`

```gdscript
## Cup sprite outer radius (rim + shelf). Capture uses CUP_CAPTURE_RADIUS (dark disc).
## On-screen hole∶ball uses texture fill, not raw constants:
##   vis_cup  = (43/64) * CUP_RADIUS * 2
##   vis_ball = (33/64) * BALL_R_PUTT * 2
## Target vis_cup/vis_ball ≈ 2.53 (real 4.25″/1.68″). BALL_R_PUTT carries that ratio;
## CUP_RADIUS is not the make disc — see CUP_CAPTURE_RADIUS.
```

### (6) Short-putt overlap risk

3 ft ≈ **2.25 px** center-to-center (`PX_PER_YARD`).

| | Vis radius @ 1.0 | @ 1.44 |
|--|------------------|--------|
| Ball | 0.52 | 0.74 |
| Cup dark | 1.88 | 1.88 |
| Gap (2.25 − both) | **−0.15** (already overlaps) | **−0.37** (more) |

Tap-ins **already** overlap ball vs dark disc; 1.44 increases it. Flag for playtest — not a ship blocker if tap-ins still read “over the hole.”

---

## 6. Proposed change (example)

**Files only:**

1. `scripts/ball/ball.gd` — `BALL_R_PUTT := 1.44` + derivation comment  
2. `scripts/ball/putt_pace_check.py` — visible-ratio assert (replace literal `1.0`)  
3. `scripts/course/hole_controller.gd` — comment at `:9` only (no constant edits)

```gdscript
## On-green draw radius. (33/64)*(2R) vs (43/64)*(2*CUP_RADIUS) ≈ 2.53 real cup/ball.
const BALL_R_PUTT := 1.44
```

---

## 7. Out of scope — do not touch

- `CUP_RADIUS`, `CUP_CAPTURE_RADIUS`, cup sensor, settle predicate  
- `BALL_R := 3.5`  
- Regenerating `ball.png` / `cup.png`  
- `PUTT_ZOOM_CAP`  
- `_on_ball_settled`, `_on_holed_out`, `_on_practice_green_holed`, `_on_short_game_holed`  
- Any file not listed in §6  

---

## 8. Acceptance

- [ ] `python scripts/ball/putt_pace_check.py` passes with **visible-ratio** assert (`≈ 2.53 ± 0.06`)  
- [ ] Existing see=catch assert still passes  
- [ ] **Make rate unchanged** — only `BALL_R_PUTT` (draw in `_apply_lie_visual`); capture/settle physics untouched  
- [ ] Device 8 ft @ zoom 24: on-screen cup dark∶ball ≈ **2.5** (was ~3.6)  
- [ ] Smoke 3 ft address: overlap acceptable; glow/spin not absurd  

---

## 9. Handoff

On approve: copy this doc to `plans/putt-ball-visible-size.md`, then one PR with §6 only.

# Plan — Lip-out leave: real-golf bleed + geometry-weighted luck

**Recon:** session findings (exit `@ 0.9 × entry` → min ~22 yd leave)  
**Status:** CODE COMPLETE — device playtest pending.  
**Add-on:** Firm putts inside the make gate (`speed_ratio ≥ 0.55`) can lip out with chance rising to ~42% at the hard max (center-hot slightly higher). Soft putts still always drop.  
**Scope:** One PR. Horseshoe **presentation** (arc/orbit) unchanged. Make rate / `CUP_CAPTURE_MAX_SPEED` frozen.  
**User locks:** Entry-speed still scales leave; randomness from **entry geometry** (offset × heat), not a coin flip; typical leave **sit→~6 ft**, hot max **~12–15 ft**.

---

## 1. Understanding

Today lip-out is honest about *direction* (rim tangent) but dishonest about *energy*: `LIP_OUT_SPEED_KEEP := 0.9` restores almost all inbound speed. That makes a smoking 100+ yd approach kick long (plausible) and a barely-hot chip rocket off the green (not).

Real horseshoes bleed most energy on the liner. Exit speed still rises with how hot you arrived — and micro-variations in line (offset) and contact make some hot lips **sit** and others **kick**.

---

## 2. Current code (unchanged contract)

```text
speed > CUP_CAPTURE_MAX_SPEED (32) + over dark disc
  → _begin_lip_out (stash speed/offset, curl tween)
  → _finish_lip_out: velocity = tangent * (_lip_out_speed * 0.9)
```

Make / miss predicates stay as they are. This PR only changes **exit speed** (and settle threshold for the leave — see §4).

---

## 3. Real-golf model (PLAYTEST)

### 3a. Leave distance → exit speed (green decel ≈ 8.44 px/s²)

Coast \(d = v^2 / (2a)\) down to near stop. Targets:

| Leave | Feet | Yards | ≈ exit px/s (to rest) |
|-------|------|-------|------------------------|
| Sit / die | 0–1 | ~0–0.3 | **2–5** |
| Typical | ~6 | 2 | **~9** |
| Hot max | 12–15 | 4–5 | **~12–14** |

Replace `LIP_OUT_SPEED_KEEP` with an **absolute exit-speed band** (ft-grounded), not a 0.9 fraction of entry.

### 3b. Heat + offset → kick tendency (deterministic backbone)

```text
heat         = clampf((_lip_out_speed - CUP_CAPTURE_MAX_SPEED) / CUP_CAPTURE_MAX_SPEED, 0, 1)
               # 32 → 0, 64 → 1, hotter → clamps at 1
offset_ratio = clampf(_lip_out_offset.length() / CUP_CAPTURE_RADIUS, 0, 1)

# Center-hot rattles harder; high-offset horseshoe is longer ride but usually softer exit.
# PLAYTEST — tweak weights on device.
kick_tend = clampf(
    lerpf(0.25, 1.0, heat) * lerpf(1.0, 0.55, offset_ratio),
    0.0, 1.0)
```

- Hot + center-ish → high `kick_tend` (more chance of long kick, still can sit)  
- Hot + high offset → medium  
- Just-over-gate + any offset → low (mostly sit / short dribble)

Inbound speed still matters via `heat`. A 100+ yd ball that is still smoking at the cup has high heat; a chip just over 32 has low heat.

### 3c. Luck = micro-line, skewed by geometry

```gdscript
## PLAYTEST — u~U(0,1); power > 1 biases toward sit when kick_tend is low
var u := randf()
var sit_bias := lerpf(2.4, 0.75, kick_tend)  # low tend → more sits; high → flatter
var leave_t := pow(u, sit_bias)              # in [0,1], geometry-skewed
var exit_spd := lerpf(LIP_OUT_EXIT_SIT, LIP_OUT_EXIT_MAX, leave_t)
# Scale ceiling by kick_tend so cold lips cannot roll the hot max
exit_spd *= lerpf(0.45, 1.0, kick_tend)
exit_spd = clampf(exit_spd, LIP_OUT_EXIT_SIT, LIP_OUT_EXIT_MAX)
```

Constants (PLAYTEST, comment ft rationale):

```gdscript
const LIP_OUT_EXIT_SIT := 3.0    ## ~0–1 ft after settle — “got lucky”
const LIP_OUT_EXIT_MAX := 14.0   ## ~12–15 ft coast — smoking kick
# remove or repurpose LIP_OUT_SPEED_KEEP := 0.9
```

**Grounding:** randomness is not “50% teleport sit.” Geometry sets how often you get the soft vs hard part of the band; `randf` stands in for un-simulated micro-offset/spin at the liner — same idea as tempo noise elsewhere, but keyed off stash we already have.

Optional (same PR if cheap): seed from a hash of offset angle so two visually identical packs don’t feel identical every time — still `randf()` is fine for v1.

---

## 4. Settle after lip-out (chip vs putt)

Chips use `ROLL_SETTLE_SPEED := 10`. An exit of 9 px/s would **instant-sit**; a 6 ft leave needs coast below 10. Putts use `PUTT_SETTLE_SPEED := 1.5` and match the ft table.

**Fix:** while finishing a lip-out leave on green, use putt-like settle (trickle physics):

```gdscript
var _lip_out_leave: bool = false  # set true in _finish_lip_out; clear on settle/launch/reset

# in _process_roll settle pick:
var settle_spd := (
    BallPhysics.PUTT_SETTLE_SPEED
    if _is_putt or _lip_out_leave
    else BallPhysics.ROLL_SETTLE_SPEED
)
```

Grounded: once you’re off the rim you’re at putting speeds. Does not change normal chip roll settle elsewhere.

Also: sideways leave skipping `along >= plan` is fine once exit is ~ft-scale — friction stops you before rockets.

---

## 5. Files

| File | Change |
|------|--------|
| `scripts/ball/ball.gd` | Exit-speed model; `_lip_out_leave`; clear flags in `launch` / `reset_at` / settle |
| `scripts/ball/cup_lip_out_check.py` | Assert no `LIP_OUT_SPEED_KEEP := 0.9` (or keep name but value gone); assert exit band constants; assert `_lip_out_leave` / putt settle path; assert capture max still 32 |

No controller / aim / wind / capture-radius edits.

---

## 6. Out of scope

- Make rate, `CUP_CAPTURE_RADIUS`, sensor  
- Horseshoe arc/orbit/duration presentation  
- Aim preview wind honesty  
- Line-error F1 telemetry  
- Changing green `roll_friction_for` / `FRAC`  

---

## 7. Acceptance

- [ ] Chip just over hot gate: most leaves **sit or ≤ ~6 ft**; not off-green  
- [ ] Smoking approach lip-out: can kick **up to ~12–15 ft**, still scales with how hot (high heat more often toward max)  
- [ ] Same heat: more center-ish offset → higher average kick than high-offset horseshoe (geometry weight)  
- [ ] Repeated identical-looking lips: **mix** of sit vs dribble vs kick (luck), not one fixed distance  
- [ ] Make rate unchanged (only exit after reject)  
- [ ] `cup_lip_out_check` (+ quick ball checks) pass  
- [ ] Short-game range: screenshot soft sit + hot kick on purpose  

---

## 8. Go / no-go

**Proceed** with absolute exit band (sit→14 px/s), `kick_tend(heat, offset)`, skewed `randf` leave, and `_lip_out_leave` → putt settle on green.

**On approve:** write `plans/lip-out-leave-phase1.md`, implement one PR.

# Putting Phase 1 — Contact on green

**Status:** SHIPPED — playtest 2026-08-27 (FAT dies, THIN runs, line floor ~5 in @ 6 ft)  
**Roadmap:** `plans/putting-rework-roadmap.md`  
**Do not** start camera Phases 3–4 in this PR.

---

## Why this is not “delete the `1.0`”

Putt contact labels are **the same axis as pace**. `PuttStroke.grade()` sets FAT/THIN from
`frac_err` vs the pace marker, then `power` from `power_from_frac(actual)`. Amplitude
already shortened a FAT and lengthened a THIN. Full-swing `contact_multiplier`
(THIN 0.82 / FAT 0.68 / PERFECT 1.06) on top of that is the stack
`decisions.md` / `putt_pace_check.py` killed on purpose.

Blindly removing `contact_mul = 1.0 if lie == "Green"` reopens that cliff.

**Phase 1:** a **putt-only mild curve**, applied in the **single distance owner**
(`resolve_distance`), plus a small **line floor** so a mishit can miss the hole even
when the stroke stayed in the arc lane.

---

## Current path (verified)

```text
PuttStroke.grade
  contact  ← |frac_err| / BAND_HALF   (PERFECT / GOOD / FAT / THIN; MISS if incomplete)
  power    ← power_from_frac(actual) × (1 + tempo_bias)     # amplitude owns pace
  contact_mul ← 1.0 on Green                                 # coaching yards only
ShotRoutine          power = committed * power_mul           # no contact_mul
resolve_distance     skip contact_multiplier when is_putt    # ball yards
launch_velocity      line_miss = path_error * 0.14 * contact_scale
                     # path_error == 0 → line_miss == 0 even on FAT
ShotReport           planned_yards skips contact on Green
```

| File | What |
|------|------|
| `scripts/shot/putt_stroke.gd` | `grade()` ~171–184 — Green forces `contact_mul = 1.0` |
| `scripts/ball/ball_physics.gd` | `resolve_distance` ~632–635 — `if not is_putt` skip |
| `scripts/ball/ball_physics.gd` | `contact_multiplier` ~768–781 — full-swing curve only |
| `scripts/ball/ball_physics.gd` | `launch_velocity` putt ~921–934 — `line_miss *= path_error` |
| `scripts/systems/shot_report.gd` | ~46–48 — Green planned yards skip contact |
| `scripts/ball/putt_pace_check.py` | ~108–118 — asserts FAT yards == GOOD yards |

Chip stays on the existing curve + overpull exception (`frac_err > 0` drops THIN tax).

---

## Locked choice

1. **Distance owner is `resolve_distance`.** One multiply. `PuttStroke` / `ShotReport`
   call the same helper so glance yards match the roll.
2. **Putt curve ≠ full-swing curve.** Thin putts **skid long**; fat putts **die**.
   PERFECT does **not** get the 1.06 “reads past committed” gift (true-scale cup).
3. **Amplitude still owns the big miss.** Contact is a visible extra, not a second
   stroke. If playtest feels like “I already came up short and then it died,”
   raise FAT toward 1.0 — do not retie contact to tempo in this phase.

---

## PLAYTEST TARGETS

`BallPhysics.contact_multiplier(quality, lie)` — Green branch:

| Contact | Mul | Why |
|---------|-----|-----|
| PERFECT | 1.00 | no make-rate gift |
| GOOD | 1.00 | committed pace |
| THIN | 1.06 | skid / runs |
| FAT | 0.90 | dies |
| MISS | 0.78 | incomplete |

`path = sign * maxf(absf(path), floor)` then `putt_line_miss` × pin yards × 36 = inches at cup.

| Knob | Value | Where |
|------|--------|--------|
| `PUTT_CONTACT_LINE_FLOOR` | 0.08 | `putt_stroke.gd` |
| MISS floor | 0.14 | same |
| `PUTT_LINE_MISS_SCALE` | 0.84 | `ball_physics.gd` — 6 ft THIN floor ≈ 5 in (was 0.14 ≈ 1 in) |

---

## Diff (one PR)

1. **`ball_physics.gd` `contact_multiplier`** — add `lie := ""` (default keeps
   full-swing numbers). Green match table above. Comment: PLAYTEST TARGET.
2. **`resolve_distance`** — always `power_mul *= contact_multiplier(contact, lie)`.
   Delete the putt skip + “don’t stack contact” comment.
3. **`putt_stroke.gd`** — `contact_mul = BallPhysics.contact_multiplier(contact, lie)`.
   Chip overpull exception unchanged (`lie != "Green"`). Add line floor on Green
   mishit as above.
4. **`shot_report.gd`** — pass `p_lie` into `contact_multiplier`. Green
   `planned_yards` uses `resolve_distance` (same as non-putt).
5. **`launch_velocity`** — drop “Amplitude owns pace; contact owns line only”
   comment. Leave `contact_scale` on `line_miss`.
6. **`decisions.md`** — replace “FAT/THIN no longer stack distance” with the
   putt curve + “amplitude owns the miss; contact is a mild extra.”
7. **`putt_pace_check.py`** — `putt_roll_yards` multiplies the Green curve.
   Assert at same `power_mul`: FAT < GOOD, THIN > GOOD, PERFECT == GOOD.
   Keep “no 0.68 cliff” (FAT ≥ 0.85). Smash-long still amplitude-first
   (`1.55 * THIN 1.06` still long).

No new files. No tempo/contact retie. No camera.

---

## Acceptance

- Same committed power, FAT stroke finishes short of an identical GOOD; THIN
  finishes long. Visible on a ~20 ft putt (not only in F1).
- Straight-in-lane FAT/THIN can miss the cup left or right (line floor).
- Chip distance unchanged (including overpull-THIN exception).
- Check: `python scripts/ball/putt_pace_check.py`

## Out of scope

- Retie putt contact to tempo/balance (follow-up if the extra still feels like
  double-tax).
- Camera Phases 3–4.
- Snap knobs / line-aim copy.
- Full-swing or chip multipliers.

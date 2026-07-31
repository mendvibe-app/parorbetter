# Tuning Epic: Stop Double-Penalizing Distance on Good Contact

**Status**: Shipped — PERFECT/GOOD power_mul = 1.0; PERFECT contact_multiplier 1.06; THIN/FAT over-band tax only.

## Problem
Playtesting: shots consistently land short on every club, even on swings that
feel good / are graded well. Traced to a real bug, not just a feel issue —
two systems are both taxing distance for the same tempo imperfection.

## Root cause (verified in `scripts/shot/tempo_grade.gd` + `scripts/ball/ball_physics.gd`)

`TempoGrade.grade()` does two things off the same tempo-ratio error (`abs_n`):
1. Buckets it into a **contact tier** (PERFECT / GOOD / THIN / FAT / MISS).
2. *Separately* computes a **continuous power multiplier**:
   ```gdscript
   var power_mul := clampf(1.0 - abs_n * 0.22, 0.55, 1.0)
   ```
   This only equals `1.0` at a dead-perfect ratio match. Anywhere else inside
   the PERFECT band (`abs_n` up to `BAND_PERFECT = 0.50`) it's already below
   1.0. Anywhere in the GOOD band (up to `BAND_GOOD = 1.15`) it can fall to
   `0.747`.

That `power_mul` gets baked into `result.power` in `shot_routine.gd`. Then
`ball_physics.gd` applies a **second**, independent penalty on top, keyed off
the discrete contact tier:
```gdscript
static func contact_multiplier(quality: ShotResult.ContactQuality) -> float:
    match quality:
        PERFECT: return 1.04
        GOOD:    return 1.0
        THIN:    return 0.82
        FAT:     return 0.68
        MISS:    return 0.4
```

Stacked, the actual numbers look like this today:

| Tempo error (abs_n) | Contact label | power_mul | × contact_multiplier | **Net result** |
|---|---|---|---|---|
| 0.0 | PERFECT | 1.00 | ×1.04 | +4% (fine) |
| 0.3 | PERFECT | 0.93 | ×1.04 | **−3%** on a "PERFECT" shot |
| 0.5 | PERFECT (edge) | 0.89 | ×1.04 | **−7%** on a "PERFECT" shot |
| 0.8 | GOOD | 0.82 | ×1.00 | **−18%** on a "GOOD" shot |
| 1.15 | GOOD (edge) | 0.75 | ×1.00 | **−25%** on a "GOOD" shot |

A shot the game itself calls GOOD can land a quarter short. That's the "why
is everything short even when I'm on a roll" feeling, confirmed in the math.

## Real-world grounding
Launch-monitor smash-factor data backs up that this is *not* how real golf
distance loss works. Strikes roughly half an inch off the center of the face
cost only about **1–3% distance** on a modern clubface — real golf is
forgiving of "solid but not flush" contact. Meaningful distance loss in real
golf comes from genuinely poor strikes (thin, fat, off the toe), not from a
slightly-early transition that still finds the middle of the face. A "GOOD"
shot losing 25% has no real-golf analog; a "GOOD" shot losing ~0–5% does.

This also matches a known sore spot in the genre — PGA Tour 2K players
report confusion over swings that felt clean producing unpredictable
distance, because a rhythm-timing score is quietly reshaping distance behind
the scenes. The fix here is the same idea in reverse: make distance
*predictable* from contact quality, and put the "how'd I actually strike it"
signal where players can feel it.

## Fix
**Single source of truth for distance-by-quality: contact tier owns it.**
Tempo-ratio error should only start taxing distance once a shot has already
fallen out of GOOD — i.e. once it's genuinely THIN/FAT/MISS. Inside
PERFECT/GOOD, distance stays flat and `ball_physics.contact_multiplier()`
alone decides the (already-tuned) tier bonus/penalty.

In `scripts/shot/tempo_grade.gd`, replace:
```gdscript
var power_mul := clampf(1.0 - abs_n * 0.22, 0.55, 1.0)
if contact == ShotResult.ContactQuality.MISS:
    power_mul = minf(power_mul, 0.50)
```
with:
```gdscript
# Distance is owned by contact tier (ball_physics.contact_multiplier).
# Tempo error only taxes distance once we're actually out of GOOD —
# inside PERFECT/GOOD, a slightly-off ratio shouldn't leak distance,
# same as real golf: near-center contact costs ~1-3%, not double digits.
var power_mul := 1.0
if contact == ShotResult.ContactQuality.THIN or contact == ShotResult.ContactQuality.FAT:
    var over := maxf(abs_n - BAND_GOOD, 0.0)
    power_mul = clampf(1.0 - over * 0.30, 0.55, 1.0)
elif contact == ShotResult.ContactQuality.MISS:
    power_mul = 0.50
```
`path` (the left/right accuracy term right below this block) is untouched —
it already scales continuously with `abs_n` regardless of tier, which is
exactly the behavior you want: a good shot can still drift left or right,
it just shouldn't come up short.

**Second change**, in `scripts/ball/ball_physics.gd`, nudge the PERFECT
bonus up slightly so a pure strike reads as "10-15 yards longer" on
full-length clubs, not just ~4%:
```gdscript
PERFECT: return 1.06   # was 1.04
```
At 1.06, a driver (260 max) gains ~15.6 yd on a pure strike; a wedge (85 max)
gains ~5 yd — smaller in absolute terms, which tracks real golf too (short
clubs are already standardized/repeatable, there's less room for a "flush"
bonus to show up).

## Net effect after both changes

| Tempo error | Contact label | power_mul | × contact_multiplier | Net result |
|---|---|---|---|---|
| 0.0 | PERFECT | 1.00 | ×1.06 | +6% |
| 0.5 | PERFECT (edge) | 1.00 | ×1.06 | +6% |
| 0.8 | GOOD | 1.00 | ×1.00 | on target |
| 1.15 | GOOD (edge) | 1.00 | ×1.00 | on target |
| 1.5 | THIN/FAT | ~0.90 | ×0.82/0.68 | short, as intended |
| 2.0+ | MISS | 0.50 | ×0.40 | way short, as intended |

This is the "reality spot" you described: good contact lands about the right
distance (drift is left/right via path error, not short/long), a pure strike
goes a bit past, and real mishits are the only thing that comes up short.

## Scope note
This only touches `TempoGrade.grade()`, which drives full-swing and pitch
shots. Chip and putt distance run through `PuttStroke.grade()` instead —
worth a separate look if short-game distance feels off too, but that wasn't
what came up in this playtest session, so leaving it out of scope here.

## Suggested validation
After the change, playtest a stretch of full-swing shots per club and
confirm: GOOD-graded shots land within a couple yards of the committed
target distance, PERFECT-graded shots land ~5-15 yd past it depending on
club, and only THIN/FAT/MISS shots come up short.

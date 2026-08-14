# Correction addendum — add a deadzone to the lateral shape read

Add this to the shot-shape work. Root cause of a real playtest miss: a shot
that felt straight and clean produced a -0.11 draw that missed well left.

## The bug

`shot_routine.gd` (~line 460-463) reads `max_lateral` off the swipe gesture
and turns it directly into `swing_shape` with **no deadzone**:

```
var lat := float(sample.get("max_lateral", 0.0))
swing_shape = clampf(lat / 0.18, -1.0, 1.0)
```

`max_lateral` (`tempo_gesture.gd` ~line 656) is raw perpendicular finger
drift divided by pad height — nothing filters noise out of it. A human
thumb does not travel in a perfectly straight line even on a swing that
*feels* clean. On the playtest shot in question, `lat` was only -0.03 —
roughly 15-25px of sideways drift on a full-height swipe pad, a couple
millimeters on an actual screen. That's not a deliberate draw input, it's
normal hand tremor.

Combined with `_shape_authority()` giving PERFECT contact 1.0 (full)
authority with no damping, that tiny drift became a fully-expressed -0.11
path and sent the ball offline on a shot the player did nothing wrong on.

The takeaway deadzone (`_deadzone()`) already exists to stop this exact
class of problem for swing *start* detection. It was never applied to the
lateral/shape axis.

## The fix

Add a deadzone to `lat` **before** it's converted to `swing_shape`, with a
continuous remap (not a hard cutoff) so there's no dead-then-sudden-jump
feel:

- Below the deadzone: shape contribution is 0 (reads as straight).
- Above the deadzone: scale from 0 at the deadzone threshold up to ±1.0 at
  the existing 0.18 saturation point — don't just subtract the deadzone
  and reuse the old /0.18 divisor, or full shape becomes harder to reach
  than it is today.

Example shape (adjust to match the constant names already in the file):

```
const LAT_DEADZONE := 0.035  # playtest target — tune against feel, not fixed
const LAT_SATURATION := 0.18  # existing value, unchanged

var lat := float(sample.get("max_lateral", 0.0))
var lat_mag := absf(lat)
var swing_shape := 0.0
if lat_mag > LAT_DEADZONE:
    var scaled := (lat_mag - LAT_DEADZONE) / (LAT_SATURATION - LAT_DEADZONE)
    swing_shape = signf(lat) * clampf(scaled, 0.0, 1.0)
```

`0.035` is a starting number, not a final one — it's chosen to sit just
above the -0.03 that produced this bug, so this exact shot would read as
straight. Confirm against a few more playtest reps before locking it in;
if intentional small draws/fades start feeling unresponsive, lower it, but
don't lower it back below ~0.03 or this bug returns.

## Coverage — confirm before assuming more work is needed

This fix reaches **every shot type that uses swipe-derived shape**:
`shot_routine.gd`'s `else` branch (where this fix lives) is one shared code
path for **full swing, pitch, and punch** — they are not separated by shot
type here, so patching this one spot covers all three simultaneously.

**Putt and chip do not need this fix.** They never reach this branch (see
the `shot_type == "putt" or shot_type == "chip"` check just above it) —
they use `PuttStroke._path_error()`, which already has its own deadzone
equivalent: an "arc allowance" that absorbs some lateral drift as the
putt's natural arc before treating it as offline (`excess = |lat| - allow`,
zero below that). That's a different name for the same protective idea,
already in place. Do not add the `LAT_DEADZONE` constant to
`putt_stroke.gd` — it has its own tuned mechanism and doesn't need this
one duplicated on top of it.

## File scope

- `scripts/shot/shot_routine.gd` only — the deadzone/remap logic around the
  `swing_shape = clampf(lat / 0.18, ...)` line (~460-463).
- Do **not** touch `tempo_gesture.gd`'s `_max_lateral` capture. That raw
  value also drives the putt aim-line preview, which is a separate system
  (`PuttStroke`) and out of scope here — filtering it at the capture site
  would change putt behavior too. Filter downstream, in `shot_routine.gd`,
  where only full/pitch/punch shape consumes it.
- Do not touch `_shape_authority()` or the contact-quality scaling — this
  fix is about not treating noise as intent, not about how much authority
  clean contact gets once intent is established.

## Acceptance criteria

- A swipe with `|lat| ≤ 0.035` produces `swing_shape == 0.0` exactly.
- A swipe with `|lat|` at the old saturation point (0.18) still produces
  `swing_shape == ±1.0` (full shape range is preserved, just remapped).
- The regression case: replay the shot that produced `lat -0.03` (this
  playtest shot) — `swing_shape` must now read 0, and with `pull` and
  `dispersion` also at/near 0 on this shot, `shape`/`path` should land at
  or very close to 0 (straight), not -0.11.
- Confirm a deliberate large in-to-out swipe (well above 0.035) still
  produces a visibly curved shot at PERFECT contact — this fix must not
  flatten intentional shot-shaping, only kill noise near zero.

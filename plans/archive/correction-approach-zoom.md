# Correction — Camera Zoom for Short Approach Shots

**Track:** correction, found live during playtest
**Branch:** TBD, from main
**Size:** likely small-to-moderate — tuning existing zoom logic, not building new camera
infrastructure. Grounded in code, not yet implemented — for tomorrow.

---

## The complaint, precisely

On short wedge/approach shots close to the hole, the camera stays too zoomed out to read the
shot clearly — the aim cone, target, and landing area all render small even though the actual
distance being played is short.

---

## What's actually driving zoom today (traced, not assumed)

This isn't a blind system — there's real distance-aware logic already:

```gdscript
// hole_controller.gd:2683-2708, _desired_camera_zoom()
if _is_putt_context():
	// scales zoom continuously against actual ball-to-cup distance
	var dist := ball.global_position.distance_to(_cup_pos)
	...
else:
	var z_cor := _corridor_zoom_level()
	if _aiming and _should_show_green_book():
		z = lerpf(z_cor * 0.92, z_cor * 0.78, ...)
	elif pin_yd <= 90.0:
		z = lerpf(z_cor * 1.08, z_cor, clampf((pin_yd - 28.0) / 62.0, 0.0, 1.0))
	else:
		z = z_cor * 0.88
```

**Putts already do this well** — zoom scales continuously and directly off real ball-to-cup
distance, with tuning notes in the comments showing this was already refined once (*"old floor
+ cap together clamped everything under ~70 ft to one flat zoom"*).

**Non-putt shots don't get the same treatment.** `_corridor_zoom_level()` — the base zoom for
every full/approach/wedge shot — is driven entirely by `_play_corridor_width()`, **a property
of the hole's fairway geometry, not of how far the current shot actually is.** The
`pin_yd <= 90.0` branch does apply a multiplier for short approach distances, but it's a
*modifier on top of* the corridor-driven base (`z_cor * 1.08` down to `z_cor` — at most an 8%
adjustment), not a reframe toward the shot itself. A wide-corridor hole stays wide-framed even
when the shot in hand is a delicate 30-yard wedge.

That's the actual mechanism behind the complaint: **corridor width dominates; shot distance
barely nudges it**, for anything that isn't a putt.

---

## Why this matters more for short shots specifically

A missed read on a 200-yard approach costs little — the target area is large relative to
dispersion. A missed read on a 30-yard wedge is exactly the situation the swing-input pad
legibility work has already been fighting all session (narrow tolerance, hard to place
precisely) — and if the camera is also under-zoomed for that shot, the player loses visual
precision on top of input precision. This likely compounds the marker-clarity and
club-select findings rather than being a fully separate problem.

---

## Proposed direction — not fully scoped yet

Bring non-putt approach zoom closer to how putts already work: **weight shot distance more
heavily against corridor width**, especially inside some short-shot threshold (worth checking
against `TempoGrade.PITCH_YD` / `PITCH_POWER_CAP`, the same distance bands the pitch-shot
auto-selection already uses, rather than inventing a new threshold).

Two real options, needing real numbers before choosing:

1. **Widen the `pin_yd <= 90.0` multiplier's range** — currently maxes out at an 8% pull
   toward tighter zoom. Could scale further for genuinely short shots (wedge/pitch range)
   while leaving mid-approach irons closer to today's framing.
2. **Blend corridor width with shot distance more directly** — rather than a flat multiplier
   on `z_cor`, compute a distance-driven target zoom (similar shape to the putt formula) and
   blend it with the corridor-driven one, weighted toward distance as `pin_yd` shrinks.

**Do not decide between these without checking actual in-game framing at a few real short
distances first** — this needs the same "measure, don't guess" discipline as the club-select
copy fix. A change that looks right in the formula can still look wrong on the actual course
minimap, aim cone, and green.

---

## Out of scope

- Putt camera zoom — already good, don't touch.
- `_flight_camera_zoom()` (the ball-in-flight zoom during the shot itself) — this complaint is
  about the *aim/setup* phase specifically, not the flight animation.
- Pinch-to-zoom override — stays as the player's manual escape hatch regardless of what the
  auto-zoom does.
- Corridor width calculation itself (`_play_corridor_width()`) — not being changed, just
  weighted less dominantly for short shots.

---

## Investigation before implementation

1. Pull actual `pin_yd` and corridor-width values for a few real short-approach situations
   (a 30-yard wedge on a wide-corridor hole vs. a narrow one) and compute what today's formula
   produces, in real zoom numbers — establish the actual baseline before proposing a change.
2. Check whether `_should_show_green_book()` interacts with this in a way that complicates a
   simple multiplier change — that branch already has its own zoom logic for the aim phase.
3. Confirm this is genuinely about the **aim/setup phase** and not also about
   `_flight_camera_zoom()` during the shot itself — playtest may reveal the complaint spans
   both.

---

## Notes for the agent

- This is a "write up for tomorrow" doc, not an approved build spec yet — read, investigate,
  and report a concrete before/after zoom comparison before implementing anything.
- Ground any proposed threshold in existing distance-band constants
  (`TempoGrade.PITCH_YD`, `PITCH_POWER_CAP`) rather than inventing a new one, unless
  investigation shows those don't fit this purpose.
- Touch `hole_controller.gd` only unless investigation finds a real need elsewhere.

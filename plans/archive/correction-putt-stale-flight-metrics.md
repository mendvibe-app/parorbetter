# Correction — Stale Flight Metrics on Putts

**Track:** correction, found live during playtest
**Branch:** `fix/putt-stale-flight-metrics`, from main
**Size:** small — display gating, no gameplay change.

---

## The bug, confirmed by trace

`reset_at()` zeroes `_hang_time_actual` / `_carry_px_actual` / `_launch_speed` at the start of
every shot (`ball.gd:255-257`). Those fields only get real values written back in
`_capture_flight_metrics()`, called from `_begin_roll()` (`ball.gd:549-551`).

**Putts never call `_begin_roll()`.** The putt state machine takes its own separate roll
path (confirmed: `_is_putt` branches around lines 622-630 diverge from the non-putt flight
termination that leads to `_begin_roll()`). So for a putt, those three fields are zeroed at
shot start and never written again — meaning **whatever a putt displays for hang/carry/launch
is left over from the previous non-putt shot**, not this one.

Confirmed live: a 53 ft putt displayed `Carry 141 yd · roll 25 yd · hang 1.03s · launch
110 px/s` — driver-scale numbers, because that's what the last approach shot on the hole
left behind. The debug panel doesn't gate this line by shot type at all — it always prints
`flight_metrics()` regardless of whether the current shot actually populated it.

---

## The fix

`debug_controls.gd`'s flight-metrics line should not print for putts at all — there's nothing
real to show (a putt has no apex, no hang, no carry in the flight sense). Gate the line on
`is_putt`, the same flag already used elsewhere in `ball.gd`.

```gdscript
// debug_controls.gd, wherever the Carry/roll/hang/launch line is built
if not m.get("is_putt", false):
	lines.append("Carry %d yd · roll %d yd · hang %.2fs · launch %d px/s" % [...])
```

Confirm whether `last_shot_metrics` already carries an `is_putt` flag from wherever it's
populated (`hole_controller.gd`'s settle block); if not, add it there rather than inferring
from lie or shot type in the debug panel itself.

**Do not attempt to populate real hang/carry/launch values for putts.** A putt doesn't have a
flight phase — there's no honest number to show. Blank is correct, not a placeholder value.

---

## Out of scope

- The putt's actual result, tempo, or contact grading — all confirmed correct and unrelated
  to this bug. Only the flight-metrics *display* is wrong.
- Any change to `_begin_roll()`, the putt state machine, or when it's called.
- Apex/canopy line — also flight-only, same gating logic should apply if it isn't already.

---

## Acceptance criteria

1. A putt's F1 readout does not show a Carry/roll/hang/launch line at all (or shows it
   clearly blanked, not stale numbers).
2. Non-putt shots are unaffected — line still shows normally.
3. All `*_check.py` pass.

---

## Playtest verification

Hit a full shot, then immediately putt. Confirm the putt's F1 readout no longer echoes the
previous shot's flight numbers.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `debug_controls.gd`, and `hole_controller.gd` only if `is_putt` needs to be
  added to `last_shot_metrics`.
- Small and mechanical. If it needs more than gating a display line, stop and report.

# Green slope align — Phase 1

**Epic:** `plans/green-slope-align-roadmap.md`
**Status:** IMPLEMENTING
**Scope lock:** Honest field + one on-green gravity owner. No book wash. No contour-weight ramp.

## Literals

| Where | Was | Now |
|---|---|---|
| `HoleGenerator` slope mag | `lerpf(0.08, 0.30, …)` | `lerpf(0.024, 0.08, …)` |
| `PIN_MAX_LOCAL_SLOPE` | `0.18` | `0.03` |
| `GREEN_CONTOUR_AMP_SCALE` | `1.55` | `1.0` |
| `tap_in_break` | `0.12` | `0.01` |
| Practice Green `green_slope` | `(0.28, 0)` | `(0.048, 0)` — 2% plane |
| Short Game `green_slope` | `(0.18, 0)` + FLAT | `ZERO` + FLAT |
| `PUTT_BREAK_LATERAL/ALONG` | `90/55` | **deleted** |
| `PUTT_BREAK_CAL_DECEL` | `108` | **deleted** |
| `slope * 16` | chip/pitch/full on green | **deleted** |

```
GREEN_GRAVITY_FT := 32.174
GREEN_GRAVITY_SCALE := 0.45  ## PLAYTEST — rolling ball vs sliding puck; 0.45 ≈ Pelz 2%/20ft
a = GREEN_GRAVITY_FT × GREEN_GRAVITY_SCALE × grade × FT_TO_PX / FRAC² × PUTT_PACE_SCALE²
```

FLAT contour returns zero height/slope even if mag is set (root-cause for the short-game ramp).

On green, skip non-putt anti-backup. Off-green, keep it.

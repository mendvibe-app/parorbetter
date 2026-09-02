# Recon: putt pad height vs distance difficulty

**Status:** hypothesis confirmed. No code change in this pass.  
**Trigger:** playtest — hitting putt distance felt harder lately; guess was the shorter execute panel.  
**Runnable:** `python3 scripts/shot/putt_pad_height_check.py`

---

## Verdict

**Yes. Smaller vertical pad makes the same thumb miss a larger distance miss.** The map did not get “harder” as a formula — it is still the same log fraction of the lane — but the lane is shorter in pixels, so finger jitter is a bigger fraction.

Phase 4 (`SHOT_PANEL_H_PUTT` 640, was 900) is the cut. Spec already flagged it: raise toward 720 if 36-footers feel cramped (`plans/putting-phase4-execute-camera.md`).

---

## Mechanism

Putt power is `power_from_frac(backswing_frac)` with `backswing_frac = peak_disp / lane_len` (`TempoGesture._finish_impact`). Lane is 70% of pad height (`address` 0.22 → `top` 0.92). Pad height is panel minus compact chrome:

`pad = SHOT_PANEL_H_* - SHOT_PAD_TOP_COMPACT(116) - CONTROLS_PAD_BOTTOM(16)`

So **panel height is the input scale.** Log map: constant *fraction* error → constant *%* distance error. Fingers miss in *pixels*, not fractions.

---

## Numbers (desktop, no home-indicator inset)

| | Panel | Pad px | Lane px | PERFECT band | 1 px @ 20 ft |
|---|---:|---:|---:|---:|---:|
| Before Phase 4 | 900 | 768 | 538 | 16.1 px | 0.22 ft |
| Now | 640 | 508 | 356 | 10.7 px | 0.33 ft |
| Handoff “cramped → 720” | 720 | 588 | 412 | 12.3 px | 0.28 ft |

Lane now / then = **0.66** → **34% less travel**, **1.51× distance error per pixel**.

| Putt | 8 px miss @ 900 | 8 px miss @ 640 |
|---:|---:|---:|
| 12 ft | 1.0 ft | 1.6 ft |
| 20 ft | 1.7 ft | 2.6 ft |
| 36 ft | 3.1 ft | 4.7 ft |

On a phone the home indicator shrinks the pad further (`layout_shot_chrome` subtracts safe bottom). Same 640 panel with ~77 vp inset: lane **302 px**, 8 px miss on a 20-footer **~3.1 ft**.

Chip/flop share `SHOT_PANEL_H_PUTT` — same compression if those feel tight too.

---

## Not the cause

- Snap / fall ticks (aim only; gone on Confirm).
- Log map / `BAND_HALF` 0.06 — unchanged. The accept *fraction* is the same; it is just fewer pixels.
- Camera zoom. That is the green, not the stroke pad.

---

## Next (when you want a change)

Raise `SHOT_PANEL_H_PUTT` toward **720** (Phase 4 playtest knob) if you want some green back *and* ~16% more lane than 640. Restoring **900** restores old pace feel and gives the green back to the pad. No map retune needed — height is the scale.

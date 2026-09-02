# Recon: putt pad height vs distance difficulty

**Status:** confirmed. 900 restored (`putt-panel-restore-900.md` / #64).**Trigger:** playtest — hitting putt distance felt harder lately; guess was the shorter execute panel.
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

## Does 640 exist to fit the green?

**No. 900 still fits ball and cup at every length.** `_putt_frame_zoom` sizes zoom to `view.y − HUD − chrome`, and `_putt_frame_look` parks the midpoint in that band. `dist × zoom ≤ safe_h` holds at 640, 720, and 900 (3–75 ft, including a 45° 36-footer).

What the extra window actually does:

| Length | 640 vs 900 |
|---|---|
| ≤ ~6 ft (hit `PUTT_ZOOM_CAP` 130) | Same zoom, same ball size (~26 px). 640 uncovers more grass around it (11.1 vs 8.4 ft in the band). 900 does **not** cover the ball or cup — slack still ~530 px on a 3-footer. |
| 12 ft+ (height-limited) | **Same world span** (zoom scales with the hole in the band). 640 just paints that span with more pixels: 36 ft ball 5.1 vs 3.9 px. |

So Phase 4 did not unblock a clip. It traded pad travel for a taller *pixel* window of the same framing (long) / a bit more uncovered cap-zoom (short). Readability of a true-scale ball on a 36-footer is the real camera argument for keeping *some* reclaim — not “won’t fit.”

---

## Outcome

900 restored (`putt-panel-restore-900.md`). Pace travel is back; camera still fits.

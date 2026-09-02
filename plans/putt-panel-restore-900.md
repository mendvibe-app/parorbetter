# Restore execute panel to 900 (all shot types)

**Status:** SPEC — not started  
**Recon:** `plans/recon_putt_pad_height.md` (640 compresses pace; 900 still fits ball→cup)  
**Supersedes playtest:** `plans/putting-phase4-execute-camera.md` (640 reclaim)

---

## Why

Phase 4 cut putt/chip/flop to `SHOT_PANEL_H_PUTT` 640 so execute wouldn’t spend 47% of the canvas on the pad. Playtest: pace got harder. Recon: power is a fraction of lane height — 640 is **34% less travel**, **1.51× ft error per pixel**. Camera already zooms to the HUD–panel band; 900 does not clip the hole.

Full / pitch / punch never left **900**. Restore that as the one height.

---

## Do this (one PR)

Delete the split. One panel height.

| File | Change |
|------|--------|
| `scripts/ui/ui_scale.gd` | Delete `SHOT_PANEL_H_PUTT`. Keep `SHOT_PANEL_H` 900. Keep `SHOT_PAD_TOP_COMPACT` (meter hide — not panel height). |
| `scripts/shot/shot_routine.gd` `layout_shot_chrome` | `offset_top = -UiScale.SHOT_PANEL_H` always. Compact `pad_top` still only for `uses_stroke_pad`. |
| `scripts/course/hole_controller.gd` `_putt_bottom_chrome` | Visible stroke panel → `SHOT_PANEL_H`. Aim still `abs(CONFIRM_AIM_TOP)`. Drop the `uses_stroke_pad` height branch. |
| Checks | `ui_scale_check.py`: no putt-shorter-than-full assert. `tempo_check.py` / `putt_camera_zoom_check.py` / `putt_pad_height_check.py`: chrome is `SHOT_PANEL_H`. Pad-height recon becomes “lane matches 900.” |
| Docs | `decisions.md`, `AGENTS.md` (if it names 640), `putting-phase4-execute-camera.md` status → reverted. |

Lane fractions stay (`putt` 0.22→0.92). Restoring height restores pixels. No `PuttStroke` map retune.

---

## Shot types (playtest order, same build)

| Type | Today | After | Where |
|------|--------|--------|--------|
| Full / punch / pitch | 900 | 900 (no code) | Practice Range |
| **Putt** | 640 | **900** | Practice Green — 12 / 20 / 36 ft |
| **Chip** | 640 | **900** | Short Game — greenside station |
| **Flop** | 640 | **900** | Short Game — flop station |

Same const, so they all move together. Playtest **putt first** (the report), then chip, then flop. If one type feels like the pad ate the landing, say so — don’t add a second height in this PR.

---

## Out of scope

- 720 compromise
- Changing `SHOT_PAD_TOP` / compact chrome
- Zoom caps, log map, `BAND_HALF`
- Splitting putt vs chip height “to be safe” (recon: 75 ft still fits at 900)

---

## Acceptance

- `SHOT_PANEL_H_PUTT` gone. Grep clean.
- Practice Green: pad as tall as a full-swing pad; 36-footer still shows ball + cup above it.
- Short Game chip + flop: same panel height; remaining-fit still finds the cup.
- Checks: `python3 scripts/ui/ui_scale_check.py` and `python3 scripts/shot/putt_pad_height_check.py`

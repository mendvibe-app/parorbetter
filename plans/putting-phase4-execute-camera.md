# Putting Phase 4 — Execute camera + screen reclaim

**Status:** REVERTING — 640 failed pace playtest. Restore 900: `plans/putt-panel-restore-900.md`.  
**Roadmap:** `plans/putting-rework-roadmap.md`  
**Do not** start Phase 5 polish in this PR.

---

## Problem

Confirm Aim already cuts to true-scale putt zoom (`_aiming` false →
`PUTT_ZOOM_*` branch). ShotPanel is still **900 px / 47%** of the 1920 canvas,
so the execute view spends half the screen on the pad.

---

## Diff

1. `scripts/ui/ui_scale.gd` — `SHOT_PANEL_H := 900`, `SHOT_PANEL_H_PUTT := 640`
   (PLAYTEST). Chip/full stay 900.
2. `scripts/shot/shot_routine.gd` `layout_shot_chrome` — `offset_top = -h`
   from those consts (shot-type only, same as pad compact).

Camera transition is the existing `_process` lerp once `shot_routine.visible`.
No second camera system.

---

## PLAYTEST TARGETS

| Knob | Value | Why |
|------|--------|-----|
| `SHOT_PANEL_H_PUTT` | 640 | 33% vs 47%; pad ≈ 508 px (compact chrome 116) |
| Floor | don't go below ~480 | long-putt pull needs vertical travel |

If 36-footers feel cramped, raise toward 720. If the green still feels
letterboxed, drop toward 560.

---

## Acceptance

- Confirm Aim: book/flag gone, camera tightens to ball→cup, panel shorter
  than a full swing.
- Putt stroke still usable (pace marker reachable). Full/chip panel unchanged.
- Check: `python scripts/ui/ui_scale_check.py` and
  `python scripts/shot/tempo_check.py`

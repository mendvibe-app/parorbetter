# Playtest todo: Pitching feel / bugs

**Status**: Open — player reports ongoing pitch issues in playtest  
**Date noted**: 2026-07-29  
**Code**: `TempoGrade.shot_type_for`, `ShotRoutine`, `TempoGesture` (pitch ≠ chip pad)

## How pitch is wired today

| Aim distance | Type | Pad | Grade | Golfer |
|--------------|------|-----|-------|--------|
| Green | putt | amplitude | PuttStroke | putt |
| **&lt; 20 yd** (`CHIP_YD`) | **chip** | amplitude (chip chrome) | PuttStroke | chip |
| **20 → gate** | **pitch** | **full tempo pad** | TempoGrade **2:1** | chip |
| ≥ gate | full | full tempo pad | TempoGrade 3:1 | full |

Pitch gate = `min(50, club_max * 0.42)` when a club is known.

## Audit

1. **Contract drift fixed**: chip gate mirrored in `tempo_check.py`.
2. **2:1 ghost was misleading (fixed 2026-07-29)**:
   - Pitch used the **same full-length lane** as 3:1, with ghost back **0.50s** and through **0.25s** (same through as full). Ghost raced; beat pips still showed two mid marks (read as 3:1).
   - **Fix**: shorter pitch lane (`top` 0.70 vs full 0.92); `GUIDE_BACK_SHORT` **0.64** → through **0.32** (still exact 2:1); beat pips **1 mid** for 2:1 / **2 mids** for 3:1.
3. Grading math was fine — target 2.0, sample is bs/ds timestamps.
4. Gap@40yd still maps **full** (gate quirk) — separate from ghost issue.

## Still watch in playtest

- Club + aim yd + hint text when it still feels off  
- After fix: does matching the (slower, shorter) ghost land near 2:1 on the meter?

# Putting Phase 3 — Read-phase camera + flag

**Status:** SHIPPED — already in tree (green book + pin); locked 2026-08-27  
**Roadmap:** `plans/putting-rework-roadmap.md`

Read view **is** putt aim: flag in, book wash on, **ball→cup frame** (not
whole-green — that postage-stamped a 17 ft line). Chips still get whole-green
book zoom. Execute hides the flag and closes the book.

| What | Where |
|------|--------|
| Flag on green iff `_aiming` | `hole_controller.gd` `_sync_pin_flag_visible` |
| Book + `GREEN_BOOK_ZOOM_CAP` 36 | `_desired_camera_zoom` / `_should_show_green_book` |
| Flag out + book off on Confirm | `_start_power_swing` / `_confirm_aim` |

**Acceptance (already true in playtest dumps):** flag up while setting line;
gone after Confirm; book + aim line share the wide frame.

Check: `python scripts/course/green_book_check.py`

Next: Phase 4 execute panel reclaim.

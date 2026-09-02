# Handoff — Putting / true-scale / green book (2026-08-27)

**Board:** `plans/README.md` (putting rework is Active)  
**Pick up with:** this file + `plans/putting-rework-roadmap.md`

---

## Where we are

### Shipped (recent)

- **True-scale** ball/cup everywhere; putt + chip **pace scales**; lip-out chip leave capped
- **Cameras:** mid-approach widen; long-tee open + look-toward-pin; putt UI-safe look; **no green-book zoom from 180+ yd**
- **Greens:** densified 768 calm mow; slope plane weakened / contours stronger
- **Green book:** filtered height wash (warm=high, cool=low) + **fall-line arrows**
- **Course pin:** screen-scaled stick; flag at tip; in for putt **aim**, out for stroke
- **Putt line aim (default):** bearing drag, distance locked to cup. F1 flag gone. Spec: `plans/putting-phase0-line-interaction.md` (signed off)
- **Phase 1 contact:** Green curve in `resolve_distance` (THIN 1.06 / FAT 0.90 / MISS 0.78) + mishit line floor — playtested
- **Phase 3 read camera:** book zoom + flag during aim; flag out on Confirm
- **Phase 4 execute panel:** 640 reverted — all types use `SHOT_PANEL_H` 900 (`putt-panel-restore-900.md`)

### Still open / next

1. **Playtest 900 panel** — Practice Green 12 / 20 / 36 ft, then Short Game chip, then flop.
2. **Phase 5** — short-putt glow / green-art bump (parked until 4 ships).
3. **Green book polish** — arrow density (`GREEN_BOOK_ARROW_N`), wash alpha
4. **Pin art** — optional PixelLab crisp pin

---

## Key files

| Area | Path |
|------|------|
| Putt line aim | `hole_controller.gd` `_apply_aim_world`, `_putt_line_soft_snap` |
| Green book | `hole_controller.gd` `_build_green_book`, `_GreenBookDraw` |
| Course pin | `course_pin_flag.gd` |
| Chip/putt pace | `ball_physics.gd` `PUTT_PACE_SCALE` / `CHIP_PACE_SCALE` |
| Roadmap | `plans/putting-rework-roadmap.md` |

**Do not** start Phase 5 polish before Phase 4 panel height is playtested.

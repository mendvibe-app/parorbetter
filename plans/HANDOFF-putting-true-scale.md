# Handoff — Putting / true-scale / green book (2026-08-27)

**Repo:** `main` (commit after this push)  
**Pick up with:** this file + `plans/putting-rework-roadmap.md` + `plans/putting-phase0-line-interaction.md`

---

## Where we are

### Shipped (recent)

- **True-scale** ball/cup everywhere; putt + chip **pace scales**; lip-out chip leave capped  
- **Cameras:** mid-approach widen; long-tee open + look-toward-pin; putt UI-safe look; **no green-book zoom from 180+ yd**  
- **Greens:** densified 768 calm mow; slope plane weakened / contours stronger  
- **Green book:** filtered height wash (warm=high, cool=low) + **fall-line arrows** (yardage-book style, not topo grid)  
- **Course pin:** screen-scaled stick; **flag at top of pole**; in for putt **aim**, out for stroke  
- **Phase 0 putt line:** F1 `Putt line aim (Phase 0)` / `GameState.debug_putt_line_aim` — bearing drag, distance locked to cup  

### Still open / next for a new agent

1. **Phase 0 sign-off** — Matt playtests line aim; then promote or tweak snap (`PUTT_LINE_*`)  
2. **Putting rework roadmap** — Phase 1 `contact_mul` on green; Phase 2 make line aim default; Phases 3–4 read/execute camera (**after** line is stable)  
3. **Green book polish** — arrow density (`GREEN_BOOK_ARROW_N`), wash alpha; optional PixelLab yardage-book overlay if procedural still feels weak  
4. **Pin art** — optional PixelLab crisp pin if vector pin isn’t enough at true-scale  

---

## Key files

| Area | Path |
|------|------|
| Green book | `hole_controller.gd` `_build_green_book`, `_GreenBookDraw` |
| Course pin | `course_pin_flag.gd` |
| Putt line prototype | `GameState.debug_putt_line_aim`, `_apply_aim_world` |
| Chip/putt pace | `ball_physics.gd` `PUTT_PACE_SCALE` / `CHIP_PACE_SCALE` |
| Roadmap | `plans/putting-rework-roadmap.md` |

---

## Playtest focus after pull

1. Green book: soft wash + **arrows = downhill**; legend text  
2. Pin: thin pole, **red flag at tip**  
3. F1 line aim on short + long putts  

**Do not** start camera Phases 3–4 before Phase 0/2 line is signed off.

# Decisions

Log of gameplay-affecting decisions, added as they happen.

- **Tempo swing (supersedes concurrent dual-pad):** single-thumb drag graded on backswing:downswing time ratio (full ~3:1, chip/putt ~2:1). Fast ≠ good — only the ratio is scored. Rushing costs both distance and accuracy. Balance is a tolerance-window modifier from gesture qualities, not a second meter. Power is committed pre-swing (`recommended_power` until club-and-power epic); gesture multiplier ≤ 1.0.
- **14-hcp miss model:** slight tempo error → mild curve + mild distance leak (GOOD band wide); duff/hosel (MISS) only when clearly off, incomplete, or extreme ratio. Physics contact multipliers stay harsh for true MISS.
- **Swing legibility:** pad landmarks (START / TOP / THROUGH / FOLLOW), live trail color + ratio strip needle; post-shot uses `ShotReport.glance_text` (tempo diagnosis + contact/balance), full dump in F1 only.
- **Driving range:** `GameState.range_mode` + `HoleController.load_range` — flat tee, skip aim, infinite reset; enter/exit from F1 debug.
- Pure-strike SFX: dropped the three-tone chime for a short low-mid noise knock + pitch-down release (same physical-transient approach as cup-in) so flush contact reads solid, not arcade-triumphant.
- ~~Concurrent shot input~~ (retired): power/stance + swing timing dual pads resolved on impact tap.
- ~~Early-release soft crush~~ (retired with dual-pad): lifting finger 1 crushed stability; replaced by balance-from-gesture.
- **HUD cleanup:** scorecard header `HOLE n · PAR p · YDS`; AdaptLabel form/○radius/bias text retired (circle + F1 carry form). Wind is a tappable flagstick (lean/wave; advice on tap) plus rim bias arrow on the aim circle — not banner sentences. Lie/club are silhouette icons beside pin yardage; club bag buttons reuse the same club icons.


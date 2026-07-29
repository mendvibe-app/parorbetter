# Decisions

Log of gameplay-affecting decisions, added as they happen.

- **Tempo swing (supersedes concurrent dual-pad):** single-thumb drag graded on backswing:downswing time ratio (full ~3:1, putt/pitch ~2:1). Fast ≠ good — only the ratio is scored. Rushing costs both distance and accuracy. Balance is a tolerance-window modifier from gesture qualities, not a second meter. Power is committed pre-swing (`recommended_power` until club-and-power epic); gesture multiplier ≤ 1.0.
- **14-hcp miss model:** slight tempo error → mild curve + mild distance leak (GOOD band wide); duff/hosel (MISS) only when clearly off, incomplete, or extreme ratio. Physics contact multipliers stay harsh for true MISS.
- **Swing legibility:** pad landmarks (START / TOP / THROUGH / FOLLOW), live trail color + ratio strip needle; post-shot uses `ShotReport.glance_text` (tempo diagnosis + contact/balance), full dump in F1 only.
- **Driving range:** `GameState.range_mode` + `HoleController.load_range` — flat tee, skip aim, infinite reset; enter/exit from F1 debug.
- Pure-strike SFX: dropped the three-tone chime for a short low-mid noise knock + pitch-down release (same physical-transient approach as cup-in) so flush contact reads solid, not arcade-triumphant.
- ~~Concurrent shot input~~ (retired): power/stance + swing timing dual pads resolved on impact tap.
- ~~Early-release soft crush~~ (retired with dual-pad): lifting finger 1 crushed stability; replaced by balance-from-gesture.
- **HUD cleanup:** scorecard header `HOLE n · PAR p · YDS`; AdaptLabel form/○radius/bias text retired (circle + F1 carry form). Wind is a tappable flagstick (lean/wave; advice on tap) plus rim bias arrow on the aim circle — not banner sentences. Lie/club are silhouette icons beside pin yardage; club bag buttons reuse the same club icons.
- **Putting distance realism:** greens ~60–130 ft diameter (was ~112–208 airport); putt camera zooms out on lags (`view_min * 0.52`, max z 7.5); green ball 1.0 / cup 2.4; putter max 40 yd / 120 ft; soft pad labels 30 ft + ticks 45/60/90.
- **Putt break readable:** lateral/along gains 90/55 (was 22/14); slope mag 0.10–0.48; early FLAT weight cut so contours move the ball (~2 ball-widths on a mid-slope 40 ft).
- **Putt pace feel:** absolute linear pad; soft ticks are landmarks (labeled 3–30, ticks 45/60/90) — no aim highlight; feel/guess where THIS putt sits. FAT/THIN no longer stack distance — amplitude owns pace, contact owns line.
- **Putt line lane:** `ARC_FLOOR` 0.10 / `ARC_SCALE` 0.16 + lane tex 56; putt address/top 0.22–0.92 for finger resolution on 15 vs 30.
- **Putt distance reads long:** camera frames ball→cup only (no green-radius floor); flag 12 px + hidden while putting (pin out).
- **Putt follow cue:** drawn finish grows with pace/backswing (pad-capped); grade matches `min(backswing, follow_cap)` — only short-of-cue chops distance. Old fixed 12% stub taught a chop on lags.
- ~~Relative putt pad~~ (retired): mid-lane = on pace made distance trivial; back to absolute soft scale.
- **Putt free pace:** smash/leave short do not auto-MISS or half-power; amplitude owns distance; hole-out from line + cup physics. MISS reserved for incomplete/stubbed strokes.
- **Putt camera zoom-in (short putts):** old `half_span` floor (34) + zoom cap (7.5) together clamped every putt under ~70 ft to one flat zoom — short and 40 ft putts looked identical. New floor 12 / pad 6 / cap 42 so `<~10 ft` reads clearly tighter than 20-40 ft at aim, and lag putts still zoom out. **Roll hold:** zoom/look lock at stroke start (`_putt_cam_*`); soft ball drift only — no live zoom-in or tight ball chase mid-roll (that felt jarring on short putts). Settle clears the lock and reframes from the resting ball.


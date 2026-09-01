# Plan — Flop at chip distances (recon + Phase 1)

**Status:** CODE COMPLETE — playtest remaining (Range, LW, pick Flop).  
**Origin:** Playtest flop at ~4 yd to pin still flew ~30 yd (LW, THIN, Plan 30 → Actual 28). User: flop should dial short like a chip; optional at chip range; high, over hazards, land soft.  
**Scope lock:** Flop **input family** only — join chip’s `PuttStroke` pad. Keep flop **flight** (apex, air share, check, wider aim circle). `FLOP_MAX_YD` 30 stays a **ceiling**, not a floor. Pitch / full / putt / chip pad map / `shot_type_for` — untouched.  
**User lock:** Optional picker shot at chip-like distance. ★ stays chip under 20 yd. SW/LW only. Real-golf trade: carry over trouble, sit, more miss than a chip.

---

## The shot (what happened)

F1, one swing (abridged):

```text
Aim ○ 4 yd · long 20 yd  [flop]
Amp BS len 0.19 frac 0.38
commit 28% · true 68% · rolled 65%
THIN
Plan 30 yd → Actual 28 yd   carry 26 + roll 2
Club LW
```

Working as coded. Unusable as a short shot.

---

## Phase 0 — Findings

### Real golf (what we want)

Same distance window as a chip (~a few yards to ~20–30). Chip runs. Flop is the override when you need **height and a soft land** (bunker lip, collar, short-sided). Tour flop is not a 30-yard-minimum shot. A 8-yard flop over a bunker is a normal shot. ★ is still the chip; flop is the player choosing the extra height / extra miss.

Archived `plans/archive/short-game-roadmap.md` Phase 5 already said this: ~10–30 cap, **never default**, SW/LW, tempo family, harsher miss. Distance cap shipped. Short dial did not.

### Why the shortest flop is ~30 yd

Flop is on the **tempo amplitude pad**, not the chip pad.

| Step | Where | What it does |
|------|--------|----------------|
| Power from pull | `BallPhysics.power_from_amplitude` | Linear map **only** `POWER_POCKET_LO` (0.60) → 1.0. Tiny pull still ~60%+. |
| Preview floor | `hole_controller._apply_committed_preview` / `_aim_planned_total_yd` | Pitch **and flop** `maxf(power, POWER_POCKET_LO)`. |
| Ceiling | `FLOP_MAX_YD` 30 in `resolve_distance` + configure cap | `min(65 × 0.60, 30) = 30`. |

`aim_control_check.py` **asserts** this: 20 yd flop + LW + floor → preview **30**. Honest overshoot from swing-input Phase 5, wrong for a flop you picked to sit at 4–20 yd.

Chip already solved short dial: `PuttStroke` log map, `POWER_FLOOR` 0.0267 (~2 ft on the putter / a few yards on LW), ticks in yards, pull length = power. Comments that say pitch/chip/flop “keep true %” are half-true: `solve_committed_power` does (`shot_type_uses_full_pocket` is full/punch only). **Launch** for flop still goes through `power_from_amplitude`.

Linear tempo pad at 6% of LW (4 / 65) is unplayable. Do not invent a third pad.

### What already matches real golf (keep)

- Picker: flop on SW/LW only (`eligible_shot_types`). PW/GW cannot flop.
- `TempoGrade.shot_type_for` **never** returns flop. Under `CHIP_YD` (20) ★ is chip. Flop is a manual override — picker already shows it at chip distances.
- Flight: air ~0.92–0.98, loft ×1.35, `APEX_SCALE_FLOP`, check mul ×1.4. Near-zero roll.
- Aim circle: flop > pitch > chip at equal rest yards (`short_game_aim_radius_yards`).
- Tree recommend: `_recommended_shot_type` may bump chip → **pitch** when the line is blocked. Does **not** bump to flop. Leave that.

### Contact today (tempo family)

`TempoGrade.grade` flop: harsher `thin_tax` / floors (Phase 5 “mistakes hurt”). THIN **shortens**. Real bladed flop often **runs hot**. After the pad move, contact comes from `PuttStroke.grade` (chip: overpull = long, THIN label, no 0.82 distance cliff). Start there. Playtest that a bladed flop is long/hot, not a 30-yard sit.

---

## Rejected (do not do)

| Idea | Why not |
|------|---------|
| Lower `POWER_POCKET_LO` for flop only | Linear 6% pull on the tempo lane is still unreadable. Chip pad exists. |
| Drop `FLOP_MAX_YD` | Ceiling is correct. The bug is the floor. |
| Auto-★ flop over bunkers / trees | Real golf optional. Picker is enough. Hazard ★ is a later ticket. |
| New flop pad / new log constants | Chip map + flop ticks. |
| Change pitch the same way | Pitch stays 60% pocket + 2:1 tempo. Different shot. |
| Teach `shot_type_for` to return flop | Breaks “rarely default.” |

---

## Phase 1 — Flop joins chip’s input family (one PR)

**Flight stays flop. Input becomes chip.**

Same pad, same log map (`POWER_FLOOR` / `BEND`), same grade shape as chip (`power_mul = actual / target` frac). Flop chrome: ticks through 30 yd, flop hints, flop flight on launch.

### Identity gate

Sibling of `uses_amplitude_power` — one place so callers cannot drift:

```gdscript
static func uses_stroke_pad(shot_type: String) -> bool:
	return shot_type == "putt" or shot_type == "chip" or shot_type == "flop"
```

Remove `"flop"` from `uses_amplitude_power`. Grep `"putt" or "chip"` and `uses_amplitude_power` — every site that means “PuttStroke family” uses the helper (routine begin/grade/path, compact panel height, meter draw, hints). Pitch stays amplitude.

`tempo_gesture`: flop leaves `_is_pitch()` and `_uses_short_lane()`. Flop uses **chip** lane geometry (`CHIP_ADDRESS_Y` / `CHIP_TOP_Y`, `_is_chip()` or the helper). Keep `_uses_chip_golfer()` including flop (wedge posture).

### Pad ruler

Reuse chip log map. Do **not** retune chip `CHIP_SCALE_*` or `BEND`.

Flop ticks (yards, same idea as chip’s 20-yd ruler):

- Labeled: `[5, 10, 15, 20, 30]` (or chip’s list + 30)
- Ticks: chip list + `25`

**Map ceiling = `FLOP_MAX_YD`, not club max.** Full pull = 30 yd, not 65 then silent clamp. `marker_frac` / `power_from_frac` for flop use `POWER_CEIL = FLOP_MAX_YD / club_max_yd` (LW ≈ 0.46, SW ≈ 0.375). Committed power is still `need / club_max` (physics fraction). 4 yd LW ≈ 6% → readable short pull on a 30-yd ruler.

`PuttStroke.grade`: flop takes the **chip** `power_mul` branch (`shot_type == "chip"` → also flop). Chip `CHIP_TOL_SCALE` / `CHIP_ARC_SCALE` start at 1.0 for flop too (playtest knobs later, don’t invent flop scales now).

`contact_multiplier`: flop PERFECT = **1.0** (committed yards), same as chip. Keep the chip overpull rule (THIN label, no 0.82 tax when `frac_err > 0`). FAT underpull still taxes.

### Preview / cap

- Drop flop from the `POWER_POCKET_LO` floors in `_apply_committed_preview` and `_aim_planned_total_yd`. **Pitch keeps the floor.**
- Always pass `shot_type` into `estimate_carry_yards` in `_apply_committed_preview` (today the non-pitch branch omits it). Flop still needs it so `resolve_distance` can cap at 30.
- Keep `FLOP_MAX_YD` in `resolve_distance` and the configure committed-power cap.
- 4 yd flop preview = ~4 yd. 20 yd = 20. 40 yd aim still 30.

### Recommend / picker

No change. ★ = `shot_type_for` (chip < 20). Flop remains in the picker on SW/LW at those distances.

### Hints / chrome

Flop hint: chip language, flop identity — pull length = power, high, sits, little roll. Drop “~2:1” as the skill (tempo explains a miss, like chip). Compact panel height (`SHOT_PANEL_H_PUTT` / `SHOT_PAD_TOP_COMPACT`) — flop is on the chip pad now.

Do not retune aim-circle bands in this PR. Existing rest-yard lerp already shrinks a 4 yd flop vs a 20 yd flop.

---

## Files (expected)

| File | Change |
|------|--------|
| `scripts/ball/ball_physics.gd` | `uses_stroke_pad`; flop out of `uses_amplitude_power`; flop PERFECT contact 1.0 |
| `scripts/shot/shot_routine.gd` | Flop → PuttStroke begin/grade/path; hints; compact chrome |
| `scripts/shot/putt_stroke.gd` | Flop scale ticks; flop map ceiling `FLOP_MAX/club_max`; chip `power_mul` for flop |
| `scripts/shot/tempo_gesture.gd` | Flop = chip lane, not pitch short lane |
| `scripts/shot/meter_display.gd` | Flop = putt/chip amplitude meter |
| `scripts/course/hole_controller.gd` | Preview: flop not pocket-floored; always pass `st` |
| Checks below | Rewrite the contracts that freeze the 30-yd floor |

`TempoGrade.TOL_FLOP` / flop `thin_tax` become unused for launch once flop leaves `TempoGrade.grade`. Leave the constants; don’t delete in this PR unless a check requires it.

---

## Self-check (rewrite, don’t stack a third file unless needed)

| Check | Today | After |
|-------|--------|--------|
| `aim_control_check.py` | 20 yd flop + floor → 30 | 20 yd flop preview = 20; 4 yd = 4; 40 yd = 30. Pitch floor cases **unchanged**. |
| `amplitude_short_check.py` | flop in `uses_amplitude_power`; lane 0.50 | flop **not** in that gate; flop lane = chip 0.65; `uses_stroke_pad` |
| `shot_type_picker_check.py` | eligible SW/LW | still; assert `shot_type_for` never `"flop"` |
| `putt_stroke_check.py` | chip map | flop 4 yd / 20 yd / 30 yd on the flop ceiling; chip asserts bit-identical |
| `flight_model_check.py` / `club_identity_check.py` | air / `FLOP_MAX` | air + ceiling unchanged |

One runnable flop dial check (can live in `putt_stroke_check` or a tiny `flop_short_check.py`): LW, 4 yd, power from a short stroke-pad frac → total ≪ 30; 30 yd pull → ~30; 1.0 pull → 30 not 65.

Headless: `godot --headless --quit-after 120` still 0.

---

## Playtest (after code)

Practice Range, LW, pick **Flop** (not ★):

1. ~8–12 yd to a flag / mat — marker is a short pull; tick-hit lands ~that carry, sits (few yards roll).
2. Same distance **Chip** — lower, more roll. Flop is the height/sit trade.
3. Full flop pull — ~30 yd, not LW 65.
4. Overpull on a 12 yd flop — a bit long, not a teleport to 30.
5. THIN / blade — long/hot vs chip, not a 30-yd floor sit.
6. SW still flops; PW picker has no Flop.
7. Under 20 yd, ★ is still Chip.

---

## Later (not this PR)

- ★ flop when the chip line is blocked by a bunker lip / tree (extend `_recommended_shot_type`).
- Flop-specific `CHIP_TOL_SCALE` if the chip band is too soft/hard on a high shot.
- Delete dead `TOL_FLOP` once nothing reads it.
- Pitch short-dial (user did not ask).

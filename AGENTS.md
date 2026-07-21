# AGENTS.md — Par or Better

Godot 4 mobile golf prototype. One run = generated 18-hole course, lives, form-driven aim, single-thumb tempo swing (backswing:downswing ratio — the core skill).

Coding philosophy is already enforced: read `.cursor/rules/ponytail.mdc` before changing code. Shortest correct diff; reuse existing helpers; no new deps/abstractions unless asked. Non-trivial logic leaves one lightweight self-check (assert/demo/`*_check.py`).

## Shot loop (end to end)

Orchestrated by `HoleController` + `ShotRoutine`.

1. **Club select** (`ClubSelect`) — Off green: pick from `BallPhysics` bag (sand → wedges only). Green skips to putter. Confirm commits.
2. **Aim** (`HoleController` aim phase + `AimControl`) — Drag bearing; yellow dispersion circle = form radius from `GameState.get_aim_radius_yards`. Confirm Aim / Space locks target. Optional **Practice Swing** grades tempo with no stroke.
3. **Tempo strike** (`TempoGesture` + `TempoGrade`, one `Phase.ACTIVE`) — Thumb drag: takeaway → top (velocity reversal) → impact (cross address). Graded on backswing:downswing **ratio** (full ~3:1, chip/putt ~2:1), not total speed. Balance from gesture qualities tightens the tolerance window. Committed power = `recommended_power` until club-and-power epic; gesture multiplies it ≤ 1.0 (can only subtract). Pure = PERFECT contact + balance ≥ 0.72.
4. **Result** — `ShotRoutine` → `ShotResult` → `BallPhysics.launch_velocity` → `GolfBall` flight/roll → settle/hazard/cup → `ShotReport` (tempo line) + lives/`Scoring` on hole-out. Earned pure: compression SFX, haptic, slow-mo/camera punch, brighter trail, round pure counter.

## Key gameplay constants

| What | Where |
|------|--------|
| Full-swing tempo target | `TempoGrade.TARGET_FULL` (3.0); tol half-width `TOL_FULL` (0.5 → accept ~2.5–3.5 at full balance) |
| Short/putt tempo target | `TempoGrade.TARGET_SHORT` (2.0); `TOL_SHORT` (0.4) |
| Pure balance gate | `TempoGrade.PURE_BALANCE` / `ShotRoutine.PURE_BALANCE` (0.72) |
| Dispersion circle (full shot) | `GameState.AIM_RADIUS_WEAK_YD/MID/PRO` (40 / 22 / 10 yd); `get_aim_radius_yards()` |
| Dispersion circle (putt) | `GameState.PUTT_RADIUS_WEAK_YD/PRO` (2.7 / 1.0 yd) |
| Form history window | `GameState.FORM_HISTORY_MAX` (8) |
| Cup catch radius | `HoleController.CUP_RADIUS` (7.0 px) |
| Yards ↔ pixels | `BallPhysics.PX_PER_YARD` (2.25) |
| Air vs roll split | `BallPhysics.AIR_DISTANCE_FRACTION` (0.78) |
| Green slope field | `HoleData.green_slope` + `green_height_at` / `green_slope_at` (shared by putt physics + green book) |
| Lie timing tighten | `BallPhysics.lie_timing_scale` (scales tempo tolerance width) |
| Lives | `GameState.MAX_LIVES/START_LIVES`; deltas via `GameState.apply_hole_result_lives` |
| Pure strikes (round) | `GameState.pure_strikes` / `record_pure_strike()` |
| UI type scale | `UiScale.CAPTION/BODY/TITLE` (32 / 40 / 48); celebration 56–64 in scenes |
| Touch target min | `UiScale.TOUCH_MIN` (120 px on 1080-wide canvas ≈ 44–48pt) |
| Safe-area insets | `UiScale.viewport_safe_margins` / `apply_hole_safe_area` |

## Folder map (`scripts/`)

| Path | Belongs here |
|------|----------------|
| `shot/` | Club select, aim helpers, tempo gesture/grade, shot routine/result, arc meter math (autoload `ArcMeters`) |
| `ball/` | Ball node + launch/lie/physics helpers |
| `course/` | Hole data/resource, generator, hole controller (build + shot UI glue) |
| `systems/` | Scoring, shot report formatting |
| `ui/` | HUD, shot result panel, game over, `UiScale` (type/touch/safe-area) |
| `autoload/` | `GameState`, `AudioBus` (ArcMeters lives under `shot/` but is autoloaded) |
| `debug/` | F1 debug panel — prototype tooling (tempo tol / balance tighten / release=impact) |

Scenes under `scenes/`; art under `assets/`.

## Autoloads (`project.godot`)

- **GameState** — Run state: lives, hole index, generated course, form + path-miss history, pure-strike count, aim-radius helpers, adaptation bias helpers, debug overrides (incl. tempo tol), tempo guide flags, run end.
- **AudioBus** — Procedural SFX (`AudioStreamGenerator`): contact, pure (compression transient), putt drop, birdie, splash, UI, tempo `play_tick()`. No asset pack.
- **ArcMeters** (`scripts/shot/arc_meter_math.gd`) — Shared geometry for swing arc meters (angles, polylines, draw helpers). Note: `tempo_*` helpers are the **power-arc** draw API name, not the 3:1 ratio grade.

## Entry

`scenes/main.tscn` → `main.gd` loads hole 1, wires next-hole / game-over / debug.

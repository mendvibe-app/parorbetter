# AGENTS.md — Par or Better

Godot 4 mobile golf prototype. One run = generated 18-hole course, lives, form-driven aim, single-thumb tempo swing (backswing:downswing ratio — the core skill).

Coding philosophy is already enforced: read `.cursor/rules/ponytail.mdc` before changing code. Shortest correct diff; reuse existing helpers; no new deps/abstractions unless asked. Non-trivial logic leaves one lightweight self-check (assert/demo/`*_check.py`).

## Shot loop (end to end)

Orchestrated by `HoleController` + `ShotRoutine`.

1. **Club select** (`ClubSelect`) — Off green: 3 clubs near `BallPhysics.pick_club` (★), **Full bag** for the rest (sand → wedges only). Green skips to putter. Confirm commits. **Driving range** (F1 → Driving Range): same club pick, then skip aim.
2. **Aim** (`HoleController` aim phase + `AimControl`) — Drag bearing; yellow dispersion circle = form radius from `GameState.get_aim_radius_yards`. Confirm Aim / Space locks target. Optional **Practice Swing** grades tempo with no stroke. Range mode skips this (fixed center aim). On green: aim-drag is line + pace; short flat putts (`GameState.tap_in_yd` / `tap_in_break`) skip aim and go straight to stroke.
3. **Strike** — Full/chip: `TempoGesture` + `TempoGrade` (backswing:downswing ratio). Putt: same gesture pad, re-skinned; `PuttStroke` grades **amplitude vs pace marker** (power), **arc path** (line), tempo as miss-explainer. Committed power = `recommended_power`; gesture multiplies. Pure = PERFECT + balance ≥ 0.72.
4. **Result** — Glance panel (`ShotReport.glance_text`: tempo diagnosis for full; distance/line for putt). Full dump stays in F1. Range: ball resets to tee and loops. Course: settle → next shot / hole-out lives via `Scoring`.

## Key gameplay constants

| What | Where |
|------|--------|
| Full-swing tempo target | `TempoGrade.TARGET_FULL` (3.0); tol half-width `TOL_FULL` (1.1 → accept ~1.9–4.1 at full balance; 14-hcp miss model) |
| Chip tempo target | `TempoGrade.TARGET_SHORT` (2.0); `TOL_SHORT` (0.85) |
| Putt stroke (amplitude) | `PuttStroke.marker_frac` (sqrt map); `BAND_HALF` (0.06 pad frac); line via `arc_allowance` |
| Tap-in fast path | `GameState.tap_in_yd` (4.0) + `tap_in_break` (0.12) |
| Pure balance gate | `TempoGrade.PURE_BALANCE` / `PuttStroke.PURE_BALANCE` / `ShotRoutine.PURE_BALANCE` (0.72) |
| Dispersion circle (full shot) | `GameState.AIM_RADIUS_WEAK_YD/MID/PRO` (40 / 22 / 10 yd); `get_aim_radius_yards()` |
| Dispersion circle (putt) | `GameState.PUTT_RADIUS_WEAK_YD/PRO` (2.7 / 1.0 yd) |
| Form history window | `GameState.FORM_HISTORY_MAX` (8) |
| Cup catch radius | `HoleController.CUP_RADIUS` (12.0 px); ball `BALL_R` (5.0) — cup ≈ 2.4× ball |
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
| `debug/` | F1 debug panel — tempo tol / balance / release=impact / **Driving Range** |

Scenes under `scenes/`; art under `assets/`.

## Autoloads (`project.godot`)

- **GameState** — Run state: lives, hole index, generated course, form + path-miss history, pure-strike count, aim-radius helpers, adaptation bias helpers, debug overrides (incl. tempo tol), tempo guide flags, `range_mode`, run end.
- **AudioBus** — Procedural SFX (`AudioStreamGenerator`): contact, pure (compression transient), putt drop, birdie, splash, UI, tempo `play_tick()`. No asset pack.
- **ArcMeters** (`scripts/shot/arc_meter_math.gd`) — Shared geometry for swing arc meters (angles, polylines, draw helpers). Note: `tempo_*` helpers are the **power-arc** draw API name, not the 3:1 ratio grade.

## Entry

`scenes/main.tscn` → `main.gd` loads hole 1, wires next-hole / game-over / debug.

## Cursor Cloud specific instructions

Engine: **Godot 4.7.x** at `/usr/local/bin/godot` (installed by the update script). Matches `project.godot` `config/features` ("4.7"). GDScript only — no C#/Mono build.

- **Tests / "lint":** there is no GDScript linter or CI. The test suite is the Python contract checks (`scripts/**/*_check.py`) — each parses the sibling `.gd` and asserts gameplay constants/logic haven't drifted. Run all: `for f in scripts/*/*_check.py; do python3 "$f" || break; done` (Python 3 is preinstalled). Add one check alongside non-trivial gameplay logic (ponytail rule).
- **Headless sanity check:** `godot --headless --import` (imports assets, generates `.godot/`), then `godot --headless --quit-after 120` runs `main.tscn` for 120 frames and surfaces any GDScript parse/runtime errors. Both exit 0 when clean.
- **Run the game (GUI):** `DISPLAY=:1 godot --path /workspace`. The VM has no GPU/audio, so Godot logs (harmless, expected) `VK_KHR_surface not found` → falls back to OpenGL/`llvmpipe` software rendering, and ALSA errors → dummy audio driver. The game still renders and plays fine. Use the F1 debug panel + Driving Range for isolated shot testing.
- Shot loop for manual testing: Club select (pick ★ club → Confirm) → Aim (Space / Confirm Aim) → Tempo swing (LMB drag DOWN then UP through the ball on the pad) → dismiss result with Space.
- Godot 4.4+ writes `*.gd.uid` files next to scripts; they are committed. Importing may generate a missing one (e.g. for a script added without its `.uid`) — harmless.

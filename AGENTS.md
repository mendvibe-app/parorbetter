# AGENTS.md — Par or Better

Godot 4 mobile golf prototype. One run = generated 18-hole course, lives, form-driven aim, single-thumb tempo swing (backswing:downswing ratio — the core skill).

Coding philosophy is already enforced: read `.cursor/rules/ponytail.mdc` before changing code. Shortest correct diff; reuse existing helpers; no new deps/abstractions unless asked. Non-trivial logic leaves one lightweight self-check (assert/demo/`*_check.py`).

**Art**: Locked direction in `art/STYLE.md` (**Pixel Kit Golf**) — PixelLab-native kit (tilesets/character/props), not photo-ref clones. Pipeline: `art/prompts/kit.md`. Mood refs optional under `art/references/`. Briefs under `art/prompts/`. Raw → `art/generated/`; finals → `assets/` after wave gate. UI typeface: **Pixel Operator** (CC0) via `assets/ui/game_theme.tres` / `UiScale.FONT`.

## Token Efficiency

- Prefer editing the previous result over re-explaining or defending it.
- When continuing work, carry forward only the last accepted answer or the minimal necessary context. Drop drafts, false starts, and long intermediate reasoning.
- Start a new focused session (or clearly separate the task) when the goal changes or the conversation gets heavy.
- Default to concise outputs. Prefer “code only”, “diff only”, or short answers unless depth is explicitly requested.
- Be selective with file reads and context. Prefer targeted reads/greps over broad exploration once the relevant location is known. Avoid re-reading the same files.
- Batch related questions in one response when possible.
- If a request is ambiguous, ask 1–2 clarifying questions instead of guessing and regenerating.
- Once a result is accepted, treat it as the new baseline.

## Shot loop (end to end)

Orchestrated by `HoleController` + `ShotRoutine`.

1. **Club select** (`ClubSelect`) — Off green: 3 clubs near `BallPhysics.pick_club` (★), **Full bag** for the rest (sand → wedges only). Green skips to putter. Confirm commits. **Driving range** (start screen → Practice Range): same club pick, then skip aim.
2. **Aim** (`HoleController` aim phase + `AimControl`) — Drag bearing; yellow dispersion circle = form radius from `GameState.get_aim_radius_yards`. Confirm Aim / Space locks target. Optional **Practice Swing** grades tempo with no stroke. Range mode skips this (fixed center aim). On green: aim-drag is **start line** (distance locked to cup; short putts soft-snap within `PUTT_LINE_SNAP_*`); pace is the stroke. Short flat putts (`GameState.tap_in_yd` / `tap_in_break`) skip aim and go straight to stroke.
3. **Strike** — Full/pitch/flop/punch: `TempoGesture` + `TempoGrade`; power from pull length (`power_from_amplitude`); `recommended_power` is the pad-tick / aim-preview target, not launch power. Putt/chip: same pad, re-skinned; `PuttStroke` grades **amplitude vs pace marker** (power), **arc path** (line), tempo as miss-explainer. Pure = PERFECT + balance ≥ 0.72.
4. **Result** — Glance panel (`ShotReport.glance_text`: tempo diagnosis for full; distance/line for putt). Full dump stays in F1. Range: ball resets to tee and loops. Course: settle → next shot / hole-out lives via `Scoring`.

## Key gameplay constants

| What | Where |
|------|--------|
| Full-swing tempo target | `TempoGrade.TARGET_FULL` (3.0); tol half-width `TOL_FULL` (1.1 → accept ~1.9–4.1 at full balance; 14-hcp miss model) |
| Chip tempo target | `TempoGrade.TARGET_SHORT` (2.0); `TOL_SHORT` (0.85) |
| Putt stroke (amplitude) | `PuttStroke` absolute log pad (`marker_frac` / `power_from_frac`, `_power_to_u` / `_u_to_power` + `BEND`); soft ticks `SCALE_LABELED_FT` / `SCALE_TICK_FT`; line via `arc_allowance` |
| Putt line aim | Bearing drag, distance locked to cup; `PUTT_LINE_SNAP_DEG` 3° / `PUTT_LINE_SNAP_MAX_FT` 8 (`HoleController`) |
| Putter max | `BallPhysics.PUTTER_MAX_YD` (25.0 → 75 ft); soft scale labels/ticks in `PuttStroke.SCALE_*_FT` |
| Tap-in fast path | `GameState.tap_in_yd` (4.0) + `tap_in_break` (0.01 = 1% grade) |
| Pure balance gate | `TempoGrade.PURE_BALANCE` / `PuttStroke.PURE_BALANCE` / `ShotRoutine.PURE_BALANCE` (0.72) |
| Dispersion circle (full shot) | `GameState.AIM_RADIUS_WEAK_YD/MID/PRO` (40 / 22 / 10 yd); `get_aim_radius_yards()` |
| Dispersion circle (putt) | `GameState.PUTT_RADIUS_WEAK_YD/PRO` (2.7 / 1.0 yd) |
| Form history window | `GameState.FORM_HISTORY_MAX` (8) |
| Cup / ball visual | True-scale: `CUP_RADIUS` / `CUP_CAPTURE_RADIUS` / `BALL_R_PUTT` (0.102 always — whole round); see `plans/putt-true-scale-phase1.md` |
| Putt break | `BallPhysics.green_slope_accel` (`GREEN_GRAVITY_SCALE` 0.45 × g); field mag `0.024–0.071` → 1–3% plane (`GREEN_PLANE_WEIGHT` 0.42, hi = `PIN_MAX / 0.42`); pin shelf `PIN_MAX_LOCAL_SLOPE` 0.03 |
| Pin placement | `HoleGenerator.PIN_EDGE_MARGIN_YD` (5.0 → 15 ft / ~4 paces from edge & greenside trouble); `_pick_pin` zone sample + slope shelf |
| Yards ↔ pixels | `BallPhysics.PX_PER_YARD` (2.25) |
| Air vs roll split | `BallPhysics.AIR_DISTANCE_FRACTION` (0.78) |
| Green slope field | `HoleData.contour_profile` + `green_slope` + `green_height_at` / `green_slope_at`; book wash ±2 ft, arrows from 1% |
| Hazards | `HoleData.hazards` role specs (`greenside` / `landing` / `carry` / `edge` / `island_ring`); placed by `HoleController._place_hazards` |
| Lie timing tighten | `BallPhysics.lie_timing_scale` (scales tempo tolerance width) |
| Lives (Survival) | `GameState.MAX_LIVES/START_LIVES`; deltas via `GameState.apply_hole_result_lives` |
| 18 Hole Round | `GameState.stroke_play_mode` — no lives, always finish 18; net via `HandicapMath` |
| Pure strikes (round) | `GameState.pure_strikes` / `record_pure_strike()` |
| UI type scale | `UiScale.CAPTION/BODY/TITLE` (40 / 48 / 56); celebration ~64–72 in scenes |
| Touch target min | `UiScale.TOUCH_MIN` (120 px on 1080-wide canvas ≈ 44–48pt) |
| Safe-area insets | `UiScale.viewport_safe_margins` / `apply_hole_safe_area` |

## Folder map (`scripts/`)

| Path | Belongs here |
|------|----------------|
| `shot/` | Club select, aim helpers, tempo gesture/grade, shot routine/result, arc meter math (autoload `ArcMeters`) |
| `ball/` | Ball node + launch/lie/physics helpers |
| `course/` | Hole data/resource, generator, hole controller (build + shot UI glue) |
| `systems/` | Scoring, shot report formatting, `HandicapMath` (slope / SI / HCP) |
| `ui/` | HUD, shot result panel, game over, `UiScale` (type/touch/safe-area) |
| `autoload/` | `GameState`, `AudioBus` (ArcMeters lives under `shot/` but is autoloaded) |
| `debug/` | F1 debug panel — metrics, force perfect/mishit, hole jump, balance sliders |

Scenes under `scenes/`; art under `assets/`.

## Autoloads (`project.godot`)

- **GameState** — Run state: lives, hole index, generated course, form + path-miss history, pure-strike count, aim-radius helpers, adaptation bias helpers, debug overrides (incl. tempo tol), tempo guide flags, `range_mode`, run end.
- **AudioBus** — Procedural SFX (`AudioStreamGenerator`): contact, pure (compression transient), putt drop, birdie, splash, UI, tempo `play_tick()`. No asset pack.
- **ArcMeters** (`scripts/shot/arc_meter_math.gd`) — Shared geometry for swing arc meters (angles, polylines, draw helpers). Note: `tempo_*` helpers are the **power-arc** draw API name, not the 3:1 ratio grade.

## Entry

`scenes/main.tscn` → `main.gd` loads hole 1, wires next-hole / game-over / debug.

## Godot AI MCP

Plugin: `addons/godot_ai` (hi-godot/godot-ai). User Grok config: `[mcp_servers."godot-ai"]` via `uvx … godot-ai attach` (ports 8000 / 9500). **When `godot-ai` tools are connected**, prefer them for editor operations (scenes, nodes, scripts, signals, project settings) over hand-editing `.tscn` / wiring by text. Requires the Godot **editor** open on this project with the plugin enabled.

**Do not clone `godot-ai` (or any second copy of the addon) inside this project tree.** Duplicate `class_name Mcp*` scripts poison Godot’s global class cache (`Cannot convert argument … Object to Object`, `hides a global script class`, handlers resolving to `res://_tmp_godot_ai/...`). Install only under `addons/godot_ai`. If that happens: remove the extra tree, fully quit the editor (plugin reload is not enough), reopen the project.

## Cursor Cloud specific instructions

Engine: **Godot 4.7.x** at `/usr/local/bin/godot` (installed by the update script). Matches `project.godot` `config/features` ("4.7"). GDScript only — no C#/Mono build.

- **Tests / "lint":** there is no GDScript linter or CI. The test suite is the Python contract checks (`scripts/**/*_check.py`) — each parses the sibling `.gd` and asserts gameplay constants/logic haven't drifted. Run all: `for f in scripts/*/*_check.py; do python3 "$f" || break; done` (Python 3 is preinstalled). Add one check alongside non-trivial gameplay logic (ponytail rule).
- **Headless sanity check:** `godot --headless --import` (imports assets, generates `.godot/`), then `godot --headless --quit-after 120` runs `main.tscn` for 120 frames and surfaces any GDScript parse/runtime errors. Both exit 0 when clean.
- **Run the game (GUI):** `DISPLAY=:1 godot --path /workspace`. The VM has no GPU/audio, so Godot logs (harmless, expected) `VK_KHR_surface not found` → falls back to OpenGL/`llvmpipe` software rendering, and ALSA errors → dummy audio driver. The game still renders and plays fine. Use start-screen **Practice Range** for isolated shot testing; F1 for metrics/force shots.
- Shot loop for manual testing: Club select (pick ★ club → Confirm) → Aim (Space / Confirm Aim) → Tempo swing (LMB drag DOWN then UP through the ball on the pad) → dismiss result with Space.
- Godot 4.4+ writes `*.gd.uid` files next to scripts; they are committed. Importing may generate a missing one (e.g. for a script added without its `.uid`) — harmless.

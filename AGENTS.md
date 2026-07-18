# AGENTS.md — Par or Better

Godot 4 mobile golf prototype. One run = generated 18-hole course, lives, form-driven aim, dual-phase shot loop (power/stance → swing timing).

Coding philosophy is already enforced: read `.cursor/rules/ponytail.mdc` before changing code. Shortest correct diff; reuse existing helpers; no new deps/abstractions unless asked. Non-trivial logic leaves one lightweight self-check (assert/demo/`*_check.py`).

## Shot loop (end to end)

Orchestrated by `HoleController` + `ShotRoutine`.

1. **Club select** (`ClubSelect`) — Off green: pick from `BallPhysics` bag (sand → wedges only). Green skips to putter. Confirm commits.
2. **Aim** (`HoleController` aim phase + `AimControl`) — Drag bearing; yellow dispersion circle = form radius from `GameState.get_aim_radius_yards`. Confirm Aim / Space locks target.
3. **Power + stance** (`PowerStance`, finger 1) — Vertical = power toward white tick; horizontal tracks gold lean. Outside mash/baby pocket → accuracy tax via `BallPhysics.force_factor`. Release when lock fills.
4. **Swing timing** (`SwingContact`, finger 2) — Arc marker; impact at bottom yellow. Grades `ShotResult.ContactQuality`. Putts: slower/tighter window; green book visible when relevant.
5. **Result** — `ShotRoutine` → `ShotResult` → `BallPhysics.launch_velocity` → `GolfBall` flight/roll → settle/hazard/cup → `ShotReport` + lives/`Scoring` on hole-out.

## Key gameplay constants

| What | Where |
|------|--------|
| Dispersion circle (full shot) | `GameState.AIM_RADIUS_WEAK_YD/MID/PRO` (40 / 22 / 10 yd); `get_aim_radius_yards()` |
| Dispersion circle (putt) | `GameState.PUTT_RADIUS_WEAK_YD/PRO` (2.7 / 1.0 yd) |
| Form history window | `GameState.FORM_HISTORY_MAX` (8) |
| Mash / baby power pocket | `BallPhysics.POWER_POCKET_LO/HI` (0.60 / 0.92); tax via `force_factor()` |
| Cup catch radius | `HoleController.CUP_RADIUS` (7.0 px) |
| Yards ↔ pixels | `BallPhysics.PX_PER_YARD` (2.25) |
| Air vs roll split | `BallPhysics.AIR_DISTANCE_FRACTION` (0.78) |
| Green slope field | `HoleData.green_slope` + `green_height_at` / `green_slope_at` (shared by putt physics + green book) |
| Lie timing tighten | `BallPhysics.lie_timing_scale` |
| Lives | `GameState.MAX_LIVES/START_LIVES`; deltas via `GameState.apply_hole_result_lives` |

## Folder map (`scripts/`)

| Path | Belongs here |
|------|----------------|
| `shot/` | Club select, aim helpers, power/stance, swing contact, shot routine/result, arc meter math (autoload `ArcMeters`) |
| `ball/` | Ball node + launch/lie/physics helpers |
| `course/` | Hole data/resource, generator, hole controller (build + shot UI glue) |
| `systems/` | Scoring, shot report formatting |
| `ui/` | HUD, shot result panel, game over |
| `autoload/` | `GameState`, `AudioBus` (ArcMeters lives under `shot/` but is autoloaded) |
| `debug/` | F1 debug panel — prototype tooling |

Scenes under `scenes/`; art under `assets/`.

## Autoloads (`project.godot`)

- **GameState** — Run state: lives, hole index, generated course, form + path-miss history, aim-radius helpers, adaptation bias helpers, debug overrides, run end.
- **AudioBus** — Procedural SFX (`AudioStreamGenerator`): contact, pure, putt drop, birdie, splash, UI. No asset pack.
- **ArcMeters** (`scripts/shot/arc_meter_math.gd`) — Shared geometry for tempo/swing arc meters (angles, polylines, draw helpers).

## Entry

`scenes/main.tscn` → `main.gd` loads hole 1, wires next-hole / game-over / debug.

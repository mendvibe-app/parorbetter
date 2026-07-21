# AGENTS.md — Par or Better

Godot 4 mobile golf prototype. One run = generated 18-hole course, lives, form-driven aim, concurrent dual-touch shot (power/stance + swing timing resolved together at impact).

Coding philosophy is already enforced: read `.cursor/rules/ponytail.mdc` before changing code. Shortest correct diff; reuse existing helpers; no new deps/abstractions unless asked. Non-trivial logic leaves one lightweight self-check (assert/demo/`*_check.py`).

## Shot loop (end to end)

Orchestrated by `HoleController` + `ShotRoutine`.

1. **Club select** (`ClubSelect`) — Off green: pick from `BallPhysics` bag (sand → wedges only). Green skips to putter. Confirm commits.
2. **Aim** (`HoleController` aim phase + `AimControl`) — Drag bearing; yellow dispersion circle = form radius from `GameState.get_aim_radius_yards`. Confirm Aim / Space locks target.
3. **Concurrent strike** (`PowerStance` + `SwingContact`, one `Phase.ACTIVE`) — Finger 1 holds power (vertical → white tick) and gold lean; finger 2 starts the arc and taps impact at the yellow bottom. Both stay live until the impact tap, which samples **live** power/stability (not frozen earlier). Lifting finger 1 early soft-crushes stability (`EARLY_RELEASE_STAB_MUL` / `CEIL`) but still lets finger 2 finish. Outside mash/baby pocket → `BallPhysics.force_factor` accuracy tax. Putts: slower/tighter window; green book when relevant.
4. **Result** — `ShotRoutine` → `ShotResult` → `BallPhysics.launch_velocity` → `GolfBall` flight/roll → settle/hazard/cup → `ShotReport` + lives/`Scoring` on hole-out. Earned pure (perfect contact + stance ≥ 0.72): compression SFX, haptic pulse, slow-mo/camera punch, brighter trail, round pure counter.

## Key gameplay constants

| What | Where |
|------|--------|
| Dispersion circle (full shot) | `GameState.AIM_RADIUS_WEAK_YD/MID/PRO` (40 / 22 / 10 yd); `get_aim_radius_yards()` |
| Dispersion circle (putt) | `GameState.PUTT_RADIUS_WEAK_YD/PRO` (2.7 / 1.0 yd) |
| Form history window | `GameState.FORM_HISTORY_MAX` (8) |
| Mash / baby power pocket | `BallPhysics.POWER_POCKET_LO/HI` (0.60 / 0.92); tax via `force_factor()` |
| Early-release stability | `PowerStance.EARLY_RELEASE_STAB_MUL` (0.45) / `EARLY_RELEASE_STAB_CEIL` (0.32) — playtest tunable |
| Cup catch radius | `HoleController.CUP_RADIUS` (7.0 px) |
| Yards ↔ pixels | `BallPhysics.PX_PER_YARD` (2.25) |
| Air vs roll split | `BallPhysics.AIR_DISTANCE_FRACTION` (0.78) |
| Green slope field | `HoleData.green_slope` + `green_height_at` / `green_slope_at` (shared by putt physics + green book) |
| Lie timing tighten | `BallPhysics.lie_timing_scale` |
| Lives | `GameState.MAX_LIVES/START_LIVES`; deltas via `GameState.apply_hole_result_lives` |
| Pure strikes (round) | `GameState.pure_strikes` / `record_pure_strike()` |
| UI type scale | `UiScale.CAPTION/BODY/TITLE` (32 / 40 / 48); celebration 56–64 in scenes |
| Touch target min | `UiScale.TOUCH_MIN` (120 px on 1080-wide canvas ≈ 44–48pt) |
| Safe-area insets | `UiScale.viewport_safe_margins` / `apply_hole_safe_area` |

## Folder map (`scripts/`)

| Path | Belongs here |
|------|----------------|
| `shot/` | Club select, aim helpers, power/stance, swing contact, shot routine/result, arc meter math (autoload `ArcMeters`) |
| `ball/` | Ball node + launch/lie/physics helpers |
| `course/` | Hole data/resource, generator, hole controller (build + shot UI glue) |
| `systems/` | Scoring, shot report formatting |
| `ui/` | HUD, shot result panel, game over, `UiScale` (type/touch/safe-area) |
| `autoload/` | `GameState`, `AudioBus` (ArcMeters lives under `shot/` but is autoloaded) |
| `debug/` | F1 debug panel — prototype tooling |

Scenes under `scenes/`; art under `assets/`.

## Autoloads (`project.godot`)

- **GameState** — Run state: lives, hole index, generated course, form + path-miss history, pure-strike count, aim-radius helpers, adaptation bias helpers, debug overrides, run end.
- **AudioBus** — Procedural SFX (`AudioStreamGenerator`): contact, pure (compression transient), putt drop, birdie, splash, UI. No asset pack.
- **ArcMeters** (`scripts/shot/arc_meter_math.gd`) — Shared geometry for tempo/swing arc meters (angles, polylines, draw helpers).

## Entry

`scenes/main.tscn` → `main.gd` loads hole 1, wires next-hole / game-over / debug.

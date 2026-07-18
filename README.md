# Par or Better

Minimal Godot 4 mobile golf prototype — dual-finger shot loop, aim circles, lives, adaptation.

## Requirements

- [Godot 4.3+](https://godotengine.org/) (4.x)

## Run

1. Open this folder in Godot (`project.godot`).
2. Press **F5** (or Play).

## Controls (desktop → simulates dual touch)

### 0) Club (approaches)
- Tap a club (suggested ★), then **Confirm** (short lock so you commit). Sand → wedges only. Green skips this (putter).

### 1) Aim / shape
- Directional **wedge** shows start line + shape; drag changes **bearing only** (yardage comes later).
- Yellow **dispersion circle** size = recent form (~40 yd wild → ~10 yd sharp).
- **Drag** / **arrows** to adjust for wind (see cyan wind banner).
- **Space** or **Confirm Aim**.

### 2) Power + stance (Finger 1)
- Meter starts neutral — drag to the **white tick** (recommended %).
- Landing circle slides to your estimated carry and tightens as you near the tick.
- Mash (over 92%) or baby (under 60%) a club → accuracy tax (take more/less club instead).
- Vertical = power; horizontal **tracks the gold lean notch**.
- Release / Space when the lock meter fills.

### 3) Swing / putt timing (Finger 2)
- **Space / RMB**: start the **swing arc** marker; press again on the **yellow** at the **bottom** (impact).
- Putts use a slower, tighter window; green book shows slope during aim.

### After each shot
- Shot Result stays until **click / Space / Enter**.

| Extra | Key |
|--------|-----|
| Debug | **F1** |
| Force perfect | Debug → Force Perfect |

## Lives

Birdie+ = +1 · Par = hold · Bogey = −1 · Double+ = −2 · 0 = game over

## Project

See `scripts/shot/` (dual-finger), `scripts/ball/` (flight), `scripts/course/` (layouts).

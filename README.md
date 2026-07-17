# Par or Better

Minimal Godot 4 mobile golf prototype — dual-finger shot loop, aim circles, lives, adaptation.

## Requirements

- [Godot 4.3+](https://godotengine.org/) (4.x)

## Run

1. Open this folder in Godot (`project.godot`).
2. Press **F5** (or Play).

## Controls (desktop → simulates dual touch)

### 0) Aim
- Yellow **landing circle** starts toward the hole.
- Size = recent form (~40 yd wild → ~10 yd sharp).
- **Drag** / **arrows** to adjust for wind (see cyan wind banner + arrow).
- **Space** or **Confirm Aim**.

### 1) Power + stance (Finger 1)
- **Hold LMB** on the **tempo arc**: vertical = power fill along the club path; horizontal **tracks the gold lean notch**.
- Stability comes from continuous tracking (not a one-time center).
- **←/→** also track; ↑↓ change power but don’t grant free perfect stance.
- Release / Space when the lock meter fills.

### 2) Swing / putt timing (Finger 2)
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

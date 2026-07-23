# Par or Better

Minimal Godot 4 mobile golf prototype — tempo-ratio swing, aim circles, lives, adaptation.

## Requirements

- [Godot 4.3+](https://godotengine.org/) (4.x)

## Run

1. Open this folder in Godot (`project.godot`).
2. Press **F5** (or Play).

## Controls

### 0) Club (approaches)
- Tap one of 3 suggested clubs (★), or **Full bag** for the rest; then **Confirm**. Sand → wedges only. Green skips this (putter).

### 1) Aim / shape
- Directional **wedge** shows start line + shape; drag changes **bearing only**.
- Yellow **dispersion circle** size = recent form (~40 yd wild → ~10 yd sharp).
- **Drag** / **arrows** to adjust for wind (see cyan wind banner).
- **Practice Swing** (optional) — full tempo gesture + readout, no stroke.
- **Space** or **Confirm Aim**.

### 2) Tempo swing (one thumb)
- Power is **committed** at aim confirm (recommended % for club/distance). The gesture cannot add distance — only tempo quality can subtract.
- **Drag back** (takeaway) → slight pause at the **top** → **drag through** impact.
- Graded on **tempo ratio** (full ~3:1, chip/putt ~2:1), not how fast you swipe. Fast ≠ good.
- Balance is read from the gesture (spikes, jerks, stubby backswing) and tightens the window — not a second meter.
- Desktop: **LMB drag** on the swing pad.

### After each shot
- Shot Result shows tempo line (e.g. `Tempo 2.4:1 — transition rushed`) until **click / Space / Enter**.

| Extra | Key |
|--------|-----|
| Debug | **F1** |
| Force perfect | Debug → Force Perfect |
| Tempo tol / bal / release=impact | Debug sliders |

## Lives

Birdie+ = +1 · Par = hold · Bogey = −1 · Double+ = −2 · 0 = game over

## Project

See `scripts/shot/` (tempo gesture + grade), `scripts/ball/` (flight), `scripts/course/` (layouts).

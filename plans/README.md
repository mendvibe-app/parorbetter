# Plans — board

**Status: putting rework is the open track.** Pickup:
`HANDOFF-putting-true-scale.md`. Execute panel restored to 900 (`putt-panel-restore-900.md`).

**New track:** flop at chip distances — `flop-short-dial-phase1.md`
(code). Flop joins chip’s `PuttStroke` pad; flight stays flop; `FLOP_MAX_YD` 30 is a ceiling not a floor.

**New track:** chip distance vs real golf — `chip-distance-real-golf.md`
(Phase 1+2 code). Pad smash (log map) then roll skate (lie-change speed).

**New track:** green slope align — `green-slope-align-roadmap.md` / `green-slope-align-phase1.md`.
Field is 1–3% grade; putt and on-green short-game roll share `green_slope_accel`.

Shipped epic/correction specs live in [`archive/`](archive/).

---

## Living roadmaps (reference only)

| Doc | Status |
|-----|--------|
| `putting-rework-roadmap.md` | **ACTIVE** — Phases 0–3 shipped; Phase 4 640 reverted |
| `green-slope-align-roadmap.md` | **SHIPPED** — Phases 1–3 (device playtest skipped) |
| `flight-model-rebuild-roadmap.md` | COMPLETE (code) — Phases 0–7; pacing superseded by epic-real-time-pacing |
| `swing-input-rework-roadmap.md` | COMPLETE (code) — Phases 0–6 |
| `design-effort-based-swing.md` | Design companion (not an open epic) |
| `Golf_Ball_Speed_Physics_Research.pdf` | Authority for peak-at-face + air speed envelope (shipped) |

---

## Shipped this stack (2026-08-15)

Order was intentional — do not retune putt pace before green sizing next time.

| Epic / correction | What landed |
|-------------------|-------------|
| `correction-rough-base-layer` | P0 pad split + P1 invert paint (`FIRST_CUT_W=14`, dark base → light first cut → fairway) |
| `epic-real-time-pacing` | Phase 1 flight (`FLIGHT_DURATION_FRAC=0.65`) → Phase 2 roll → Phase 3 putt; wind force ∝ √(g/535) |
| `epic-distance-driven-green-sizing` | Approach-driven radii, area floor/ceil, deeper-than-wide aspects |
| Club Coach history | `SCHEMA_VERSION` **3** (after greens — GIR rates shift) |

---

## Active

| Doc | Status |
|-----|--------|
| `HANDOFF-putting-true-scale.md` | Pickup — where we left off 2026-08-27 |
| `putting-rework-roadmap.md` | ACTIVE — line / contact / read-execute camera |
| `putting-phase0-line-interaction.md` | SHIPPED — line aim is default (signed off 2026-08-27) |
| `putting-phase1-contact.md` | SHIPPED — playtest 2026-08-27 |
| `putting-phase3-read-camera.md` | SHIPPED — book zoom + flag during aim |
| `putting-phase4-execute-camera.md` | REVERTED — 640 failed pace; 900 restored (`putt-panel-restore-900.md`) |
| `putt-panel-restore-900.md` | SHIPPED — one 900 panel for all shot types |
| `recon_putt_pad_height.md` | SHIPPED — 640 compressed pace; 900 still fits ball→cup |
| `putt-true-scale-phase1.md` | SHIPPED — true-scale ball/cup/capture |
| `putt-true-scale-phase2.md` | SHIPPED — putt camera framing (mins/cap still playtest knobs) |
| `lip-in-drop-variation-phase1.md` | SHIPPED — pour vs toilet-bowl (unit bug 2026-08-27) |
| `lip-out-leave-phase1.md` | CODE COMPLETE — ft-grounded leave + geometry-weighted luck |
| `short-game-wind-offline-phase1.md` | SHIPPED (`64c76f7`) — wind exposure + path drift |
| `short-game-landing-circle-phase1.md` | SHIPPED (`5703bb3`) — chip/pitch/flop aim circle by rest yards |
| `cup-lip-out-phase2.md` | SHIPPED (`0038400`) — horseshoe on hot rejects; make rate frozen |
| `green-slope-align-roadmap.md` | SHIPPED — 1–3% field, shared gravity, book ±2 ft, mag×t |
| `green-slope-align-phase1.md` | SHIPPED — literals (playtest skipped) |
| `short-game-follow-camera-phase1.md` | SHIPPED (`8af1a7e` / `#56`) — remaining-fit + roll tracer |
| `chip-distance-real-golf.md` | CODE COMPLETE — pad linear, lie-change remain, chip PERFECT 1.0 |
| `flop-short-dial-phase1.md` | CODE COMPLETE — flop joins chip pad; 30 yd ceiling only; picker-only |

---

## Deferred (no active ticket)

Not on the board until you re-open:

- Bag calibration **Part B** (unapproved bag rescale)
- Unplayable lie / drop (no epic written)
- Putt aim curve (TV leftovers item 1a) — see archive
- Swipe-sign convention QA — see archive
- Haptics device smoke — see archive
- Camera easing if 3× hang feels sticky (pacing epic risk — playtest first)

---

## Archive

`plans/archive/` holds closed phase epics, shipped corrections, and deferred playtest
docs. **`correction-tv-broadcast-feel` item 3 (keep GRAVITY_PX=535) is superseded** by
`epic-real-time-pacing` — do not follow the old hold.

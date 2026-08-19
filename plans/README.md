# Plans — board

**Status: clean for free play.** Stack shipped 2026-08-15 (rough + real-time pacing +
distance-driven greens + Club Coach schema 3). Playtest the whole stack; reopen with a
new correction if something fails on device.

Shipped epic/correction specs live in [`archive/`](archive/).

---

## Living roadmaps (reference only)

| Doc | Status |
|-----|--------|
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
| `cup-lip-out-phase2.md` | IMPLEMENTING — horseshoe on hot rejects only; make rate frozen |

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

# Plans — active backlog

Shipped epic/correction specs live in [`archive/`](archive/). Living roadmaps and
**open** work stay here.

---

## Next numbered phases

| Track | Next | Spec |
|-------|------|------|
| Flight model rebuild | **Phase 7** — feel pass + Club Coach history reset | `flight-model-rebuild-roadmap.md` |
| Swing input rework | **Phase 6** — feel pass (amplitude sensitivity, overswing curve) | `swing-input-rework-roadmap.md` |
| Design companion | Settled mechanic for swing track (not an epic) | `design-effort-based-swing.md` |

Flight phases 0–6 and swing phases 0–5 are **shipped** (see roadmaps + `archive/`).

---

## Open corrections / QA

| Plan | Status |
|------|--------|
| `correction-swipe-sign-convention.md` | **OPEN QA** — playtest swipe sign vs real draw/fade |
| `epic-contact-quality-haptics.md` | Code shipped; **Android/iOS device smoke** still open |
| `correction-approach-zoom.md` | Not implemented — short approach camera too wide |
| `correction-club-select-tip-priority.md` | Not implemented — tempo tip dominates club icons |
| `correction-tv-broadcast-feel.md` | Not implemented — putt zoom / hole-out / pacing (3 items) |
| `correction-putt-stale-flight-metrics.md` | Code on `fix/putt-stale-flight-metrics` — **merge when verified** |
| `correction-recommended-power-wind.md` | Partial: `recommended_power` shipped; **aim/commit path** still world-Y wind |

---

## Deferred / unplanned (no active plan file)

- **Bag calibration Part B** — unapproved bag rescale (note on flight roadmap)
- **`feature/short-game-practice`** — branch only, not on main
- **`feature/menu-abandon-run`** — branch only, not on main
- **Unplayable lie / drop** — mentioned historically; no epic written

---

## Archive

`plans/archive/` holds closed phase epics and shipped corrections. Prefer the
roadmap “Shipped” / “Corrections” sections for status; open the archive only when
you need the original build notes.

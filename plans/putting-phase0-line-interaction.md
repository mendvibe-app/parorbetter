# Putting Phase 0 — Line interaction spec (draft)

**Status:** PROTOTYPE IN BUILD — awaiting Matt device sign-off  
**Roadmap:** `plans/putting-rework-roadmap.md`  
**Flag:** F1 → **Putt line aim (Phase 0)** → `GameState.debug_putt_line_aim`

---

## Locked choice

**Candidate A:** Bearing drag, **distance locked to cup**.  
Pace stays on the putt stroke. Line = start direction only.

---

## How to playtest

1. F1 → enable **Putt line aim (Phase 0)**.  
2. Practice green or on-course putt.  
3. **Short (~3–6 ft):** drag slightly — should soft-snap to cup within ~3°.  
4. **Long (~35–45 ft):** drag left/right of cup — aim line holds cup distance; label shows L/R offset.  
5. Confirm Aim → stroke as usual (power still from alley).

**Off (default):** today’s free-point putt aim (drag distance ≈ pace preview).

---

## PLAYTEST TARGETS (prototype)

| Knob | Value | Where |
|------|--------|--------|
| Soft-snap angle | 3° | `PUTT_LINE_SNAP_DEG` |
| Soft-snap max length | 8 ft | `PUTT_LINE_SNAP_MAX_FT` |
| Lock yards | ball→cup | `_apply_aim_world` when flag on |

---

## Sign-off (Matt)

- [ ] Short putt: snap feels fair, not sticky/annoying  
- [ ] Long putt: easy to set a break line without changing intended pace via aim  
- [ ] Ready for Phase 1 (contact) and/or Phase 2 (promote flag → default)

**Signed:** _______________ **Date:** _______________

---

## Next

- Phase 1: `contact_mul` on green (independent)  
- Phase 2: make line aim default; remove flag; mishit threatens line  
- Phases 3–4: read/execute camera (blocked until Phase 2 stable)

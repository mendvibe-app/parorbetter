# Putting Phase 0 — Line interaction spec

**Status:** SHIPPED as default — device sign-off 2026-08-27  
**Roadmap:** `plans/putting-rework-roadmap.md`

---

## Locked choice

**Candidate A:** Bearing drag, **distance locked to cup**.  
Pace stays on the putt stroke. Line = start direction only.

---

## PLAYTEST TARGETS

| Knob | Value | Where |
|------|--------|--------|
| Soft-snap angle | 3° | `PUTT_LINE_SNAP_DEG` |
| Soft-snap max length | 8 ft | `PUTT_LINE_SNAP_MAX_FT` |
| Lock yards | ball→cup | `_apply_aim_world` (always) |

---

## Sign-off (Matt)

- [x] Short putt: snap feels fair, not sticky/annoying
- [x] Long putt: easy to set a break line without changing intended pace via aim
- [x] Ready for Phase 1 (contact) and Phase 2 promote → default

**Signed:** Matt **Date:** 2026-08-27

---

## Next

- Phase 1: `contact_mul` on green (putt-only curve)
- Phase 2 leftover: mishit threatens line even when path is clean
- Phases 3–4: read/execute camera (blocked until Phase 1 playtest)

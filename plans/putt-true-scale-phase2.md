# Epic — Putting true-scale Phase 2 (camera / zoom)

**Status:** Implemented with playtest targets — tune mins/cap on device.  
**Depends on:** Phase 1 geometry (`plans/putt-true-scale-phase1.md`) — world ball/cup/capture unchanged.  
**Scope:** Putt camera framing + pinch abs max only.

---

## Problem

Phase 1 made absolute scale correct (“30 ft looks like 30 ft to a golf hole”) but at `PUTT_ZOOM_CAP := 24` and `half_span` floor `12`, ball/cup rendered at a few screen pixels — unplayable to aim or judge makes.

Raising the cap alone does **not** fix short putts: `half_span := max(dist*0.90+6, 12)` caps zoom at ~47 regardless of `PUTT_ZOOM_CAP`. Pinch was also capped at `PINCH_ABS_ZOOM_MAX := 8`.

---

## Solution

1. **Retune distance framing** — lower span floor/pad, raise view frac + `PUTT_ZOOM_CAP` (130).
2. **Soft object-size floor** — short/mid putts blend toward min on-screen ball/cup; long lags prefer full-line fit.
3. **Raise `PINCH_ABS_ZOOM_MAX`** to match putt cap.
4. **Keep roll camera lock** — no live tighten-to-cup punch.

Constants live on `HoleController` as `PLAYTEST TARGET`s (`PUTT_MIN_*_SCREEN_PX`, span coeff, cap).

---

## Follow-up (shipped): pace + lip orbit

After Phase 2 zoom, putt **screen** speed felt fast and lip horseshoes still used pre-scale `LIP_ORBIT_MAX` (1.55). Fix: `PUTT_PACE_SCALE` (v×k, a×k²) + true-scale rim orbit (~0.175). See session plan / `ball.gd` / `ball_physics.gd`.

## Out of scope

World `BALL_R_PUTT` / `CUP_RADIUS` / `CUP_CAPTURE_RADIUS` (Phase 1), non-putt zoom, art regen.

---

## Verify

```bash
python scripts/course/putt_camera_zoom_check.py
```

Playtest: short readable → ~30 ft still “real lag” but playable → long lag zooms out → pinch works.

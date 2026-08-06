# Debug Instrumentation: Verify Transition Timing Detection Lag

## What we're checking
Matt's playtest feedback: he can't get a "solid transition" consistently, across every club.

Working theory: the game doesn't grade you for lacking a pause at the top — that check
is real but too small to ever be the reported reason. What's actually flagging shots is
a straight stopwatch comparison of downswing time vs. a fixed guide time
(`down_ms` vs `guide_down_ms`, ±22% band). The top of your swing is only detected once
your on-screen speed has already dropped, which means part of the real downswing motion
gets counted as still-backswing — shrinking the measured `down_ms` and making swings read
as "rushed" even when they weren't. Because the detection method is the same for every
club, this would show up everywhere, not just on one club — matching what Matt's seeing.

**This doc does not fix anything.** It just puts the actual vs. expected numbers on
screen so we can confirm the skew is real (and see how big it is) before touching the
detection algorithm.

## Out of scope
- No changes to `_update()` top-detection logic in `tempo_gesture.gd`
- No changes to `PACE_TOL_FRAC`, contact grading, or `power_mul`
- No changes to what the player sees in the post-shot panel
- Purely additive: new fields on the debug HUD only

## Changes

### 1. `scripts/shot/tempo_grade.gd` — expose guide + transition numbers in `grade()`

The guide times (`g_back`, `g_down`) and the raw `vel_at_top` / `peak_vel` are already
computed or available inside `grade()`, they just aren't returned. Add them to the
output dictionary.

**File:** `scripts/shot/tempo_grade.gd`
**Function:** `grade()` — the return block currently starting at line 273

Before:
```gdscript
	return {
		"ratio": r,
		"target": target,
		"balance": bal,
		"tolerance": tol,
		"contact": contact,
		"power_mul": power_mul,
		"path_error": path,
		"note": note,
		"fault": str(diag.get("fault", "")),
		"diagnosis": str(diag.get("line", "")),
		"backswing_ms": back_ms,
		"downswing_ms": down_ms,
		"backswing_read": back_read,
		"downswing_read": down_read,
		"back_line": str(copy.get("back_line", "")),
		"down_line": str(copy.get("down_line", "")),
		"headline": str(copy.get("headline", "")),
		"max_accel": float(sample.get("max_accel", 0.0)),
		"max_jerk": float(sample.get("max_jerk", 0.0)),
	}
```

After (added fields only — everything else unchanged):
```gdscript
	var vel_at_top := float(sample.get("vel_at_top", 0.0))
	var peak_vel := float(sample.get("peak_vel", 0.0))
	var down_delta_pct := (
		(float(down_ms) - g_down) / maxf(g_down, 1.0) * 100.0 if g_down > 0.0 else 0.0
	)
	return {
		"ratio": r,
		"target": target,
		"balance": bal,
		"tolerance": tol,
		"contact": contact,
		"power_mul": power_mul,
		"path_error": path,
		"note": note,
		"fault": str(diag.get("fault", "")),
		"diagnosis": str(diag.get("line", "")),
		"backswing_ms": back_ms,
		"downswing_ms": down_ms,
		"backswing_read": back_read,
		"downswing_read": down_read,
		"back_line": str(copy.get("back_line", "")),
		"down_line": str(copy.get("down_line", "")),
		"headline": str(copy.get("headline", "")),
		"max_accel": float(sample.get("max_accel", 0.0)),
		"max_jerk": float(sample.get("max_jerk", 0.0)),
		# --- debug-only, added to verify transition detection lag (not used in grading) ---
		"guide_back_ms": int(g_back),
		"guide_down_ms": int(g_down),
		"down_delta_pct": down_delta_pct,
		"transition_ratio": vel_at_top / maxf(peak_vel, 0.001),
	}
```
`g_back` and `g_down` are already local variables in `grade()` (lines 257–258) — no new
computation needed, just carrying them into the return dict.

### 2. `scripts/debug/debug_controls.gd` — show the comparison on the HUD

**File:** `scripts/debug/debug_controls.gd`
**Function:** `_process()` — the full-swing tempo line, currently around line 140

Before:
```gdscript
		else:
			var tgt := float(t.get("target", 3.0))
			var accel_hint := "clean<14" if tgt < 2.5 else "clean<8"
			tempo_line = "Tempo %.1f:1 (tgt %.0f)  bal %d%%  %d/%dms%s\naccel %.1f (%s)  jerk %.2f\n%s" % [
				float(t.get("ratio", 0.0)),
				tgt,
				int(float(t.get("balance", 0.0)) * 100.0),
				int(t.get("backswing_ms", 0)),
				int(t.get("downswing_ms", 0)),
				type_bit,
				float(t.get("max_accel", 0.0)),
				accel_hint,
				float(t.get("max_jerk", 0.0)),
				str(t.get("note", "")),
			]
```

After:
```gdscript
		else:
			var tgt := float(t.get("target", 3.0))
			var accel_hint := "clean<14" if tgt < 2.5 else "clean<8"
			tempo_line = "Tempo %.1f:1 (tgt %.0f)  bal %d%%  %d/%dms (guide %d/%dms, Δ%+.0f%%)%s\naccel %.1f (%s)  jerk %.2f  transV %.2f\n%s" % [
				float(t.get("ratio", 0.0)),
				tgt,
				int(float(t.get("balance", 0.0)) * 100.0),
				int(t.get("backswing_ms", 0)),
				int(t.get("downswing_ms", 0)),
				int(t.get("guide_back_ms", 0)),
				int(t.get("guide_down_ms", 0)),
				float(t.get("down_delta_pct", 0.0)),
				type_bit,
				float(t.get("max_accel", 0.0)),
				accel_hint,
				float(t.get("max_jerk", 0.0)),
				float(t.get("transition_ratio", 0.0)),
				str(t.get("note", "")),
			]
```

`Δ%` is your actual downswing time vs. the guide, as a percent — negative means faster
(shorter) than expected, which is the "rushed" direction. `transV` is `vel_at_top /
peak_vel` — near 0 means your speed had genuinely died off at the top; higher means it
hadn't.

## Playtest order
1. Practice Mode, 5-iron, 10 reps. Swing at a normal, comfortable pace — don't try to
   "beat" the number.
2. Note the `Δ%` reading each rep. Write down whether it clusters negative (consistently
   reading fast) or scatters both directions (would suggest real inconsistency, not a
   detection bug).
3. Repeat with Driver and a wedge — 10 reps each. Same club-scaling exists on the guide
   time (`club_guide_duration_scale`), so if the skew shows up on all three, that
   confirms it's not driver-specific.
4. If `Δ%` clusters consistently negative (say, average worse than -15%) across all
   three clubs even on swings that felt clean, that's the confirmation: downswing is
   being measured short because the top is being marked late, not because you're
   actually rushing.

## What happens after verification
If the pattern confirms: the fix is almost certainly loosening or backdating how `t_top`
is marked (so the timer starts closer to your real physical reversal) rather than
widening `PACE_TOL_FRAC` — widening the tolerance would just mask the mismeasurement
instead of fixing it. I'll spec that as a separate epic once we have the numbers.

## Acceptance criteria
- Debug HUD full-swing tempo line shows guide back/down ms and `Δ%` alongside actual.
- No change to `contact`, `power_mul`, `path_error`, or any player-facing copy/values.
- New dict fields are additive only — nothing existing removed or renamed.

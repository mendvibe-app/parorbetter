# Epic: Fix Transition Detection Lag (Late "Top of Swing" Marking)

## Confirmed by playtest data
Real debug-HUD readings from a live session:

| Shot | back/down ms | guide back/down | Δ% | transV | max_accel (clean<8) |
|---|---|---|---|---|---|
| Driver | 681/216 | 795/265 | -18% | 0.46 | 130.9 |
| Driver | 756/244 | 795/265 | -8% | 0.42 | 234.3 |
| Iron, fairway | 652/216 | 750/250 | -14% | 0.30 | 134.2 |
| Driver | 650/185 | 795/265 | -30% | 0.52 | 200.8 |

Two things line up on every single shot:
1. **Δ% is always negative** — measured downswing time always comes in short of the
   guide, never long, never scattered. That's a systematic bias, not swing variance.
2. **`max_accel` blows through the "clean<8" reference on every shot**, by 15–30x. That's
   not a wide-tolerance situation — it means the "cast" penalty in the balance score is
   maxed out on effectively every swing, clean ones included, which explains the 12–29%
   balance readings on shots the game itself calls "GOOD" contact and "Clean."

## Root cause — one bug, two symptoms
`tempo_gesture.gd` only calls "the top" once your on-screen speed has visibly dropped
(`_update()`, ~line 670–679). But the position signal driving that speed reading is
smoothed first (`EMA_ALPHA = 0.35`, line 592), so the *measured* speed lags your *real*
speed by a few frames. By the time the code is confident enough to say "that's the top,"
your real downswing already started a few frames earlier.

That lag causes both symptoms from the same root:
- Those "already downswing but still counted as backswing" frames get subtracted from
  `down_ms` → **shrinks measured downswing time → reads as rushed** (symptom 1).
- The code already knows a real direction-reversal produces an unavoidable, meaningless
  acceleration spike, and deliberately excludes *that one frame* from `_max_accel`
  (line 685–689, comment: *"guaranteed to show a sharp accel/jerk value... fold both
  into running max everywhere EXCEPT that one frame"*). But because "that one frame" is
  detected late, the **real** spike frame(s) — the ones the exclusion was built to
  protect against — happen *before* the flagged frame and never get excluded
  (symptom 2).

Same lag, two broken numbers. One fix should move both.

## The fix
We already track the exact frame displacement peaks (`_peak_disp`, line 132,
updated at line 648–650) every frame — that's the best available proxy for the *true*
physical top, and it's available immediately with no new signal processing. We just
never captured *when* that happened.

**Phase 1 (this epic): backdate `_t_top` to the peak-displacement frame, and widen the
accel/jerk exclusion window to match.** Both are additive/reassignment changes to
existing tracked state — no new detection algorithm.

### 1. Track the timestamp of peak displacement

**File:** `scripts/shot/tempo_gesture.gd`

Add the new state var next to `_peak_disp` (line 132):
```gdscript
var _peak_disp: float = 0.0
var _t_peak_disp: float = 0.0
```

Reset it alongside `_peak_disp` in `reset()` (line 343):
```gdscript
	_peak_disp = 0.0
	_t_peak_disp = 0.0
```

Capture it every frame displacement makes a new high, in `_update()` (line 648–650):

Before:
```gdscript
	if _disp >= _peak_disp:
		_peak_disp = _disp
		peak_pos = _smoothed
```
After:
```gdscript
	if _disp >= _peak_disp:
		_peak_disp = _disp
		peak_pos = _smoothed
		_t_peak_disp = now
```

### 2. Use that timestamp instead of the confirmation-frame timestamp

**File:** `scripts/shot/tempo_gesture.gd`, `_update()`, line ~670–679

Before:
```gdscript
	if not had_top and _peak_disp >= min_bs:
		var reversing := _prev_vel > vel_eps and _vel <= vel_eps * 0.25
		var peaked := _disp < _peak_disp - _deadzone() * 0.15 and _vel < 0.0
		if reversing or peaked:
			had_top = true
			_vel_at_top = absf(_vel)
			_t_top = now
			_top_flash_until = Time.get_ticks_msec() + 320
			moment.emit("top")
			live_changed.emit()
```
After:
```gdscript
	if not had_top and _peak_disp >= min_bs:
		var reversing := _prev_vel > vel_eps and _vel <= vel_eps * 0.25
		var peaked := _disp < _peak_disp - _deadzone() * 0.15 and _vel < 0.0
		if reversing or peaked:
			had_top = true
			_vel_at_top = absf(_vel)
			# Backdate to when displacement actually peaked, not the (later) frame
			# where we became confident enough to call it — recovers the downswing
			# time that was being silently donated to the backswing side.
			_t_top = _t_peak_disp if _t_peak_disp > 0.0 else now
			_top_flash_until = Time.get_ticks_msec() + 320
			moment.emit("top")
			live_changed.emit()
```
`_vel_at_top` is left as-is for this phase (see Out of Scope) — it still reads velocity
at the confirmation frame, not the backdated one. It only feeds a capped, minor balance
penalty today, not the loud "rushed" copy, so it's lower priority than the two symptoms
above.

### 3. Widen the accel/jerk exclusion to cover the whole lag window, not one frame

**File:** `scripts/shot/tempo_gesture.gd`, `_update()`, line ~681–689

Right now only the single confirmation frame is excluded. With the backdate above, we
know the true top happened earlier — so any frame between "displacement started
retreating from its peak" and "top officially confirmed" is *also* part of the same
unavoidable-spike window and should be excluded the same way.

Before:
```gdscript
	# The frame where velocity actually reverses direction is guaranteed to show
	# a sharp accel/jerk value regardless of swing quality — that's just what a
	# reversal is. Fold both into the running max everywhere EXCEPT that one
	# frame, so a controlled pause at the top doesn't register as a violent spike.
	var is_top_frame := not was_had_top and had_top
	if not is_top_frame:
		_max_accel = maxf(_max_accel, accel_n)
		if have_jerk:
			_max_jerk = maxf(_max_jerk, jerk_ang)
```
After:
```gdscript
	# The frame where velocity actually reverses direction is guaranteed to show
	# a sharp accel/jerk value regardless of swing quality — that's just what a
	# reversal is. Detection lags the real reversal by a few frames (see _t_top
	# backdating above), so exclude the whole pending-top window — from the moment
	# displacement starts retreating from its peak until top is officially
	# confirmed — not just the single confirmation frame. A controlled pause at
	# the top must not register as a violent spike.
	var is_top_frame := not was_had_top and had_top
	var pending_top := not had_top and _disp < _peak_disp - _deadzone() * 0.05
	if not is_top_frame and not pending_top:
		_max_accel = maxf(_max_accel, accel_n)
		if have_jerk:
			_max_jerk = maxf(_max_jerk, jerk_ang)
```

## Out of scope (this epic)
- `_vel_at_top` accuracy / `transition_ratio` — still measured at the confirmation
  frame rather than the true top. Would need a short rolling buffer of recent velocity
  samples to backdate properly. Today this feeds a capped ≤15%-weight penalty that
  isn't the reported "rushed" fault line, so it's lower priority — flag as a possible
  Phase 2 if the debug numbers still look off after this lands.
- `PACE_TOL_FRAC` (the ±22% guide band) — not touching this. If Δ% clusters near 0
  after this fix, the band was fine all along and the bug was purely measurement.
  Only revisit width if Δ% is still consistently skewed after this change.
- Balance penalty weights (`accel_lo`, `accel_span`, `trans_w`, etc.) — not touching.
  If `max_accel` readings drop into a sane range post-fix, no retuning should be needed.
- Guide time constants (`GUIDE_BACK_FULL`, `club_guide_duration_scale`) — not touching;
  these looked correct against real Tour Tempo references, the bug was measurement.

## Playtest order
1. **Driver first** (largest observed skew: -30% on one sample). Practice Mode, 10 reps
   at a normal, comfortable pace. Check the debug HUD `Δ%` and `transV` — expect them
   to land close to 0 and near-zero respectively on clean-feeling swings, not the
   -18%/-30% and 0.4+ we saw before.
2. **A mid iron** (7I or similar) — confirm the smaller skew also tightens up.
3. **A wedge** — same check.
4. Watch `max_accel` on the debug HUD across all three — should drop from the 130–234
   range down toward something under or near the `clean<8`/`clean<14` reference the
   panel already prints, on swings that feel clean.
5. Only after driver + iron + wedge all look right: play a few holes normally and see if
   balance scores and "rushed transition" copy start matching how the swing actually felt.

## Acceptance criteria
- On a clean-feeling full swing, debug HUD `Δ%` lands within roughly ±10% (down from
  the -8% to -30% range observed pre-fix), consistently across clubs.
- `max_accel` on clean swings drops to a range consistent with the panel's own
  `clean<8` / `clean<14` hint, instead of 15–30x over it.
- No change to `contact`, `power_mul`, `path_error`, guide time constants, or balance
  penalty weights — this epic only changes *when* the top is marked and which frames
  count toward the accel/jerk max, not the grading math itself.
- Club Coach's per-club `tempo avg` and `resolved tip` should trend away from
  `rushed_transition` / "(rushed)" bias over the next ~50 shots per club, without any
  change to actual swing behavior.

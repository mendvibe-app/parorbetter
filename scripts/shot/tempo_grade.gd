class_name TempoGrade
extends RefCounted

## Pure tempo math — backswing:downswing ratio vs target, balance as window modifier.
## Speed-invariant: only the ratio of the two intervals is graded.
## Putts use PuttStroke (amplitude + path), not this ratio model.

const TARGET_FULL := 3.0
const TARGET_SHORT := 2.0
## Half-width of accept window at full balance (full: ~1.9–4.1 with 1.1 — 14-hcp playable).
const TOL_FULL := 1.1
## Pitch/putt ratio window — short pad path makes through easy to over-speed (was 0.85;
## playtest: ghost match still MISS Path+1 from ~4–6:1 blasts). Wider = mobile-playable 2:1.
const TOL_SHORT := 1.35
const PURE_BALANCE := 0.72
## Below this aim distance → pitch tempo (2:1); at/above → full (3:1).
const PITCH_YD := 50.0
## Cap pitch-gate as a fraction of club max so short clubs (Gap) aren't forced
## onto 2:1 while still swinging a near-stock % — same pad feel as longer clubs.
const PITCH_POWER_CAP := 0.42
## Below this aim distance → chip (amplitude-graded via PuttStroke, not tempo
## ratio). Flat gate, independent of club — real short-game stats split
## "inside 20" from "20-40," not by club. Tuning default, not a final number:
## a future pass could calibrate this per the player's actual wedge carry
## data instead of a hardcoded flat yardage.
const CHIP_YD := 20.0

## Contact tiers by |ratio − target| / tolerance (after balance × timing scale).
## Slightly off stays GOOD; thin/fat only when clearly wrong; MISS = disaster.
const BAND_PERFECT := 0.50
const BAND_GOOD := 1.15
const BAND_THIN_FAT := 1.85
## Absolute pace vs ghost guide (display only — does not change contact grade).
const PACE_TOL_FRAC := 0.22
## Cast / max_accel bands (pad-normalized). Shared with F1 hint + trail color.
## Calibrated after frame-cap + post-top mute (playtest clean sat at 48 under old 8/24).
const ACCEL_LO_FULL := 28.0
const ACCEL_SPAN_FULL := 40.0
const ACCEL_LO_PITCH := 32.0
const ACCEL_SPAN_PITCH := 40.0
## Rushed tempo past GOOD band → outside-in nudge on swipe (not independent path).
const TRANSITION_PULL_MAX_FULL := 0.20
const TRANSITION_PULL_MAX_PITCH := 0.12
const TRANSITION_PULL_SCALE := 0.35  ## scales abs_n past BAND_GOOD; hard-cap pull_max
## Random direction jitter when balance < 0.35 (shot_routine).
const BALANCE_DISPERSION_MAX := 0.15


static func shot_type_for(lie: String, remaining_yd: float, club_max_yards: float = 0.0) -> String:
	if lie == "Green":
		return "putt"
	if remaining_yd < CHIP_YD:
		return "chip"
	var gate := PITCH_YD
	if club_max_yards > 1.0:
		gate = minf(PITCH_YD, club_max_yards * PITCH_POWER_CAP)
	if remaining_yd < gate:
		return "pitch"
	return "full"


static func target_ratio(shot_type: String) -> float:
	# Punch uses full 3:1; only putt/pitch are short-game tempo.
	return TARGET_SHORT if shot_type == "putt" or shot_type == "pitch" else TARGET_FULL


static func base_tolerance(shot_type: String) -> float:
	return TOL_SHORT if shot_type == "putt" or shot_type == "pitch" else TOL_FULL


## Minimum backswing/follow-through length (fraction of pad size.y) to avoid the
## balance() short-swing penalty. Single source of truth — grading and the pad's
## drawn floor markers (tempo_gesture.gd) both read from here.
static func bs_floor(shot_type: String) -> float:
	return 0.10 if shot_type == "putt" or shot_type == "pitch" else 0.18


static func ft_floor(shot_type: String) -> float:
	return 0.04 if shot_type == "putt" or shot_type == "pitch" else 0.08


static func ratio(sample: Dictionary) -> float:
	var bs: float = float(sample.get("t_top", 0.0)) - float(sample.get("t_takeaway", 0.0))
	var ds: float = float(sample.get("t_impact", 0.0)) - float(sample.get("t_top", 0.0))
	if ds <= 0.001:
		return 99.0
	if bs <= 0.0:
		return 0.0
	return bs / ds


## Display-only floor: causes below this are not worth a fault line.
const DIAG_FLOOR := 0.18
## If top two severities are within this relative gap, keep only the top (no blend).
const DIAG_TIE_FRAC := 0.10

const FAULT_LINES := {
	"cast": "Cast at it — released too early",
	"jerky": "Rough tempo through the swing",
	"rushed_transition": "Rushed the transition — no pause at the top",
	"short_backswing": "Backswing too short — take it to the top",
	"short_finish": "Quit on it before the finish",
	"incomplete": "Didn't complete the swing",
	"back_slow": "Backswing — too slow, take it back with more pace",
	"back_fast": "Backswing — too quick",
	"down_fast": "Downswing — rushed the transition",
	"down_slow": "Downswing — lost speed through impact",
	"ratio_off": "Through too quick for that backswing",
}


static func balance_detail(
	sample: Dictionary, tighten: float = 1.0, shot_type: String = "full"
) -> Dictionary:
	## Same math as legacy balance(); also returns weighted cause severities for copy.
	var t := maxf(tighten, 0.0)
	var accel := float(sample.get("max_accel", 0.0))
	var jerk := float(sample.get("max_jerk", 0.0))
	var bs_len := float(sample.get("backswing_len", 0.0))
	var ft_len := float(sample.get("follow_through_len", 0.0))
	var incomplete: bool = bool(sample.get("incomplete", false))
	# Short strokes are shorter — don't grade putt/pitch length against a full-swing pad.
	var is_pitch := shot_type == "pitch"
	var short_game := shot_type == "putt" or is_pitch
	var floor_bs := bs_floor(shot_type)
	var floor_ft := ft_floor(shot_type)

	# ponytail: post-cap world — clean swings often sit ~25–45 after top mute;
	# full cast scales to ACCEL_LO+SPAN (frame cap 72). Old 8/24 maxed everyone at 48.
	var accel_lo := ACCEL_LO_PITCH if is_pitch else ACCEL_LO_FULL
	var accel_span := ACCEL_SPAN_PITCH if is_pitch else ACCEL_SPAN_FULL
	var accel_pen := clampf((accel - accel_lo) / accel_span, 0.0, 1.0) * t
	var jerk_pen := clampf((jerk - 0.6) / 1.4, 0.0, 1.0) * t
	var short_bs := clampf((floor_bs - bs_len) / floor_bs, 0.0, 1.0)
	var short_ft := 0.0 if incomplete else clampf((floor_ft - ft_len) / floor_ft, 0.0, 1.0)
	# Incomplete still hurts; short game less — early release is common on a putt stroke.
	var incomplete_pen := (0.30 if short_game else 0.55) if incomplete else 0.0

	# Did you slow down before turning around, relative to your own backswing speed —
	# not a fixed threshold, so it adapts to fast/slow swingers like the tempo ratio does.
	var peak_vel := float(sample.get("peak_vel", 0.0))
	var transition_ratio := float(sample.get("vel_at_top", 0.0)) / maxf(peak_vel, 0.001)
	# Pitch 2:1 reverse is snappier by design — don't demand a full-swing pause.
	var tr_lo := 0.28 if is_pitch else 0.15
	var tr_hi := 0.75 if is_pitch else 0.55
	var transition_pen := clampf((transition_ratio - tr_lo) / maxf(tr_hi - tr_lo, 0.05), 0.0, 1.0) * t

	var accel_w := 0.25 if is_pitch else 0.35
	var trans_w := 0.10 if is_pitch else 0.15
	var cast_s := accel_pen * accel_w
	var jerky_s := jerk_pen * 0.15
	var rush_s := transition_pen * trans_w
	var short_bs_s := short_bs * 0.20
	var short_ft_s := short_ft * 0.15
	var pen := cast_s + jerky_s + rush_s + short_bs_s + short_ft_s + incomplete_pen
	return {
		"score": clampf(1.0 - pen, 0.0, 1.0),
		"causes": {
			"cast": cast_s,
			"jerky": jerky_s,
			"rushed_transition": rush_s,
			"short_backswing": short_bs_s,
			"short_finish": short_ft_s,
			"incomplete": incomplete_pen,
		},
	}


static func balance(sample: Dictionary, tighten: float = 1.0, shot_type: String = "full") -> float:
	## Gesture qualities → 0..1. tighten scales how harshly spikes hurt (debug knob).
	return float(balance_detail(sample, tighten, shot_type)["score"])


static func tolerance_width(
	shot_type: String,
	bal: float,
	timing_scale: float = 1.0,
	tol_scale: float = 1.0
) -> float:
	## Held base (bal→1) = full window; lurch (bal→0) shrinks toward ~35% width. Never widens past base.
	var base := base_tolerance(shot_type) * maxf(tol_scale, 0.15) * maxf(timing_scale, 0.35)
	var shrink := lerpf(0.35, 1.0, clampf(bal, 0.0, 1.0))
	return base * shrink


static func guide_back_ms(shot_type: String, club_max_yards: float = 0.0) -> float:
	## Same absolute guide as TempoGesture ghost / meter ticks (ms).
	var base := (
		TempoGesture.GUIDE_BACK_SHORT
		if target_ratio(shot_type) < 2.5
		else TempoGesture.GUIDE_BACK_FULL
	)
	if shot_type == "full" and club_max_yards > 0.0:
		base *= TempoGesture.club_guide_duration_scale(club_max_yards)
	return base * 1000.0


static func guide_down_ms(shot_type: String, club_max_yards: float = 0.0) -> float:
	return guide_back_ms(shot_type, club_max_yards) / maxf(target_ratio(shot_type), 1.0)


static func grade(
	sample: Dictionary,
	shot_type: String,
	timing_scale: float = 1.0,
	tol_scale: float = 1.0,
	balance_tighten: float = 1.0,
	club_max_yards: float = 0.0
) -> Dictionary:
	var target := target_ratio(shot_type)
	var bal_detail: Dictionary = balance_detail(sample, balance_tighten, shot_type)
	var bal: float = float(bal_detail["score"])
	var r_raw := ratio(sample)
	var back_ms := int((float(sample.get("t_top", 0.0)) - float(sample.get("t_takeaway", 0.0))) * 1000.0)
	var down_ms := int((float(sample.get("t_impact", 0.0)) - float(sample.get("t_top", 0.0))) * 1000.0)
	var g_back := guide_back_ms(shot_type, club_max_yards)
	var g_down := guide_down_ms(shot_type, club_max_yards)
	# Contact ratio: soft-land when through is long vs guide (top backdate / real pause).
	# Clocks + F1 ratio stay raw; only abs_n / contact / path use r_grade.
	var r := r_raw
	if g_down > 1.0 and float(down_ms) > g_down * 1.15 and r_raw < target:
		var over := clampf((float(down_ms) / g_down - 1.15) / 0.6, 0.0, 1.0)
		r = lerpf(r_raw, target, over * 0.40)
	var err := r - target
	# Mild tempo: don't let a snappy through (accel → lurch) collapse the window into MISS.
	var base := base_tolerance(shot_type) * maxf(tol_scale, 0.15) * maxf(timing_scale, 0.35)
	var raw_n := absf(err) / maxf(base, 0.01)
	var bal_for_tol := maxf(bal, 0.70) if raw_n <= BAND_GOOD else bal
	var tol := base * lerpf(0.35, 1.0, clampf(bal_for_tol, 0.0, 1.0))
	var abs_n := absf(err) / maxf(tol, 0.01)

	var contact: ShotResult.ContactQuality
	var incomplete: bool = bool(sample.get("incomplete", false))
	if incomplete:
		# Incomplete → at least thin/fat; MISS if also far off
		contact = (
			ShotResult.ContactQuality.MISS
			if abs_n > BAND_GOOD
			else (ShotResult.ContactQuality.FAT if err < 0.0 else ShotResult.ContactQuality.THIN)
		)
	elif abs_n <= BAND_PERFECT:
		contact = ShotResult.ContactQuality.PERFECT
	elif abs_n <= BAND_GOOD:
		contact = ShotResult.ContactQuality.GOOD
	elif abs_n <= BAND_THIN_FAT:
		# Rushed (ratio low) → fat/early; high ratio → thin/late
		contact = ShotResult.ContactQuality.FAT if err < 0.0 else ShotResult.ContactQuality.THIN
	else:
		contact = ShotResult.ContactQuality.MISS

	# Extreme balance loss caps contact — modifier, not a second meter.
	if bal < 0.35 and contact == ShotResult.ContactQuality.PERFECT:
		contact = ShotResult.ContactQuality.GOOD
	# Hosel-adjacent demotion only when tempo itself is already outside the mild band.
	if bal < 0.25 and contact == ShotResult.ContactQuality.GOOD and raw_n > BAND_GOOD:
		contact = ShotResult.ContactQuality.FAT if err < 0.0 else ShotResult.ContactQuality.THIN

	# Distance is owned by contact tier (ball_physics.contact_multiplier).
	# Tempo error only taxes distance once we're out of GOOD — inside PERFECT/GOOD
	# a slightly-off ratio must not leak carry (was continuous abs_n tax on every shot).
	var power_mul := 1.0
	if contact == ShotResult.ContactQuality.THIN or contact == ShotResult.ContactQuality.FAT:
		var over_pw := maxf(abs_n - BAND_GOOD, 0.0)
		power_mul = clampf(1.0 - over_pw * 0.30, 0.55, 1.0)
	elif contact == ShotResult.ContactQuality.MISS:
		power_mul = 0.50

	# OTT / out-to-in magnitude (always ≥ 0). Applied as +pull on swing_shape so
	# shape moves toward fade/slice (+), not draw (−). Only when rushed past GOOD.
	var pull_max := TRANSITION_PULL_MAX_PITCH if shot_type == "pitch" else TRANSITION_PULL_MAX_FULL
	var transition_pull := 0.0
	if err < 0.0:
		var over_band := maxf(abs_n - BAND_GOOD, 0.0)
		transition_pull = clampf(over_band * TRANSITION_PULL_SCALE, 0.0, pull_max)

	var floor_bs := bs_floor(shot_type)
	var short_bs := clampf((floor_bs - float(sample.get("backswing_len", 0.0))) / floor_bs, 0.0, 1.0)
	# Display-only pace vs ghost guide (does not affect contact / power_mul / path).
	var reads: Dictionary = pace_reads(back_ms, down_ms, g_back, g_down)
	var back_read := str(reads.get("backswing_read", "on_pace"))
	var down_read := str(reads.get("downswing_read", "on_pace"))
	# Coaching copy uses raw ratio (matches F1 clocks); contact used r above.
	var copy: Dictionary = pace_copy(back_read, down_read, r_raw, target)
	back_read = str(copy.get("backswing_read", back_read))
	down_read = str(copy.get("downswing_read", down_read))
	var causes: Dictionary = bal_detail.get("causes", {})
	var diag: Dictionary = diagnose_swing(
		causes, back_read, down_read, r_raw, target, back_ms, down_ms, g_back, g_down
	)
	var note := tempo_note(
		r_raw, target, back_ms, down_ms, short_bs, back_read, down_read, str(copy.get("headline", "")), diag
	)

	# Debug-only (F1): guide vs actual downswing + transition speed — not used in grading.
	var vel_at_top := float(sample.get("vel_at_top", 0.0))
	var peak_vel := float(sample.get("peak_vel", 0.0))
	var down_delta_pct := (
		(float(down_ms) - g_down) / maxf(g_down, 1.0) * 100.0 if g_down > 0.0 else 0.0
	)

	return {
		"ratio": r_raw,  ## matches back/down clocks; contact used soft r when down long
		"target": target,
		"balance": bal,
		"tolerance": tol,
		"contact": contact,
		"power_mul": power_mul,
		## Full/pitch: path_error set in shot_routine from unified shape; grade leaves 0.
		"path_error": 0.0,
		"transition_pull": transition_pull,
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
		"guide_back_ms": int(g_back),
		"guide_down_ms": int(g_down),
		"down_delta_pct": down_delta_pct,
		"transition_ratio": vel_at_top / maxf(peak_vel, 0.001),
	}


static func pace_band(actual_ms: float, guide_ms: float) -> String:
	## "on_pace" | "slow" | "fast" vs ghost guide duration (display only).
	var g := maxf(guide_ms, 1.0)
	var err := actual_ms - g
	var half := g * PACE_TOL_FRAC
	if absf(err) <= half:
		return "on_pace"
	return "slow" if err > 0.0 else "fast"


static func pace_reads(
	back_ms: int, down_ms: int, guide_back_ms: float, guide_down_ms: float
) -> Dictionary:
	return {
		"backswing_read": pace_band(float(back_ms), guide_back_ms),
		"downswing_read": pace_band(float(down_ms), guide_down_ms),
	}


static func pace_copy(
	back_read: String, down_read: String, ratio: float = -1.0, target: float = 3.0
) -> Dictionary:
	## Coaching-biased lines. Never say "on time" when ratio is clearly off the target
	## (absolute guide bands can both pass while 4.2:1 vs 3:1 still grades MISS).
	var br := back_read
	var dr := down_read
	var back_line := ""
	var down_line := ""
	var ratio_ok := true
	if ratio >= 0.0 and target > 0.01:
		# Same ballpark as tempo_note "on tempo" (~8% of target).
		ratio_ok = absf(ratio - target) <= maxf(target * 0.08, 0.2)

	# Absolute guide said both fine, but ratio is the grade — re-attribute relatively.
	if br == "on_pace" and dr == "on_pace" and not ratio_ok:
		if ratio > target:
			# Too many back units per through: thru quick relative to back (playtest 826/197).
			br = "slow"  # long vs through (coaching often: speed the back / ease the whip)
			dr = "fast"
		else:
			br = "fast"
			dr = "slow"

	match br:
		"slow":
			back_line = "Backswing — too slow, take it back with more pace"
		"fast":
			back_line = "Backswing — too quick"
		_:
			back_line = "Backswing — on pace"
	match dr:
		"fast":
			down_line = "Downswing — rushed the transition"
		"slow":
			down_line = "Downswing — lost speed through impact"
		_:
			down_line = "Downswing — on pace"

	# Relative override lines when we re-attributed from ratio.
	if back_read == "on_pace" and down_read == "on_pace" and not ratio_ok:
		if ratio > target:
			back_line = "Backswing — long for that through"
			down_line = "Downswing — too quick vs back"
		else:
			back_line = "Backswing — short vs through"
			down_line = "Downswing — hanging / slow vs back"

	var headline: String
	if br == "on_pace" and dr == "on_pace" and ratio_ok:
		headline = "Tempo — on time"
	elif not ratio_ok and ratio > target:
		# Lead with the real miss: relationship, not absolute clocks.
		headline = "Through too quick for that backswing — match the %.0f:1" % target
	elif not ratio_ok and ratio < target:
		# Low ratio ≠ always "rushed transition" — after top-backdate, longer down
		# lowers ratio even when down is on/slow vs guide. Use absolute leg reads.
		if down_read == "fast":
			headline = "Rushed to through — brief pause at top"
		elif down_read == "slow":
			headline = "Through hanging vs back — match the %.0f:1" % target
		elif back_read == "fast":
			headline = "Backswing too quick for that through — match the %.0f:1" % target
		else:
			headline = "Under %.0f:1 — longer back or freer through" % target
	elif br == "slow":
		headline = back_line
	elif br == "on_pace" and dr != "on_pace":
		headline = down_line
	elif br == "fast" and dr == "on_pace":
		headline = back_line
	else:
		headline = back_line
	return {
		"back_line": back_line,
		"down_line": down_line,
		"headline": headline,
		"backswing_read": br,
		"downswing_read": dr,
	}


static func _pace_leg_severity(actual_ms: float, guide_ms: float) -> float:
	## 0 if on-pace; else overshoot past the guide half-band, normalized ~0..1.
	var g := maxf(guide_ms, 1.0)
	var half := g * PACE_TOL_FRAC
	var over := absf(actual_ms - g) - half
	if over <= 0.0:
		return 0.0
	return clampf(over / maxf(g * 0.5, 1.0), 0.0, 1.0)


static func diagnose_swing(
	causes: Dictionary,
	back_read: String = "",
	down_read: String = "",
	ratio: float = -1.0,
	target: float = 3.0,
	back_ms: int = 0,
	down_ms: int = 0,
	guide_back: float = 0.0,
	guide_down: float = 0.0
) -> Dictionary:
	## One ranked fault for copy. Balance causes + tempo pace/ratio on one severity scale.
	var cands: Array = []
	for key in causes.keys():
		var sev := float(causes[key])
		if sev > DIAG_FLOOR and FAULT_LINES.has(key):
			cands.append({"fault": str(key), "severity": sev, "line": str(FAULT_LINES[key])})

	if guide_back > 0.0 and back_ms > 0:
		var bs := _pace_leg_severity(float(back_ms), guide_back)
		if bs > DIAG_FLOOR:
			if back_read == "slow":
				cands.append({"fault": "back_slow", "severity": bs, "line": str(FAULT_LINES["back_slow"])})
			elif back_read == "fast":
				cands.append({"fault": "back_fast", "severity": bs, "line": str(FAULT_LINES["back_fast"])})
	if guide_down > 0.0 and down_ms > 0:
		var ds := _pace_leg_severity(float(down_ms), guide_down)
		if ds > DIAG_FLOOR:
			if down_read == "fast":
				cands.append({"fault": "down_fast", "severity": ds, "line": str(FAULT_LINES["down_fast"])})
			elif down_read == "slow":
				cands.append({"fault": "down_slow", "severity": ds, "line": str(FAULT_LINES["down_slow"])})

	if ratio >= 0.0 and target > 0.01:
		var band := maxf(target * 0.08, 0.2)
		var r_sev := clampf(absf(ratio - target) / band, 0.0, 1.0)
		if r_sev > DIAG_FLOOR:
			var r_line := str(FAULT_LINES["ratio_off"])
			if ratio > target:
				r_line = "Through too quick for that backswing — match the %.0f:1" % target
			elif ratio < target:
				# Gate "rushed" on actual fast through, not bare low ratio.
				if down_read == "fast":
					r_line = "Rushed to through — brief pause at top"
				elif down_read == "slow":
					r_line = "Through hanging vs back — match the %.0f:1" % target
				elif back_read == "fast":
					r_line = "Backswing too quick for that through — match the %.0f:1" % target
				else:
					r_line = "Under %.0f:1 — longer back or freer through" % target
			cands.append({"fault": "ratio_off", "severity": r_sev, "line": r_line})

	if cands.is_empty():
		return {"fault": "", "line": "", "severity": 0.0}

	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["severity"]) > float(b["severity"])
	)
	var top: Dictionary = cands[0]
	# Tie-break: do not blend two near-equal faults into one sentence.
	if cands.size() >= 2:
		var s0 := float(top["severity"])
		var s1 := float(cands[1]["severity"])
		if s0 > 0.0 and absf(s0 - s1) / s0 <= DIAG_TIE_FRAC:
			pass  # still only report top
	return {
		"fault": str(top["fault"]),
		"line": str(top["line"]),
		"severity": float(top["severity"]),
	}


static func tempo_note(
	r: float,
	target: float,
	back_ms: int = 0,
	down_ms: int = 0,
	short_bs: float = 0.0,
	back_read: String = "",
	down_read: String = "",
	headline: String = "",
	diag: Dictionary = {}
) -> String:
	## One coaching story — no steady/shaky/lurch append.
	var timing := ""
	if back_ms > 0 and down_ms > 0:
		timing = " (%dms back / %dms thru)" % [back_ms, down_ms]
	var dline := str(diag.get("line", ""))

	# Short takeaway is a golf miss — surface it once, no second fault tail.
	if short_bs >= 0.45:
		return "Tempo %.1f:1%s — backswing too short · take it to the top" % [r, timing]

	if not dline.is_empty():
		return "Tempo %.1f:1%s — %s" % [r, timing, dline]

	# Clean (or below speak floor): ratio context only, silence on swing-quality word.
	if not headline.is_empty():
		return "Tempo %.1f:1%s — %s" % [r, timing, headline]
	if not back_read.is_empty() and not down_read.is_empty():
		var copy: Dictionary = pace_copy(back_read, down_read, r, target)
		return "Tempo %.1f:1%s — %s" % [r, timing, str(copy["headline"])]
	var err := r - target
	var tempo_word: String
	if absf(err) <= target * 0.08:
		tempo_word = "on tempo"
	elif err < 0.0:
		if down_read == "fast":
			tempo_word = "rushed to through — brief pause at top"
		elif down_read == "slow":
			tempo_word = "through hanging vs back"
		else:
			tempo_word = "under target ratio — longer back or freer through"
	elif back_ms > 0 and down_ms > 0 and float(down_ms) < float(back_ms) / target * 0.92:
		tempo_word = "through too quick — finish through the ball"
	else:
		tempo_word = "pull/pause too long vs through — don't linger at top"
	return "Tempo %.1f:1%s — %s" % [r, timing, tempo_word]

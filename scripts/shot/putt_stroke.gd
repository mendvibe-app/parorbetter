class_name PuttStroke
extends RefCounted

## Putting stroke grade — amplitude (power) + arc path (line); tempo explains a miss.
## Deliberately separate from TempoGrade (ratio model is for full swings / chips).

## Pad marker range (fraction of lane). Floor stays above TempoGesture.MIN_BACKSWING_FRAC.
const MARKER_MIN_FRAC := 0.22
const MARKER_MAX_FRAC := 0.88
## Committed-power floor used in the map (matches recommended_power clamp).
const POWER_FLOOR := 0.05
## Half-width of accept band in pad-fraction space. Drawn = graded.
const BAND_HALF := 0.06
## Contact tiers by |frac_err| / BAND_HALF (same shape as TempoGrade bands).
const BAND_PERFECT := 0.50
const BAND_GOOD := 1.15
const BAND_SHORT_LONG := 1.85
## Natural-arc tolerance: flat floor + quadratic growth with stroke length (pad frac).
const ARC_FLOOR := 0.04
const ARC_SCALE := 0.10
## Matched back/through halves — |follow − back| beyond this hurts smoothness.
const MATCH_TOL := 0.18
## Tempo distance bias when smoothness is bad (± playtest knob).
const TEMPO_BIAS_MAX := 0.08
const PURE_BALANCE := 0.72
## Display only — physics stays yards; golfers read putts in feet.
const FT_PER_YD := 3.0
## Soft pad scale: known zone labeled, mid ticks only, farther = feel.
const SCALE_LABELED_FT := [3, 6, 10, 15]
const SCALE_TICK_FT := [20, 30]


static func yd_to_ft(yd: float) -> float:
	return yd * FT_PER_YD


static func ft_to_yd(ft: float) -> float:
	return ft / FT_PER_YD


static func marker_frac(committed_power: float) -> float:
	## Sqrt compression: short scoring putts get more pad resolution than lags.
	var u := _power_to_u(committed_power)
	return MARKER_MIN_FRAC + (MARKER_MAX_FRAC - MARKER_MIN_FRAC) * sqrt(u)


static func power_from_frac(frac: float) -> float:
	## Inverse of marker_frac — shared by grade + visual so windows never disagree.
	var span := MARKER_MAX_FRAC - MARKER_MIN_FRAC
	var t := clampf((frac - MARKER_MIN_FRAC) / maxf(span, 0.001), 0.0, 1.0)
	return _u_to_power(t * t)


static func frac_for_ft(ft: float, club_max_yd: float = 35.0) -> float:
	## Pad fraction for a putt length — same map grade uses (drawn = graded).
	var yd := ft_to_yd(ft)
	var power := clampf(yd / maxf(club_max_yd, 1.0), POWER_FLOOR, 1.0)
	return marker_frac(power)


static func band_half(_committed_power: float = 0.0) -> float:
	## Same band in pad space for every putt (tolerance drawn = graded).
	return BAND_HALF


static func arc_allowance(stroke_frac: float) -> float:
	var s := clampf(stroke_frac, 0.0, 1.0)
	return ARC_FLOOR + ARC_SCALE * s * s


static func grade(
	sample: Dictionary,
	committed_power: float,
	tol_scale: float = 1.0,
	balance_tighten: float = 1.0,
	club_max_yd: float = 35.0
) -> Dictionary:
	var target := marker_frac(committed_power)
	var band := BAND_HALF * maxf(tol_scale, 0.15)
	var actual := float(sample.get("backswing_frac", float(sample.get("backswing_len", 0.0))))
	var follow := float(sample.get("follow_frac", float(sample.get("follow_through_len", 0.0))))
	var incomplete: bool = bool(sample.get("incomplete", false))

	var frac_err := actual - target
	var abs_n := absf(frac_err) / maxf(band, 0.001)

	var bal := TempoGrade.balance(sample, balance_tighten, "putt")
	# Matched halves (8-4-4) — fold into smoothness.
	var match_err := absf(follow - actual)
	var match_pen := clampf(match_err / maxf(MATCH_TOL, 0.01), 0.0, 1.0)
	bal = clampf(bal * (1.0 - 0.35 * match_pen), 0.0, 1.0)

	var contact: ShotResult.ContactQuality
	if incomplete and abs_n > BAND_GOOD:
		contact = ShotResult.ContactQuality.MISS
	elif incomplete:
		contact = ShotResult.ContactQuality.FAT if frac_err < 0.0 else ShotResult.ContactQuality.THIN
	elif abs_n <= BAND_PERFECT:
		contact = ShotResult.ContactQuality.PERFECT
	elif abs_n <= BAND_GOOD:
		contact = ShotResult.ContactQuality.GOOD
	elif abs_n <= BAND_SHORT_LONG:
		# Short pull → leave it (FAT); long pull → blow past (THIN).
		contact = ShotResult.ContactQuality.FAT if frac_err < 0.0 else ShotResult.ContactQuality.THIN
	else:
		contact = ShotResult.ContactQuality.MISS

	if bal < 0.35 and contact == ShotResult.ContactQuality.PERFECT:
		contact = ShotResult.ContactQuality.GOOD

	# Amplitude → rolled power via inverse map (may exceed 1 — short commit, long pull).
	var rolled := power_from_frac(actual)
	var power_mul := rolled / maxf(committed_power, POWER_FLOOR)

	# Tempo as modifier: jab → long, decel/chop → short. Smooth = no effect.
	var tempo_bias := _tempo_bias(sample, bal, match_pen)
	power_mul *= 1.0 + tempo_bias
	if contact == ShotResult.ContactQuality.MISS:
		power_mul = minf(power_mul, 0.50)

	var path := _path_error(sample, actual)
	if bal < 0.35:
		path = clampf(path * (1.0 + (0.35 - bal)), -1.0, 1.0)

	var target_yd := committed_power * club_max_yd
	var rolled_yd := clampf(committed_power * power_mul, 0.05, 1.0) * club_max_yd
	var note := putt_note(target_yd, rolled_yd, path, bal, tempo_bias, abs_n, contact, actual, follow)

	return {
		"ratio": actual / maxf(target, 0.01),  # F1-friendly stand-in (not a tempo ratio)
		"target": target,
		"target_frac": target,
		"actual_frac": actual,
		"follow_frac": follow,
		"target_yd": target_yd,
		"rolled_yd": rolled_yd,
		"balance": bal,
		"tolerance": band,
		"contact": contact,
		"power_mul": power_mul,
		"path_error": path,
		"tempo_bias": tempo_bias,
		"note": note,
		"backswing_ms": int((float(sample.get("t_top", 0.0)) - float(sample.get("t_takeaway", 0.0))) * 1000.0),
		"downswing_ms": int((float(sample.get("t_impact", 0.0)) - float(sample.get("t_top", 0.0))) * 1000.0),
	}


static func putt_note(
	target_yd: float,
	rolled_yd: float,
	path: float,
	bal: float,
	tempo_bias: float,
	abs_n: float,
	contact: ShotResult.ContactQuality,
	actual_frac: float = -1.0,
	follow_frac: float = -1.0
) -> String:
	var bal_word := "steady" if bal >= PURE_BALANCE else ("shaky" if bal >= 0.4 else "lurch")
	var line_word := ""
	if absf(path) > 0.35:
		line_word = " · pushed right" if path > 0.0 else " · pulled left"
	elif absf(path) > 0.18:
		line_word = " · a bit right" if path > 0.0 else " · a bit left"

	var delta_ft := yd_to_ft(rolled_yd - target_yd)
	var target_ft := int(round(yd_to_ft(target_yd)))
	var rolled_ft := int(round(yd_to_ft(rolled_yd)))
	var ft_core := "Target %d ft → %d" % [target_ft, rolled_ft]
	if absf(delta_ft) < 1.0:
		ft_core += " — on pace"
	elif delta_ft < 0.0:
		ft_core += " — %d ft short" % int(round(absf(delta_ft)))
	else:
		ft_core += " — %d ft long" % int(round(delta_ft))

	# Short leave + unfinished through — same story as the old off-pad THRU cue.
	var short_through := (
		actual_frac > 0.05 and follow_frac >= 0.0 and follow_frac < actual_frac * 0.65
	)
	if delta_ft < -1.0 and short_through:
		return "%s · didn't finish through the ball (%s)%s" % [ft_core, bal_word, line_word]

	# Amplitude was in band but tempo spoiled it — lead with the golf why.
	if abs_n <= BAND_GOOD and absf(tempo_bias) > 0.02:
		var why := "jabbed through" if tempo_bias > 0.0 else "didn't finish through the ball"
		return "%s · %s (%s)%s" % [ft_core, why, bal_word, line_word]

	if contact == ShotResult.ContactQuality.PERFECT or abs_n <= BAND_PERFECT:
		return "%s · %s%s" % [ft_core, bal_word, line_word]
	return "%s · %s%s" % [ft_core, bal_word, line_word]


static func _power_to_u(committed_power: float) -> float:
	var p := clampf(committed_power, POWER_FLOOR, 1.0)
	return clampf((p - POWER_FLOOR) / (1.0 - POWER_FLOOR), 0.0, 1.0)


static func _u_to_power(u: float) -> float:
	return POWER_FLOOR + clampf(u, 0.0, 1.0) * (1.0 - POWER_FLOOR)


static func _tempo_bias(sample: Dictionary, bal: float, match_pen: float) -> float:
	if bal >= 0.72 and match_pen < 0.25:
		return 0.0
	var accel := float(sample.get("max_accel", 0.0))
	var incomplete: bool = bool(sample.get("incomplete", false))
	# High accel = jab → long; incomplete / unmatched through = decel → short.
	var jab := clampf((accel - 10.0) / 30.0, 0.0, 1.0)
	var decel := clampf(match_pen * 0.7 + (0.55 if incomplete else 0.0), 0.0, 1.0)
	var raw := (jab - decel) * TEMPO_BIAS_MAX
	# Scale by how bad balance is — smooth-enough strokes don't get a surprise.
	var severity := clampf(1.0 - bal, 0.0, 1.0)
	return clampf(raw * maxf(severity, 0.35), -TEMPO_BIAS_MAX, TEMPO_BIAS_MAX)


static func _path_error(sample: Dictionary, stroke_frac: float) -> float:
	## Signed lateral excess beyond natural-arc lane (pad-normalized).
	var lat := float(sample.get("max_lateral", 0.0))
	var allow := arc_allowance(stroke_frac)
	var excess := absf(lat) - allow
	if excess <= 0.0:
		return 0.0
	var signed := signf(lat) * clampf(excess / maxf(allow, 0.01), 0.0, 1.0)
	return clampf(signed, -1.0, 1.0)

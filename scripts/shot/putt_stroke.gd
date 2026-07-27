class_name PuttStroke
extends RefCounted

## Putting stroke grade — amplitude (power) + arc path (line); tempo explains a miss.
## Absolute log pad: soft ticks are landmarks; you guess where THIS putt sits.

## Pad marker range (fraction of lane). MIN_BACKSWING_FRAC (0.14 of pad height)
## is ~0.20 of lane fraction (lane = 0.70 of pad height) — floor needs real
## headroom above that or a tap-in target sits right on "didn't register."
const MARKER_MIN_FRAC := 0.26
const MARKER_MAX_FRAC := 0.88
## Committed-power floor used in the map (matches recommended_power clamp).
## 2 ft at PUTTER_MAX_YD (25 yd / 75 ft) — a real tap-in, not a 6 ft floor.
const POWER_FLOOR := 0.0267
## Half-width of accept band in pad-fraction space. Drawn = graded.
## Log map makes this a percentage band (~±40% of the putt) rather than the old
## fixed ±10 ft — tuning candidate for a follow-up pass.
const BAND_HALF := 0.06
## Contact tiers by |frac_err| / BAND_HALF (same shape as TempoGrade bands).
const BAND_PERFECT := 0.50
const BAND_GOOD := 1.15
## Natural-arc tolerance: flat floor + quadratic growth with stroke length (pad frac).
const ARC_FLOOR := 0.10
const ARC_SCALE := 0.16
## Matched back/through halves — |follow − back| beyond this hurts smoothness.
const MATCH_TOL := 0.18
## Tempo distance bias when smoothness is bad (± playtest knob).
const TEMPO_BIAS_MAX := 0.08
const PURE_BALANCE := 0.72
## Display only — physics stays yards; golfers read putts in feet.
const FT_PER_YD := 3.0
## Soft pad scale: spaced for the log curve (linear-pad spacing bunches up on it).
const SCALE_LABELED_FT := [3, 6, 12, 25, 50]
const SCALE_TICK_FT := [8, 18, 70]
## Curve shape on top of the log map — pow(u, BEND) / pow(u, 1/BEND). 1.0 = pure log.
const BEND := 1.0


static func yd_to_ft(yd: float) -> float:
	return yd * FT_PER_YD


static func ft_to_yd(ft: float) -> float:
	return ft / FT_PER_YD


static func _power_to_u(committed_power: float) -> float:
	## Log u in [0,1] from power floor → full — constant thumb error → constant % distance error.
	var p := clampf(committed_power, POWER_FLOOR, 1.0)
	var u := log(p / POWER_FLOOR) / log(1.0 / POWER_FLOOR)
	return pow(clampf(u, 0.0, 1.0), BEND)


static func _u_to_power(u: float) -> float:
	## Exact inverse of _power_to_u.
	var lin := pow(clampf(u, 0.0, 1.0), 1.0 / BEND)
	return POWER_FLOOR * pow(1.0 / POWER_FLOOR, lin)


static func marker_frac(committed_power: float) -> float:
	## Log-spaced: short putts low on pad, lags high — feel/guess, not mid-lane answer.
	var u := _power_to_u(committed_power)
	return MARKER_MIN_FRAC + (MARKER_MAX_FRAC - MARKER_MIN_FRAC) * u


static func power_from_frac(frac: float) -> float:
	## Inverse of marker_frac — soft scale / grade share one map.
	var span := MARKER_MAX_FRAC - MARKER_MIN_FRAC
	var t := clampf((frac - MARKER_MIN_FRAC) / maxf(span, 0.001), 0.0, 1.0)
	return _u_to_power(t)


static func frac_for_ft(ft: float, club_max_yd: float = BallPhysics.PUTTER_MAX_YD) -> float:
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
	club_max_yd: float = 40.0
) -> Dictionary:
	var target := marker_frac(committed_power)
	var band := BAND_HALF * maxf(tol_scale, 0.15)
	var actual := float(sample.get("backswing_frac", float(sample.get("backswing_len", 0.0))))
	var follow := float(sample.get("follow_frac", float(sample.get("follow_through_len", 0.0))))
	var incomplete: bool = bool(sample.get("incomplete", false))

	var frac_err := actual - target
	var abs_n := absf(frac_err) / maxf(band, 0.001)

	var bal := TempoGrade.balance(sample, balance_tighten, "putt")
	# Matched halves — follow should match backswing, but only up to what fits past address on-pad
	# (drawn cue = this cap). Don't punish a full finish the pad can't show.
	var follow_cap := float(sample.get("follow_cap_frac", 1.0))
	var match_target := minf(actual, maxf(follow_cap, 0.05))
	var match_err := 0.0 if follow >= match_target else (match_target - follow)
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
	else:
		# Pace error only — short leave / blow past. Hole-out from line+physics, not auto-MISS.
		contact = ShotResult.ContactQuality.FAT if frac_err < 0.0 else ShotResult.ContactQuality.THIN

	if bal < 0.35 and contact == ShotResult.ContactQuality.PERFECT:
		contact = ShotResult.ContactQuality.GOOD

	# Absolute amplitude → rolled power (may exceed commit — smash runs long).
	var rolled := power_from_frac(actual)
	var power_mul := rolled / maxf(committed_power, POWER_FLOOR)

	# Tempo as modifier: jab → long, decel/chop → short. Smooth = no effect.
	var tempo_bias := _tempo_bias(sample, bal, match_pen)
	power_mul *= 1.0 + tempo_bias

	var path := _path_error(sample, actual)
	if bal < 0.35:
		path = clampf(path * (1.0 + (0.35 - bal)), -1.0, 1.0)

	var target_yd := committed_power * club_max_yd
	var rolled_yd := clampf(committed_power * power_mul, 0.05, 1.0) * club_max_yd
	var note := putt_note(target_yd, rolled_yd, path, bal, tempo_bias, abs_n, contact, actual, follow, match_target)

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
	follow_frac: float = -1.0,
	follow_need: float = -1.0
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

	# Short leave + unfinished through — need is pad-capped matched follow (drawn = graded).
	var need := follow_need if follow_need > 0.0 else actual_frac
	var short_through := (
		actual_frac > 0.05 and follow_frac >= 0.0 and follow_frac < need * 0.65
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

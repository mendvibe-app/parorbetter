class_name ShotReport
extends RefCounted

## Builds a readable breakdown of why a shot went the distance it did.

var club_name: String = ""
var club_max_yards: float = 0.0
var lie: String = ""
var severity: String = ""
var power: float = 0.0
var stance: float = 0.0
var path_error: float = 0.0
var contact: String = ""
var contact_mul: float = 1.0
var lie_mul: float = 1.0
var planned_yards: float = 0.0
var actual_yards: float = -1.0
var aim_radius_yd: float = 0.0
var aim_offset: String = ""
var wind_note: String = ""
var tempo_note: String = ""
var reasons: PackedStringArray = PackedStringArray()


static func from_shot(
	result: ShotResult,
	p_club: String,
	p_club_max: float,
	p_lie: String,
	p_aim_radius_yd: float = 0.0,
	p_aim_offset: String = "",
	p_wind_note: String = "",
	p_severity: String = "",
	p_shot_type: String = "full"
) -> ShotReport:
	var r := ShotReport.new()
	r.club_name = p_club
	r.club_max_yards = p_club_max
	r.lie = p_lie
	r.severity = p_severity
	r.power = result.power
	r.stance = result.stance_stability
	r.path_error = result.path_error
	r.contact = result.contact_label()
	r.contact_mul = BallPhysics.contact_multiplier(result.contact_quality, p_lie, p_shot_type)
	r.lie_mul = BallPhysics.lie_multiplier(p_lie, p_severity)
	# Same owner as launch — Plan matches Actual when force/path/contact agree.
	var force_p := result.true_power if result.true_power > 0.0 else -1.0
	r.planned_yards = BallPhysics.resolve_distance(
		p_club_max,
		result.power,
		p_lie,
		p_severity,
		result.contact_quality,
		p_shot_type,
		result.path_error,
		force_p
	)
	r.aim_radius_yd = p_aim_radius_yd
	r.aim_offset = p_aim_offset
	r.wind_note = p_wind_note
	r._build_reasons(result)
	if not GameState.last_tempo_metrics.is_empty():
		var note := str(GameState.last_tempo_metrics.get("note", ""))
		if note != "":
			r.tempo_note = note
			r.reasons.insert(0, note)
	return r


func set_actual(yards: float) -> void:
	actual_yards = yards


func _build_reasons(result: ShotResult) -> void:
	reasons.clear()
	if lie == "Green":
		_build_putt_reasons(result)
		return
	match result.contact_quality:
		ShotResult.ContactQuality.PERFECT:
			if contact_mul > 1.001:
				reasons.append("Contact PURE — small distance bonus")
			else:
				reasons.append("Contact PURE — committed distance")
		ShotResult.ContactQuality.GOOD:
			reasons.append("Contact GOOD — full distance")
		ShotResult.ContactQuality.THIN:
			reasons.append("Contact THIN — only %d%% distance" % int(contact_mul * 100.0))
		ShotResult.ContactQuality.FAT:
			reasons.append("Contact FAT — only %d%% distance" % int(contact_mul * 100.0))
		ShotResult.ContactQuality.MISS:
			reasons.append("Contact MISS — only %d%% distance" % int(contact_mul * 100.0))

	var force := BallPhysics.force_factor(power, club_max_yards, lie)
	if force > 0.35:
		if power >= BallPhysics.POWER_POCKET_HI:
			reasons.append("Forced mash (%d%%) — accuracy tax" % int(power * 100.0))
		else:
			reasons.append("Baby'd the club (%d%%) — accuracy tax" % int(power * 100.0))
	elif power < 0.35:
		reasons.append("Power low (%d%%) — big distance cut" % int(power * 100.0))
	elif power < 0.55:
		reasons.append("Power modest (%d%%)" % int(power * 100.0))
	elif power >= 0.95:
		reasons.append("Power near max (%d%%)" % int(power * 100.0))

	if stance < 0.35:
		reasons.append("Balance lost (%d%%) — tempo window crushed" % int(stance * 100.0))
	elif stance < 0.6:
		reasons.append("Balance shaky (%d%%)" % int(stance * 100.0))
	elif stance >= TempoGrade.PURE_BALANCE:
		reasons.append("Balance held (%d%%)" % int(stance * 100.0))

	if absf(path_error) > 0.55:
		var side := "SLICE/right" if path_error > 0.0 else "HOOK/left"
		reasons.append("Path %s (%+.2f) — curves offline" % [side, path_error])
	elif absf(path_error) > 0.25:
		var side2 := "right" if path_error > 0.0 else "left"
		reasons.append("Path a bit %s (%+.2f)" % [side2, path_error])

	match lie:
		"Rough":
			if severity != "" and GameState.rough_severity_enabled:
				var tag := severity.to_lower()
				if severity == BallPhysics.ROUGH_SEV_SITTING:
					tag = "sitting up"
				reasons.append(
					"Lie ROUGH (%s) — %d%% club distance" % [tag, int(lie_mul * 100.0)]
				)
			else:
				reasons.append("Lie ROUGH — %d%% club distance" % int(lie_mul * 100.0))
		"Sand":
			reasons.append("Lie SAND — %d%% club distance" % int(lie_mul * 100.0))
		"Tee":
			reasons.append("Lie TEE")
		_:
			reasons.append("Lie %s" % lie.to_upper())

	if aim_radius_yd > 0.0:
		reasons.append("Aim circle %d yd (%s form)" % [int(aim_radius_yd), GameState.form_label()])
	if aim_offset != "":
		reasons.append("Aimed %s vs pin" % aim_offset)
	if wind_note != "":
		reasons.append(wind_note)

	var quality_ok := result.contact_quality == ShotResult.ContactQuality.PERFECT \
		or result.contact_quality == ShotResult.ContactQuality.GOOD
	if not quality_ok and power >= 0.7:
		reasons.append("WHY SHORT: timing/contact, not power")
	elif quality_ok and power < 0.45:
		reasons.append("WHY SHORT: power was too low")
	elif lie in ["Rough", "Sand"] and quality_ok:
		reasons.append("WHY SHORT: bad lie eats distance")


func _build_putt_reasons(result: ShotResult) -> void:
	match result.contact_quality:
		ShotResult.ContactQuality.PERFECT:
			reasons.append("Stroke length on pace")
		ShotResult.ContactQuality.GOOD:
			reasons.append("Stroke length close")
		ShotResult.ContactQuality.FAT:
			reasons.append("Stroke short — left it")
		ShotResult.ContactQuality.THIN:
			reasons.append("Stroke long — past the hole")
		ShotResult.ContactQuality.MISS:
			reasons.append("Stroke way off pace")
	if absf(path_error) > 0.35:
		var side := "right" if path_error > 0.0 else "left"
		reasons.append("Pushed/pulled %s of the line" % side)
	elif absf(path_error) > 0.18:
		var side2 := "right" if path_error > 0.0 else "left"
		reasons.append("Line a bit %s" % side2)
	if stance < 0.4:
		reasons.append("Stroke tempo spoiled the roll")
	elif stance >= PuttStroke.PURE_BALANCE:
		reasons.append("Smooth stroke")
	reasons.append("Putt — rolls toward aim")
	if aim_offset != "":
		reasons.append("Aimed %s vs pin" % aim_offset)


func summary_line() -> String:
	return glance_text()


func glance_text() -> String:
	## Short real-golf call + distance. Face map carries location; F1 keeps tempo dump.
	var call := _golf_call()
	if actual_yards >= 0.0:
		if lie == "Green":
			return "%s\n→ %d ft" % [call, int(round(PuttStroke.yd_to_ft(actual_yards)))]
		return "%s\n→ %d yd" % [call, int(actual_yards)]
	return call


func _golf_call() -> String:
	## Contact + shape in words golfers already use. Path left/right matches face map.
	if lie == "Green":
		return _putt_call()
	var hit := _contact_call()
	var shape := _shape_call()
	if shape == "":
		return hit
	return "%s · %s" % [hit, shape]


func _contact_call() -> String:
	var pure := contact == "perfect" and stance >= TempoGrade.PURE_BALANCE
	match contact:
		"perfect":
			return "Pure" if pure else "Solid"
		"good":
			return "Clean"
		"thin":
			return "Thin"
		"fat":
			return "Heavy"
		"miss":
			return "Miss"
		_:
			return contact.capitalize()


func _shape_call() -> String:
	var a := absf(path_error)
	if a <= 0.25:
		return ""
	if path_error > 0.0:
		return "slice" if a > 0.55 else "fade"
	return "hook" if a > 0.55 else "draw"


func _putt_call() -> String:
	var pace := ""
	match contact:
		"perfect":
			pace = "On pace"
		"good":
			pace = "Close"
		"fat":
			pace = "Short"
		"thin":
			pace = "Long"
		"miss":
			pace = "Way off"
		_:
			pace = "Putt"
	var line := ""
	if absf(path_error) > 0.35:
		line = "pushed" if path_error > 0.0 else "pulled"
	elif absf(path_error) > 0.18:
		line = "a bit right" if path_error > 0.0 else "a bit left"
	if line == "":
		return pace
	return "%s · %s" % [pace, line]


func full_text() -> String:
	## Debug / F1 detail dump — not shown on the player result panel.
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SHOT RESULT")
	lines.append("%s  (max %d yd)  from %s" % [club_name, int(club_max_yards), lie])
	lines.append("Power %d%%   Balance %d%%   Path %+.2f" % [
		int(power * 100.0), int(stance * 100.0), path_error
	])
	if tempo_note != "":
		lines.append(tempo_note)
	lines.append("Contact %s  (×%.2f)   Lie ×%.2f" % [
		contact.to_upper(), contact_mul, lie_mul
	])
	if aim_radius_yd > 0.0 or aim_offset != "":
		lines.append("Aim circle %d yd · %s" % [int(aim_radius_yd), aim_offset if aim_offset != "" else "pin"])
	lines.append("Planned distance:  %d yd" % int(planned_yards))
	if actual_yards >= 0.0:
		var delta := actual_yards - planned_yards
		lines.append("Actual distance:   %d yd  (%+d)" % [int(actual_yards), int(delta)])
	lines.append("———")
	for reason in reasons:
		lines.append("• " + reason)
	return "\n".join(lines)

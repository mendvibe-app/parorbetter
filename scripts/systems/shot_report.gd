class_name ShotReport
extends RefCounted

## Builds a readable breakdown of why a shot went the distance it did.

var club_name: String = ""
var club_max_yards: float = 0.0
var lie: String = ""
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
var reasons: PackedStringArray = PackedStringArray()


static func from_shot(
	result: ShotResult,
	p_club: String,
	p_club_max: float,
	p_lie: String,
	p_aim_radius_yd: float = 0.0,
	p_aim_offset: String = "",
	p_wind_note: String = ""
) -> ShotReport:
	var r := ShotReport.new()
	r.club_name = p_club
	r.club_max_yards = p_club_max
	r.lie = p_lie
	r.power = result.power
	r.stance = result.stance_stability
	r.path_error = result.path_error
	r.contact = result.contact_label()
	r.contact_mul = BallPhysics.contact_multiplier(result.contact_quality)
	r.lie_mul = BallPhysics.lie_multiplier(p_lie)
	r.planned_yards = p_club_max * result.power * r.lie_mul * r.contact_mul
	r.aim_radius_yd = p_aim_radius_yd
	r.aim_offset = p_aim_offset
	r.wind_note = p_wind_note
	r._build_reasons(result)
	return r


func set_actual(yards: float) -> void:
	actual_yards = yards


func _build_reasons(result: ShotResult) -> void:
	reasons.clear()
	match result.contact_quality:
		ShotResult.ContactQuality.PERFECT:
			reasons.append("Contact PURE — small distance bonus")
		ShotResult.ContactQuality.GOOD:
			reasons.append("Contact GOOD — full distance")
		ShotResult.ContactQuality.THIN:
			reasons.append("Contact THIN — only %d%% distance" % int(contact_mul * 100.0))
		ShotResult.ContactQuality.FAT:
			reasons.append("Contact FAT — only %d%% distance" % int(contact_mul * 100.0))
		ShotResult.ContactQuality.MISS:
			reasons.append("Contact MISS — only %d%% distance" % int(contact_mul * 100.0))

	var force := BallPhysics.force_factor(power)
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
		reasons.append("Stance unstable (%d%%) — line/contact suffer" % int(stance * 100.0))
	elif stance < 0.6:
		reasons.append("Stance shaky (%d%%)" % int(stance * 100.0))

	if absf(path_error) > 0.55:
		var side := "SLICE/right" if path_error > 0.0 else "HOOK/left"
		reasons.append("Path %s (%+.2f) — curves offline" % [side, path_error])
	elif absf(path_error) > 0.25:
		var side2 := "right" if path_error > 0.0 else "left"
		reasons.append("Path a bit %s (%+.2f)" % [side2, path_error])

	match lie:
		"Rough":
			reasons.append("Lie ROUGH — %d%% club distance" % int(lie_mul * 100.0))
		"Sand":
			reasons.append("Lie SAND — %d%% club distance" % int(lie_mul * 100.0))
		"Green":
			reasons.append("Putt — rolls toward aim")
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


func summary_line() -> String:
	var actual_txt := "—"
	if actual_yards >= 0.0:
		actual_txt = "%d yd" % int(actual_yards)
	return "%s  %d%%  %s  →  plan %d yd  got %s" % [
		club_name,
		int(power * 100.0),
		contact.to_upper(),
		int(planned_yards),
		actual_txt,
	]


func full_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SHOT RESULT")
	lines.append("%s  (max %d yd)  from %s" % [club_name, int(club_max_yards), lie])
	lines.append("Power %d%%   Stance %d%%   Path %+.2f" % [
		int(power * 100.0), int(stance * 100.0), path_error
	])
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

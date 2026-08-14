class_name ClubCoachLog
extends RefCounted

## Per-club rolling aggregate. Keyed by club_name. Persists across runs (user://club_coach.cfg).

const WINDOW := 20  ## rolling sample size per club, mirrors path_miss_history style
const MIN_SAMPLES_FOR_TIP := 5
const SAVE_PATH := "user://club_coach.cfg"
## Bump invalidates saved history (pre–flight-rebuild yardage/tempo is a different game).
const SCHEMA_VERSION := 2
const META_SECTION := "_meta"

## Tempo/path bias thresholds — first-guess playtest knobs, retune once real F1 data exists.
const TEMPO_THRESHOLD := 0.35
const PATH_THRESHOLD := 0.25
const CONTACT_MISS_FRACTION := 0.40

var clubs: Dictionary = {}  ## club_name -> stats Dictionary


func _ensure(club_name: String) -> Dictionary:
	if not clubs.has(club_name):
		clubs[club_name] = {
			"shots_logged": 0,
			"yardage_history": [],
			"path_error_history": [],
			"tempo_err_history": [],
			"contact_tally": {},
			"longest_made_yards": 0.0,
		}
	return clubs[club_name]


func record(
	club_name: String, result: ShotResult, verdict: Dictionary, actual_yards: float, holed: bool = false
) -> void:
	var stats := _ensure(club_name)
	stats["shots_logged"] = int(stats["shots_logged"]) + 1
	_push(stats["yardage_history"], actual_yards)
	_push(stats["path_error_history"], result.path_error)
	# Full-swing TempoGrade verdicts carry ratio/target; putt verdicts (PuttStroke) don't.
	if verdict.has("ratio") and verdict.has("target"):
		_push(stats["tempo_err_history"], float(verdict["ratio"]) - float(verdict["target"]))
	var tally: Dictionary = stats["contact_tally"]
	var key := int(result.contact_quality)
	tally[key] = int(tally.get(key, 0)) + 1
	if holed:
		stats["longest_made_yards"] = maxf(float(stats.get("longest_made_yards", 0.0)), actual_yards)
	save_data()


func _push(arr: Array, v: float) -> void:
	arr.append(v)
	if arr.size() > WINDOW:
		arr.pop_front()


static func avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / arr.size()


## mode "coach" (default): tempo → path → contact — root cause first (Club Coach screen).
## mode "select": path → contact → tempo — club-specific signals first (club select rows).
## Tempo is a player habit; repeating it on every club row hides differentiating path/contact.
static func resolve_tip(stats: Dictionary, mode: String = "coach") -> Dictionary:
	var shots := int(stats.get("shots_logged", 0))
	if shots < MIN_SAMPLES_FOR_TIP:
		return {"tag": "insufficient_data", "label": "Not enough shots yet", "icon_id": "insufficient_data"}

	var for_select := mode == "select"
	if for_select:
		var path_tip := _tip_path(stats)
		if not path_tip.is_empty():
			return path_tip
		var contact_tip := _tip_contact(stats)
		if not contact_tip.is_empty():
			return contact_tip
		var tempo_tip := _tip_tempo(stats)
		if not tempo_tip.is_empty():
			return tempo_tip
	else:
		var tempo_tip := _tip_tempo(stats)
		if not tempo_tip.is_empty():
			return tempo_tip
		var path_tip := _tip_path(stats)
		if not path_tip.is_empty():
			return path_tip
		var contact_tip := _tip_contact(stats)
		if not contact_tip.is_empty():
			return contact_tip

	return {"tag": "on_track", "label": "Dialed in", "icon_id": "on_track"}


static func _tip_tempo(stats: Dictionary) -> Dictionary:
	var tempo_avg := avg(stats.get("tempo_err_history", []))
	if tempo_avg <= -TEMPO_THRESHOLD:
		return {
			"tag": "rushed_transition",
			"label": "Rushing transition — pause at the top before starting down",
			"icon_id": "rushed_transition",
		}
	if tempo_avg >= TEMPO_THRESHOLD:
		return {
			"tag": "lingering_top",
			"label": "Losing rhythm at the top — start down sooner",
			"icon_id": "lingering_top",
		}
	return {}


static func _tip_path(stats: Dictionary) -> Dictionary:
	var path_avg := avg(stats.get("path_error_history", []))
	if path_avg >= PATH_THRESHOLD:
		return {"tag": "slice_tendency", "label": "Path leaking right", "icon_id": "slice_tendency"}
	if path_avg <= -PATH_THRESHOLD:
		return {"tag": "hook_tendency", "label": "Path leaking left", "icon_id": "hook_tendency"}
	return {}


static func _tip_contact(stats: Dictionary) -> Dictionary:
	var tally: Dictionary = stats.get("contact_tally", {})
	var lifetime := 0
	var bad := 0
	for k in tally:
		var count := int(tally[k])
		lifetime += count
		if k in [
			ShotResult.ContactQuality.THIN,
			ShotResult.ContactQuality.FAT,
			ShotResult.ContactQuality.MISS,
		]:
			bad += count
	if lifetime > 0 and float(bad) / float(lifetime) > CONTACT_MISS_FRACTION:
		return {
			"tag": "contact_issue",
			"label": "Contact inconsistent — thin/fat misses adding up",
			"icon_id": "contact_issue",
		}
	return {}


func clear_data() -> void:
	## Wipe all clubs and rewrite save (schema stamp only). Used on schema mismatch.
	clubs.clear()
	save_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var ver := int(cfg.get_value(META_SECTION, "schema_version", 1))
	if ver != SCHEMA_VERSION:
		# Pre–flight-rebuild history (or any older schema) is not comparable.
		clear_data()
		return
	clubs.clear()
	for section in cfg.get_sections():
		if section == META_SECTION:
			continue
		clubs[section] = {
			"shots_logged": int(cfg.get_value(section, "shots_logged", 0)),
			"yardage_history": Array(cfg.get_value(section, "yardage_history", [])),
			"path_error_history": Array(cfg.get_value(section, "path_error_history", [])),
			"tempo_err_history": Array(cfg.get_value(section, "tempo_err_history", [])),
			"contact_tally": Dictionary(cfg.get_value(section, "contact_tally", {})),
			"longest_made_yards": float(cfg.get_value(section, "longest_made_yards", 0.0)),
		}


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(META_SECTION, "schema_version", SCHEMA_VERSION)
	for club_name in clubs:
		var stats: Dictionary = clubs[club_name]
		cfg.set_value(club_name, "shots_logged", stats["shots_logged"])
		cfg.set_value(club_name, "yardage_history", stats["yardage_history"])
		cfg.set_value(club_name, "path_error_history", stats["path_error_history"])
		cfg.set_value(club_name, "tempo_err_history", stats["tempo_err_history"])
		cfg.set_value(club_name, "contact_tally", stats["contact_tally"])
		cfg.set_value(club_name, "longest_made_yards", stats["longest_made_yards"])
	cfg.save(SAVE_PATH)

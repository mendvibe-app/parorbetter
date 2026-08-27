extends Node

signal lives_changed(lives: int)
signal hole_changed(hole_index: int)
signal run_ended(deepest_hole: int, reason: String)
signal adaptation_changed(bias: float)
signal form_changed(form: float)
signal pure_strikes_changed(count: int)

const MAX_LIVES := 5
const START_LIVES := 3
const DEFAULT_HOLE_COUNT := 18
const FORM_HISTORY_MAX := 8

## Non-putt landing circle: full swing from club bucket
## (BallPhysics.lateral_spread_range_yards); chip/pitch/flop from planned rest
## yards × shot-type band (BallPhysics.short_game_aim_radius_yards). Display only.
## Putt circle (yards) — ~3–8 feet.
const PUTT_RADIUS_WEAK_YD := 2.7
const PUTT_RADIUS_PRO_YD := 1.0
## Short-game form widen — PLAYTEST TARGET. Sharp stays on table; wild opens ~35%.
const SHORT_AIM_FORM_WIDEN := 1.35

var lives: int = START_LIVES
var current_hole: int = 1  # 1-based
var deepest_hole: int = 1
var strokes_this_hole: int = 0
var total_strokes: int = 0
var pure_strikes: int = 0  ## Round-level flush-contact count
var last_shot_metrics: Dictionary = {}
var run_active: bool = true

## Generated course (runtime length). HOLE_COUNT tracks course.size().
var HOLE_COUNT: int = DEFAULT_HOLE_COUNT
var course_seed: int = 0
var course_theme: HoleData.CourseTheme = HoleData.CourseTheme.PARKLAND
var course: Array[HoleData] = []

## Signed path-error history (−1 hook/left … +1 slice/right). Drives hazard/wind bias.
var path_miss_history: Array[float] = []

## Rolling shot form 0–1 from contact + stance (drives aim circle size).
var form_history: Array[float] = []

## Debug overrides (null = use hole defaults)
var debug_timing_scale: Variant = null
var debug_wind_scale: Variant = null
var debug_fairway_scale: Variant = null
## Tempo playtest knobs (null = 1.0 defaults)
var debug_tempo_tol: Variant = null
var debug_balance_tighten: Variant = null
var force_perfect: bool = false
var force_mishit: bool = false
## Phase 0 putt-line prototype (putting-rework-roadmap): bearing drag, distance locked to cup.
## Off = today's free-point putt aim (distance ≈ pace preview). F1 toggle.
var debug_putt_line_aim: bool = false
## Last tempo verdict (ratio, balance, ms…) for F1 readout
var last_tempo_metrics: Dictionary = {}
## Fadeable tempo guide — shows rhythm only, never widens windows.
var tempo_guide_enabled: bool = true
var tempo_guide_forced: bool = false
## Auto practice reps before the real swing after Confirm Aim (0–3), per shot type.
## Not used in range_mode. Defaults: full/pitch get one; short game starts at zero.
var practice_reps: Dictionary = {"full": 1, "pitch": 1, "chip": 0, "putt": 0, "flop": 1}
## Lifetime real-shot counts per shot type (ghost-guide familiarity, Phase 4).
## 0 reps → strong guide even if global form is high.
var shot_type_reps: Dictionary = {}
## Tap-in fast path (putt ceremony skip). Playtest knobs via F1.
var tap_in_yd: float = 4.0
var tap_in_break: float = 0.12
## Driving range — infinite tee practice, no lives / hole advance.
var range_mode: bool = false
## Practice green — infinite putt practice, no lives / hole advance.
var green_mode: bool = false
## Short-game practice — station lie/distance + aim/shot-type, infinite reset.
var short_game_mode: bool = false
## 18 Hole Round (stroke play) — no lives, always finish 18. False = Survival.
var stroke_play_mode: bool = false

## In-run score vs par (sum of strokes − par per hole).
var score_to_par: int = 0
## Net score to par (stroke play with handicap strokes applied).
var net_score_to_par: int = 0
## Per-hole score-to-par for the current round (appended on each hole-out).
var hole_scores: Array[int] = []
## Course slope-style difficulty (~55–155) from mean hole complexity.
var course_slope: float = 113.0
## stroke_index[h] = SI rank 1..18 (1 = hardest); h is 0-based hole index.
var stroke_index: PackedInt32Array = PackedInt32Array()
## Strokes received this round from course handicap (0 if HCP not established).
var course_handicap: int = 0

## Persisted records (`user://records.cfg`) — Survival.
var best_score_to_par: int = 0
var best_deepest_hole: int = 0
var has_finished_course: bool = false
## 18 Hole Round PB (independent of Survival).
var best_stroke_score_to_par: int = 0
var has_finished_stroke_round: bool = false
## Rolling stroke-play differentials (last 20) for handicap index.
var stroke_differentials: Array[float] = []

const RECORDS_PATH := "user://records.cfg"
const DIFF_HISTORY_MAX := 20
const HCP_MIN_ROUNDS := 3

## Per-club tendency aggregate — persists across runs, excluded from reset_run().
var club_coach: ClubCoachLog
## Player-facing coach card (start screen + club-select badges). Always on.
var club_coach_ui_enabled: bool = true
## Sharpened dogleg corners — live for dogleg layouts (no F1 A/B).
var sharp_dogleg_enabled: bool = true
## Rough lie severity — Buried / Average / SittingUp. Always on.
var rough_severity_enabled: bool = true
## Force tee set (null = progress-based Red→White→Blue). HoleData.TeeSet or null.
var debug_tee_set: Variant = null


func _ready() -> void:
	_load_records()
	club_coach = ClubCoachLog.new()
	club_coach.load_data()
	reset_run()


func reset_run(p_stroke_play: bool = false) -> void:
	lives = START_LIVES
	current_hole = 1
	deepest_hole = 1
	strokes_this_hole = 0
	total_strokes = 0
	score_to_par = 0
	net_score_to_par = 0
	hole_scores.clear()
	pure_strikes = 0
	path_miss_history.clear()
	form_history.clear()
	last_shot_metrics.clear()
	last_tempo_metrics.clear()
	run_active = true
	debug_timing_scale = null
	debug_wind_scale = null
	debug_fairway_scale = null
	debug_tempo_tol = null
	debug_balance_tighten = null
	debug_tee_set = null
	force_perfect = false
	force_mishit = false
	debug_putt_line_aim = false
	tempo_guide_forced = false
	range_mode = false
	green_mode = false
	short_game_mode = false
	stroke_play_mode = p_stroke_play
	course_seed = randi()
	_regenerate_course()
	course_handicap = _course_handicap_for_round()
	lives_changed.emit(lives)
	hole_changed.emit(current_hole)
	adaptation_changed.emit(get_adaptation_bias())
	form_changed.emit(get_form())
	pure_strikes_changed.emit(pure_strikes)


func is_stroke_play() -> bool:
	return stroke_play_mode and not in_practice()


func is_survival() -> bool:
	return not stroke_play_mode and not in_practice()


func record_pure_strike() -> void:
	pure_strikes += 1
	pure_strikes_changed.emit(pure_strikes)


func _regenerate_course() -> void:
	if course_seed == 0:
		course_seed = randi()
	course = HoleGenerator.generate_course(course_seed, course_theme, DEFAULT_HOLE_COUNT)
	HOLE_COUNT = maxi(course.size(), 1)
	var complexities: Array[float] = []
	for h in course:
		complexities.append(float(h.complexity))
	course_slope = HandicapMath.course_slope(complexities)
	stroke_index = HandicapMath.stroke_index_ranks(complexities)


func get_hole(hole_index: int) -> HoleData:
	if course.is_empty():
		_regenerate_course()
	var i := clampi(hole_index - 1, 0, course.size() - 1)
	return course[i]


func set_lives(value: int) -> void:
	lives = clampi(value, 0, MAX_LIVES)
	lives_changed.emit(lives)
	# Stroke play: lives UI is hidden and economy is inert — never end the run.
	if lives <= 0 and run_active and not stroke_play_mode and not in_practice():
		end_run("out_of_lives")


func add_lives(delta: int) -> void:
	if stroke_play_mode or in_practice():
		return
	set_lives(lives + delta)


## Apply life change for a finished hole. Returns the delta applied.
func apply_hole_result_lives(result: Scoring.Result) -> int:
	if stroke_play_mode or in_practice():
		return 0
	var delta := 0
	match result:
		Scoring.Result.ALBATROSS, Scoring.Result.EAGLE, Scoring.Result.BIRDIE:
			delta = 1
		Scoring.Result.PAR:
			delta = 0
		Scoring.Result.BOGEY:
			delta = -1
		Scoring.Result.DOUBLE_PLUS:
			delta = -2
	add_lives(delta)
	return delta


## True if this hole (1-based) receives a handicap stroke this round.
func hole_gets_stroke(hole_index: int) -> bool:
	if not is_stroke_play() or course_handicap <= 0 or stroke_index.is_empty():
		return false
	var i := clampi(hole_index - 1, 0, stroke_index.size() - 1)
	return int(stroke_index[i]) <= course_handicap


## Map rolling miss bias to hazard side for a hole.
func effective_hazard_bias(hole: HoleData) -> HoleData.HazardBias:
	var bias := get_adaptation_bias()
	if hole.hole_number >= 4:
		if bias > 0.35:
			return HoleData.HazardBias.RIGHT
		if bias < -0.35:
			return HoleData.HazardBias.LEFT
	return hole.hazard_bias


## Extra wind nudge opposing common miss (push ball toward danger they create).
func wind_adaptation_nudge() -> Vector2:
	var bias := get_adaptation_bias()
	return Vector2(bias * 12.0, 0.0)


func bias_label() -> String:
	var b := get_adaptation_bias()
	if b > 0.25:
		return "Slice bias (R)"
	if b < -0.25:
		return "Hook bias (L)"
	return "Neutral"


func begin_hole(hole_index: int) -> void:
	current_hole = clampi(hole_index, 1, HOLE_COUNT)
	deepest_hole = maxi(deepest_hole, current_hole)
	# Survival deepest PB — stroke play doesn't compete on deepest.
	if not stroke_play_mode and deepest_hole > best_deepest_hole:
		best_deepest_hole = deepest_hole
		_save_records()
	strokes_this_hole = 0
	hole_changed.emit(current_hole)


func record_stroke() -> void:
	strokes_this_hole += 1
	total_strokes += 1


func record_path_miss(path_error: float) -> void:
	path_miss_history.append(clampf(path_error, -1.0, 1.0))
	if path_miss_history.size() > 12:
		path_miss_history.pop_front()
	adaptation_changed.emit(get_adaptation_bias())


func record_shot_form(contact: ShotResult.ContactQuality, stance: float) -> void:
	var contact_score := 0.5
	match contact:
		ShotResult.ContactQuality.PERFECT:
			contact_score = 1.0
		ShotResult.ContactQuality.GOOD:
			contact_score = 0.85
		ShotResult.ContactQuality.THIN:
			contact_score = 0.45
		ShotResult.ContactQuality.FAT:
			contact_score = 0.35
		ShotResult.ContactQuality.MISS:
			contact_score = 0.15
	var score := clampf(contact_score * 0.65 + clampf(stance, 0.0, 1.0) * 0.35, 0.0, 1.0)
	form_history.append(score)
	if form_history.size() > FORM_HISTORY_MAX:
		form_history.pop_front()
	form_changed.emit(get_form())


func active_tee_set_for_hole(hole_index: int) -> HoleData.TeeSet:
	## Round progress → harder tees: early Red, mid White, late Blue.
	## Range / green practice: White. Optional debug_tee_set override.
	if debug_tee_set != null:
		return debug_tee_set as HoleData.TeeSet
	if range_mode or green_mode or short_game_mode:
		return HoleData.TeeSet.WHITE
	var t := HoleGenerator.difficulty_t(hole_index, HOLE_COUNT)
	if t < 0.33:
		return HoleData.TeeSet.RED
	if t < 0.66:
		return HoleData.TeeSet.WHITE
	return HoleData.TeeSet.BLUE


func get_form() -> float:
	## 0 = poor, 1 = sharp. Empty history starts mid-amateur (~0.45).
	if form_history.is_empty():
		return 0.45
	var sum := 0.0
	for v in form_history:
		sum += v
	return clampf(sum / float(form_history.size()), 0.0, 1.0)


## club_max_yards picks the real-world dispersion bucket for full swing (driver
## disperses far wider than a wedge); form then interpolates within that club's
## low(skilled)-high(weak) range. Chip/pitch/flop ignore the club bucket and
## scale with planned_rest_yd × shot-type band instead (short-game landing circle).
func get_aim_radius_yards(
	on_green: bool = false,
	club_max_yards: float = 0.0,
	force: float = 0.0,
	planned_rest_yd: float = 0.0,
	shot_type: String = "full",
) -> float:
	var form := get_form()
	if on_green:
		return lerpf(PUTT_RADIUS_WEAK_YD, PUTT_RADIUS_PRO_YD, form)
	if shot_type == "chip" or shot_type == "pitch" or shot_type == "flop":
		var r_short := BallPhysics.short_game_aim_radius_yards(planned_rest_yd, shot_type)
		# Sharp → table; wild → open (PLAYTEST).
		r_short *= lerpf(SHORT_AIM_FORM_WIDEN, 1.0, form)
		if force > 0.0:
			r_short *= lerpf(1.0, 1.45, clampf(force, 0.0, 1.0))
		return r_short
	var spread := BallPhysics.lateral_spread_range_yards(club_max_yards)
	var pro_yd := spread.x * 0.5  # half-width: radius, not full pattern
	var weak_yd := spread.y * 0.5
	var mid_yd := (pro_yd + weak_yd) * 0.5
	# Piecewise: weak→mid→pro
	var r: float
	if form < 0.5:
		r = lerpf(weak_yd, mid_yd, form / 0.5)
	else:
		r = lerpf(mid_yd, pro_yd, (form - 0.5) / 0.5)
	# Club-fit: forced swings open the landing circle (in-pocket force=0 → unchanged).
	if force > 0.0:
		r *= lerpf(1.0, 1.45, clampf(force, 0.0, 1.0))
	return r


func form_label() -> String:
	var f := get_form()
	if f >= 0.75:
		return "sharp"
	if f >= 0.5:
		return "steady"
	if f >= 0.3:
		return "rusty"
	return "wild"


func get_adaptation_bias() -> float:
	if path_miss_history.is_empty():
		return 0.0
	var sum := 0.0
	for v in path_miss_history:
		sum += v
	return clampf(sum / float(path_miss_history.size()), -1.0, 1.0)


func advance_hole() -> bool:
	if current_hole >= HOLE_COUNT:
		end_run("course_complete")
		return false
	begin_hole(current_hole + 1)
	return true


func end_run(reason: String) -> void:
	if not run_active:
		return
	run_active = false
	_update_records_on_end(reason)
	run_ended.emit(deepest_hole, reason)


func add_score_to_par(diff: int) -> void:
	if in_practice():
		return
	score_to_par += diff
	hole_scores.append(diff)
	var net_diff := diff
	if is_stroke_play() and hole_gets_stroke(current_hole):
		net_diff -= 1
	net_score_to_par += net_diff


static func format_score_to_par(score: int) -> String:
	if score == 0:
		return "E"
	return "%+d" % score


func handicap_index() -> Variant:
	## null if not established; else float average of best recent differentials.
	return HandicapMath.handicap_index(stroke_differentials, HCP_MIN_ROUNDS)


func handicap_label() -> String:
	var hi: Variant = handicap_index()
	if hi == null:
		return "HCP — play %d rounds" % HCP_MIN_ROUNDS
	return "HCP %.1f" % float(hi)


func _course_handicap_for_round() -> int:
	if not stroke_play_mode:
		return 0
	var hi: Variant = handicap_index()
	if hi == null:
		return 0
	return HandicapMath.course_handicap(float(hi), course_slope)


func _update_records_on_end(reason: String) -> void:
	var changed := false
	if stroke_play_mode:
		if reason == "course_complete":
			if not has_finished_stroke_round or score_to_par < best_stroke_score_to_par:
				best_stroke_score_to_par = score_to_par
				has_finished_stroke_round = true
				changed = true
			var d := HandicapMath.score_differential(score_to_par, course_slope)
			stroke_differentials.append(d)
			while stroke_differentials.size() > DIFF_HISTORY_MAX:
				stroke_differentials.pop_front()
			changed = true
	else:
		if deepest_hole > best_deepest_hole:
			best_deepest_hole = deepest_hole
			changed = true
		if reason == "course_complete":
			if not has_finished_course or score_to_par < best_score_to_par:
				best_score_to_par = score_to_par
				has_finished_course = true
				changed = true
	if changed:
		_save_records()


func practice_swing_count_for(shot_type: String) -> int:
	var key := shot_type if practice_reps.has(shot_type) else "full"
	return clampi(int(practice_reps.get(key, 0)), 0, 3)


func set_practice_swing_count(shot_type: String, v: int) -> void:
	var key := shot_type if practice_reps.has(shot_type) else "full"
	practice_reps[key] = clampi(v, 0, 3)
	_save_records()


## Stroke play / practice: real swings at this type → full guide fade (Phase 4).
const SHOT_TYPE_GUIDE_REPS := 20.0
## Novice / mastered ghost alpha (tempo pad + meter ticks share this).
const GUIDE_ALPHA_NOVICE := 0.78
const GUIDE_ALPHA_MASTERED := 0.0


func shot_type_rep_count(shot_type: String) -> int:
	return maxi(int(shot_type_reps.get(shot_type, 0)), 0)


func record_shot_type_rep(shot_type: String) -> void:
	if shot_type.is_empty():
		return
	shot_type_reps[shot_type] = shot_type_rep_count(shot_type) + 1
	_save_records()


## 0 = novice at this type (strong guide); 1 = familiar (faded guide). Not global form.
func get_shot_type_form(shot_type: String) -> float:
	return clampf(float(shot_type_rep_count(shot_type)) / SHOT_TYPE_GUIDE_REPS, 0.0, 1.0)


## 0 = start of round (strong guide); 1 = last hole (faded). Survival course progress.
func survival_guide_form() -> float:
	var n := maxi(HOLE_COUNT, 1)
	if n <= 1:
		return 0.0
	return clampf(float(current_hole - 1) / float(n - 1), 0.0, 1.0)


## Shared fade for tempo ghost + meter ticks.
func guide_alpha_for_form(form: float) -> float:
	return lerpf(GUIDE_ALPHA_NOVICE, GUIDE_ALPHA_MASTERED, clampf(form, 0.0, 1.0))


func guide_alpha_for_shot_type(shot_type: String) -> float:
	## Survival: ghost is strong on hole 1 and fades over the 18 as the course hardens.
	## Ignores lifetime shot-type reps so a new Survival run always coaches early holes.
	if is_survival() and run_active and not in_practice():
		return guide_alpha_for_form(survival_guide_form())
	# Stroke play / range practice path: per-type familiarity (Phase 4).
	return guide_alpha_for_form(get_shot_type_form(shot_type))


func _load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RECORDS_PATH) != OK:
		return
	best_score_to_par = int(cfg.get_value("records", "best_score_to_par", 0))
	best_deepest_hole = int(cfg.get_value("records", "best_deepest_hole", 0))
	has_finished_course = bool(cfg.get_value("records", "has_finished_course", false))
	best_stroke_score_to_par = int(cfg.get_value("records", "best_stroke_score_to_par", 0))
	has_finished_stroke_round = bool(cfg.get_value("records", "has_finished_stroke_round", false))
	stroke_differentials.clear()
	var raw: Variant = cfg.get_value("records", "stroke_differentials", [])
	if raw is Array:
		for v in raw:
			stroke_differentials.append(float(v))
	_load_practice_reps(cfg)
	_load_shot_type_reps(cfg)


func _load_practice_reps(cfg: ConfigFile) -> void:
	## Per-type prefs; migrate flat practice_swing_count → full (and pitch if unset).
	var defaults := {"full": 1, "pitch": 1, "chip": 0, "putt": 0, "flop": 1}
	if cfg.has_section_key("prefs", "practice_reps"):
		var raw: Variant = cfg.get_value("prefs", "practice_reps", {})
		if raw is Dictionary:
			for k in defaults.keys():
				if raw.has(k):
					defaults[k] = clampi(int(raw[k]), 0, 3)
	elif cfg.has_section_key("prefs", "practice_swing_count"):
		var old := clampi(int(cfg.get_value("prefs", "practice_swing_count", 1)), 0, 3)
		defaults["full"] = old
		defaults["pitch"] = old
	practice_reps = defaults


func _load_shot_type_reps(cfg: ConfigFile) -> void:
	shot_type_reps.clear()
	if not cfg.has_section_key("prefs", "shot_type_reps"):
		return
	var raw: Variant = cfg.get_value("prefs", "shot_type_reps", {})
	if raw is Dictionary:
		for k in raw.keys():
			shot_type_reps[str(k)] = maxi(int(raw[k]), 0)


func _save_records() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_score_to_par", best_score_to_par)
	cfg.set_value("records", "best_deepest_hole", best_deepest_hole)
	cfg.set_value("records", "has_finished_course", has_finished_course)
	cfg.set_value("records", "best_stroke_score_to_par", best_stroke_score_to_par)
	cfg.set_value("records", "has_finished_stroke_round", has_finished_stroke_round)
	var diffs: Array = []
	for d in stroke_differentials:
		diffs.append(d)
	cfg.set_value("records", "stroke_differentials", diffs)
	cfg.set_value("prefs", "practice_reps", practice_reps.duplicate())
	cfg.set_value("prefs", "shot_type_reps", shot_type_reps.duplicate())
	cfg.save(RECORDS_PATH)


func jump_to_hole(hole_index: int) -> void:
	begin_hole(hole_index)


func in_practice() -> bool:
	return range_mode or green_mode or short_game_mode


func enter_range_mode() -> void:
	green_mode = false
	short_game_mode = false
	range_mode = true
	stroke_play_mode = false
	run_active = true


func exit_range_mode() -> void:
	range_mode = false


func enter_green_mode() -> void:
	range_mode = false
	short_game_mode = false
	green_mode = true
	stroke_play_mode = false
	run_active = true


func exit_green_mode() -> void:
	green_mode = false


func enter_short_game_mode() -> void:
	range_mode = false
	green_mode = false
	short_game_mode = true
	stroke_play_mode = false
	run_active = true


func exit_short_game_mode() -> void:
	short_game_mode = false


## Leave mid-session without writing records — Menu / Restart → start screen.
func abandon_run() -> void:
	run_active = false
	range_mode = false
	green_mode = false
	short_game_mode = false

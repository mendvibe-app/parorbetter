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

## Landing circle radii (yards) from poor → sharp form.
const AIM_RADIUS_WEAK_YD := 40.0
const AIM_RADIUS_MID_YD := 22.0
const AIM_RADIUS_PRO_YD := 10.0
## Putt circle (yards) — ~3–8 feet.
const PUTT_RADIUS_WEAK_YD := 2.7
const PUTT_RADIUS_PRO_YD := 1.0

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
## Last tempo verdict (ratio, balance, ms…) for F1 readout
var last_tempo_metrics: Dictionary = {}
## Fadeable tempo guide — shows rhythm only, never widens windows.
var tempo_guide_enabled: bool = true
var tempo_guide_forced: bool = false
## Driving range — infinite tee practice, no lives / hole advance.
var range_mode: bool = false


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	lives = START_LIVES
	current_hole = 1
	deepest_hole = 1
	strokes_this_hole = 0
	total_strokes = 0
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
	force_perfect = false
	force_mishit = false
	tempo_guide_forced = false
	range_mode = false
	course_seed = randi()
	_regenerate_course()
	lives_changed.emit(lives)
	hole_changed.emit(current_hole)
	adaptation_changed.emit(get_adaptation_bias())
	form_changed.emit(get_form())
	pure_strikes_changed.emit(pure_strikes)


func record_pure_strike() -> void:
	pure_strikes += 1
	pure_strikes_changed.emit(pure_strikes)


func _regenerate_course() -> void:
	if course_seed == 0:
		course_seed = randi()
	course = HoleGenerator.generate_course(course_seed, course_theme, DEFAULT_HOLE_COUNT)
	HOLE_COUNT = maxi(course.size(), 1)


func get_hole(hole_index: int) -> HoleData:
	if course.is_empty():
		_regenerate_course()
	var i := clampi(hole_index - 1, 0, course.size() - 1)
	return course[i]


func set_lives(value: int) -> void:
	lives = clampi(value, 0, MAX_LIVES)
	lives_changed.emit(lives)
	if lives <= 0 and run_active:
		end_run("out_of_lives")


func add_lives(delta: int) -> void:
	set_lives(lives + delta)


## Apply life change for a finished hole. Returns the delta applied.
func apply_hole_result_lives(result: Scoring.Result) -> int:
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


func get_form() -> float:
	## 0 = poor, 1 = sharp. Empty history starts mid-amateur (~0.45).
	if form_history.is_empty():
		return 0.45
	var sum := 0.0
	for v in form_history:
		sum += v
	return clampf(sum / float(form_history.size()), 0.0, 1.0)


func get_aim_radius_yards(on_green: bool = false) -> float:
	var form := get_form()
	if on_green:
		return lerpf(PUTT_RADIUS_WEAK_YD, PUTT_RADIUS_PRO_YD, form)
	# Piecewise: weak→mid→pro
	if form < 0.5:
		return lerpf(AIM_RADIUS_WEAK_YD, AIM_RADIUS_MID_YD, form / 0.5)
	return lerpf(AIM_RADIUS_MID_YD, AIM_RADIUS_PRO_YD, (form - 0.5) / 0.5)


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
	run_ended.emit(deepest_hole, reason)


func jump_to_hole(hole_index: int) -> void:
	begin_hole(hole_index)


func enter_range_mode() -> void:
	range_mode = true
	run_active = true


func exit_range_mode() -> void:
	range_mode = false

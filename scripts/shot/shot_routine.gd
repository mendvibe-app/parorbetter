class_name ShotRoutine
extends Control

## Tempo swing: committed pre-shot power × gesture ratio grade.
## Single-thumb drag; desktop LMB. Practice mode grades without launching.

signal shot_ready(result: ShotResult)
signal phase_changed(phase: String)
signal pure_strike(result: ShotResult)
signal practice_result(verdict: Dictionary)

enum Phase { IDLE, ACTIVE, DONE }

const PURE_BALANCE := 0.72

var phase: Phase = Phase.IDLE
var timing_scale: float = 1.0
var suggested_shape: float = 0.0
var practice_mode: bool = false

var club_name: String = "Iron"
var club_max_yards: float = 180.0
var remaining_yards: float = 160.0
var pin_yards: float = 160.0
var current_lie: String = "Tee"
var aim_radius_yd: float = 22.0
var committed_power: float = 0.75
var shot_type: String = "full"
var last_verdict: Dictionary = {}

@onready var info_label: Label = $InfoLabel
@onready var meter_display: MeterDisplay = $MeterDisplay
@onready var tempo_gesture: TempoGesture = $Controls/TempoGesture
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	tempo_gesture.committed.connect(_on_tempo_committed)
	tempo_gesture.moment.connect(_on_tempo_moment)
	if meter_display:
		meter_display.bind(tempo_gesture)
	set_active(false)


func configure(
	lie: String,
	aim_distance_yd: float,
	pin_distance_yd: float,
	wind: Vector2,
	_shape_label: String,
	p_timing: float,
	p_shape: float = 0.0,
	p_aim_radius_yd: float = 22.0,
	p_club_name: String = "",
	p_club_max_yards: float = -1.0
) -> void:
	timing_scale = p_timing
	suggested_shape = p_shape
	current_lie = lie
	remaining_yards = aim_distance_yd
	pin_yards = pin_distance_yd
	aim_radius_yd = p_aim_radius_yd
	if GameState.debug_timing_scale != null:
		timing_scale = float(GameState.debug_timing_scale)
	timing_scale *= BallPhysics.lie_timing_scale(lie)

	if p_club_max_yards > 0.0 and not p_club_name.is_empty():
		club_name = p_club_name
		club_max_yards = p_club_max_yards
	else:
		var club := BallPhysics.pick_club(pin_distance_yd, lie)
		club_name = String(club["name"])
		club_max_yards = float(club["max_yards"])

	committed_power = BallPhysics.recommended_power(aim_distance_yd, club_max_yards, lie, wind)
	shot_type = TempoGrade.shot_type_for(lie, club_name, aim_distance_yd)

	var wind_str := "Wind %d %s" % [int(wind.length()), _wind_dir(wind)]
	var ratio_t := TempoGrade.target_ratio(shot_type)
	info_label.text = "%s  ·  Aim %d yd (pin %d)  ·  %s @ %d%%  ·  %s  ·  Tempo ~%.0f:1" % [
		lie, int(aim_distance_yd), int(pin_distance_yd), club_name,
		int(committed_power * 100.0), wind_str, ratio_t
	]


func begin_shot(p_practice: bool = false) -> void:
	practice_mode = p_practice
	phase = Phase.ACTIVE
	last_verdict.clear()
	tempo_gesture.reset()
	tempo_gesture.set_enabled(true)
	if meter_display:
		meter_display.set_shot_context(shot_type, timing_scale, practice_mode)
	if practice_mode:
		hint_label.text = "PRACTICE — press START · pull UP · pause · drag back through the gold."
	elif shot_type == "putt":
		hint_label.text = "PUTT ~2:1 — press START · pull UP slowly · through the gold."
	elif shot_type == "chip":
		hint_label.text = "CHIP ~2:1 — press START · pull UP · through the gold."
	else:
		hint_label.text = "SWING ~3:1 — press START · pull UP (~3 beats) · through (~1 beat)."
	phase_changed.emit("active")
	set_active(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if info_label:
		info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint_label:
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if meter_display:
		meter_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter_display.queue_redraw()
	var bg := get_node_or_null("PanelBG") as Control
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controls := get_node_or_null("Controls") as Control
	if controls:
		controls.mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_active(on: bool) -> void:
	visible = on
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func force_result(perfect: bool) -> void:
	var contact := ShotResult.ContactQuality.PERFECT if perfect else ShotResult.ContactQuality.FAT
	var path := 0.0 if perfect else 0.65
	var stab := 1.0 if perfect else 0.35
	var power_amt := committed_power if perfect else committed_power * 0.55
	_emit_result(ShotResult.make(power_amt, stab, path, contact, suggested_shape))


func _on_tempo_moment(name: String) -> void:
	if meter_display:
		meter_display.on_moment(name)
	match name:
		"top":
			Input.vibrate_handheld(8)
		"impact":
			pass  # thump intensity decided at commit from contact tier


func _on_tempo_committed(sample: Dictionary) -> void:
	if phase != Phase.ACTIVE:
		return

	var tol_scale := 1.0
	if GameState.debug_tempo_tol != null:
		tol_scale = float(GameState.debug_tempo_tol)
	var bal_tighten := 1.0
	if GameState.debug_balance_tighten != null:
		bal_tighten = float(GameState.debug_balance_tighten)

	var verdict := TempoGrade.grade(sample, shot_type, timing_scale, tol_scale, bal_tighten)
	last_verdict = verdict
	GameState.last_tempo_metrics = verdict

	if GameState.force_perfect:
		verdict = {
			"ratio": TempoGrade.target_ratio(shot_type),
			"target": TempoGrade.target_ratio(shot_type),
			"balance": 1.0,
			"contact": ShotResult.ContactQuality.PERFECT,
			"power_mul": 1.0,
			"path_error": 0.0,
			"note": "Tempo forced perfect",
			"backswing_ms": 750,
			"downswing_ms": 250,
		}
		last_verdict = verdict
	elif GameState.force_mishit:
		verdict = {
			"ratio": 1.2,
			"target": TempoGrade.target_ratio(shot_type),
			"balance": 0.25,
			"contact": ShotResult.ContactQuality.FAT,
			"power_mul": 0.55,
			"path_error": 0.8,
			"note": "Tempo forced mishit",
			"backswing_ms": 200,
			"downswing_ms": 180,
		}
		last_verdict = verdict

	var contact: ShotResult.ContactQuality = verdict["contact"]
	var bal: float = float(verdict["balance"])
	var path: float = float(verdict["path_error"])
	var power := clampf(committed_power * float(verdict["power_mul"]), 0.05, 1.0)

	# Putts: path hurts more (same as old routine)
	if current_lie == "Green":
		path = clampf(path * 1.35, -1.0, 1.0)

	_haptic_impact(contact)

	if practice_mode:
		hint_label.text = str(verdict.get("note", "Practice swing"))
		if meter_display:
			meter_display.show_verdict(verdict)
		phase = Phase.DONE
		tempo_gesture.set_enabled(false)
		practice_result.emit(verdict)
		return

	_emit_result(ShotResult.make(power, bal, path, contact, suggested_shape))


func _haptic_impact(contact: ShotResult.ContactQuality) -> void:
	match contact:
		ShotResult.ContactQuality.PERFECT:
			Input.vibrate_handheld(18)
		ShotResult.ContactQuality.GOOD:
			Input.vibrate_handheld(12)
		ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
			Input.vibrate_handheld(6)
		_:
			Input.vibrate_handheld(4)


func _emit_result(result: ShotResult) -> void:
	phase = Phase.DONE
	tempo_gesture.set_enabled(false)
	set_active(false)
	GameState.record_path_miss(result.path_error)
	GameState.record_shot_form(result.contact_quality, result.stance_stability)
	phase_changed.emit("done")
	if result.is_perfect() and result.stance_stability >= PURE_BALANCE:
		pure_strike.emit(result)
	shot_ready.emit(result)


func _wind_dir(wind: Vector2) -> String:
	var full := AimControl.wind_label(wind)
	return full.replace("Wind ", "")

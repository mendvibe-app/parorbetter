class_name ShotRoutine
extends Control

## Concurrent dual-touch shot: finger 1 (power/stance) + finger 2 (swing timing)
## stay live together; impact tap resolves with live values.
## Desktop: LMB drag power; RMB / Space for swing start+impact.

signal shot_ready(result: ShotResult)
signal phase_changed(phase: String)
signal pure_strike(result: ShotResult)

enum Phase { IDLE, ACTIVE, DONE }

var phase: Phase = Phase.IDLE
var timing_scale: float = 1.0
var suggested_shape: float = 0.0
var _power: float = 0.45
var _stability: float = 1.0
var _path: float = 0.0
var _contact: ShotResult.ContactQuality = ShotResult.ContactQuality.GOOD

var club_name: String = "Iron"
var club_max_yards: float = 180.0
var remaining_yards: float = 160.0
var pin_yards: float = 160.0
var current_lie: String = "Tee"
var aim_radius_yd: float = 22.0

@onready var info_label: Label = $InfoLabel
@onready var power_stance: PowerStance = $Controls/PowerStance
@onready var swing_contact: SwingContact = $Controls/SwingContact
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	# committed = finger-1 released (early-release feedback only; impact still resolves)
	power_stance.committed.connect(_on_power_released)
	power_stance.updated.connect(_on_power_updated)
	swing_contact.committed.connect(_on_swing_committed)
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
	var recommend := BallPhysics.recommended_power(aim_distance_yd, club_max_yards, lie, wind)
	power_stance.setup_yardage(club_name, club_max_yards, aim_distance_yd, lie, recommend)
	power_stance.set_timing_scale(timing_scale)

	var wind_str := "Wind %d %s" % [int(wind.length()), _wind_dir(wind)]
	info_label.text = "%s  ·  Aim %d yd (pin %d)  ·  %s  ·  %s  ·  Circle %d yd" % [
		lie, int(aim_distance_yd), int(pin_distance_yd), club_name, wind_str, int(aim_radius_yd)
	]


func begin_shot() -> void:
	phase = Phase.ACTIVE
	_power = power_stance.power
	_stability = 0.35
	power_stance.reset()
	power_stance.set_enabled(true)
	var is_putt := current_lie == "Green"
	swing_contact.reset(timing_scale, is_putt)
	swing_contact.set_enabled(true)
	# ponytail: arc starts on first finger-2 tap (not shot-begin); auto-sweep on begin if takeaway feel needs it
	if is_putt:
		hint_label.text = "Hold lean + power · PUTT — tap arc to start, tap yellow BOTTOM at impact."
	else:
		hint_label.text = "Hold lean + power · Swing — tap arc to start, tap yellow BOTTOM at impact."
	phase_changed.emit("active")
	set_active(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if info_label:
		info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint_label:
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var power_amt := power_stance.recommend_power if perfect else 0.55
	_emit_result(ShotResult.make(power_amt, stab, path, contact, suggested_shape))


func _on_power_updated(power: float, stability: float) -> void:
	_power = power
	_stability = stability


func _on_power_released(_power_amt: float, _stability_amt: float) -> void:
	## Soft early-release: stability already crushed in PowerStance; swing stays live.
	if phase != Phase.ACTIVE:
		return
	if power_stance.balance_broken:
		_stability = power_stance.stability
		hint_label.text = "Balance broken — finish the swing (stability crushed)."


func _on_swing_committed(path_error: float, contact: ShotResult.ContactQuality) -> void:
	# Resolve from live finger-1 state at impact — not values frozen earlier.
	_power = power_stance.power
	_stability = power_stance.stability
	_path = path_error
	_contact = contact

	# Forced swings (mash/baby) can't claim a pure strike — take the right club instead.
	if current_lie != "Green":
		var force := BallPhysics.force_factor(_power)
		if force > 0.0:
			_stability *= lerpf(1.0, 0.55, force)
			_path += signf(_path if absf(_path) > 0.05 else 1.0) * force * 0.22
			_path = clampf(_path, -1.0, 1.0)

	# Stance aggressively gates "perfect" — rare and earned
	if _contact == ShotResult.ContactQuality.PERFECT:
		if _stability < 0.72:
			_contact = ShotResult.ContactQuality.GOOD
		if _stability < 0.5:
			_contact = ShotResult.ContactQuality.THIN if _path >= 0.0 else ShotResult.ContactQuality.FAT
	elif _contact == ShotResult.ContactQuality.GOOD and _stability < 0.4:
		_contact = ShotResult.ContactQuality.THIN if _path >= 0.0 else ShotResult.ContactQuality.FAT

	if _stability < 0.35:
		_path += signf(_path if absf(_path) > 0.05 else 1.0) * (0.45 - _stability)
		_path = clampf(_path, -1.0, 1.0)

	# Putts: path error hurts more
	if current_lie == "Green":
		_path *= 1.35
		_path = clampf(_path, -1.0, 1.0)

	if GameState.force_perfect:
		_emit_result(ShotResult.make(power_stance.recommend_power, 1.0, 0.0, ShotResult.ContactQuality.PERFECT, suggested_shape))
		return
	if GameState.force_mishit:
		_emit_result(ShotResult.make(_power, 0.25, 0.8, ShotResult.ContactQuality.FAT, suggested_shape))
		return

	_emit_result(ShotResult.make(_power, _stability, _path, _contact, suggested_shape))


func _emit_result(result: ShotResult) -> void:
	phase = Phase.DONE
	power_stance.set_enabled(false)
	swing_contact.set_enabled(false)
	set_active(false)
	GameState.record_path_miss(result.path_error)
	GameState.record_shot_form(result.contact_quality, result.stance_stability)
	phase_changed.emit("done")
	if result.is_perfect() and result.stance_stability >= 0.72:
		pure_strike.emit(result)
	shot_ready.emit(result)


func _wind_dir(wind: Vector2) -> String:
	var full := AimControl.wind_label(wind)
	return full.replace("Wind ", "")

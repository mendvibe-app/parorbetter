class_name PowerStance
extends Control

## Finger 1 (power + stance) — mobile: hold/drag; desktop: LMB drag.
## Touch pad only; meter arcs render on MeterDisplay.

signal committed(power: float, stability: float)
signal updated(power: float, stability: float)

const TRACK_HISTORY := 0.4
const DWELL_REQUIRED := 0.28
const IN_ZONE_THRESH := 0.22
const POWER_IN_ZONE := 0.07
const DEFAULT_START_POWER := 0.75
## Soft early-release: crush + sticky cap so re-grab can't fully recover before impact.
## ponytail: playtest tunables (leave until device feel says otherwise) —
## hard mishit on release if CEIL still feels too soft; raise MUL if crush is too gentle
const EARLY_RELEASE_STAB_MUL := 0.45
const EARLY_RELEASE_STAB_CEIL := 0.32

var active: bool = false
var dragging: bool = false
var power: float = DEFAULT_START_POWER
var stability: float = 0.5
var timing_scale: float = 1.0
## True after finger-1 lifts before impact; sticky until reset().
var balance_broken: bool = false

var _start_pos: Vector2 = Vector2.ZERO
var _drag_origin_power: float = DEFAULT_START_POWER
var _player_x: float = 0.5
var _target_x: float = 0.5
var _dwell: float = 0.0
var _track_samples: Array[float] = []
var _power_samples: Array[float] = []
var _sample_timer: float = 0.0
var _sway_phase: float = 0.0
## Radians/sec — locked to swing arc; one lean cycle per HALF_SWEEPS_PER_LEAN half-sweeps.
## ponytail: was TAU (1:1 half-sweep) — too fast to track; 4 ≈ old learnable pace. Try 2 if too slow.
const HALF_SWEEPS_PER_LEAN := 4.0
var _sway_speed: float = TAU * 1.25 / HALF_SWEEPS_PER_LEAN
## Remember last committed power so the next shot doesn't start on the answer.
static var last_power: float = DEFAULT_START_POWER

var club_name: String = "Iron"
var club_max_yards: float = 180.0
var remaining_yards: float = 160.0
var lie: String = "Fairway"
var recommend_power: float = 1.0

@onready var label: Label = $Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	if label:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_visuals()


func setup_yardage(p_club_name: String, p_club_max: float, p_remaining: float, p_lie: String, p_recommend: float) -> void:
	club_name = p_club_name
	club_max_yards = p_club_max
	remaining_yards = p_remaining
	lie = p_lie
	recommend_power = clampf(p_recommend, 0.05, 1.0)
	# Neutral start — player must work toward the white tick, not inherit the answer.
	power = clampf(last_power, 0.05, 1.0)
	_refresh_visuals()


func set_timing_scale(p_scale: float) -> void:
	timing_scale = maxf(0.4, p_scale)


func set_sway_from_arc_speed(arc_speed: float) -> void:
	## Lean period = HALF_SWEEPS_PER_LEAN / arc_speed (still integer-ratio locked to the arc).
	_sway_speed = TAU * maxf(arc_speed, 0.35) / HALF_SWEEPS_PER_LEAN


func reset() -> void:
	active = true
	dragging = false
	balance_broken = false
	power = clampf(last_power, 0.05, 1.0)
	_drag_origin_power = power
	stability = 0.35
	_player_x = 0.5
	_target_x = 0.5
	_dwell = 0.0
	_track_samples.clear()
	_power_samples.clear()
	_sample_timer = 0.0
	_sway_phase = randf() * TAU
	set_process(true)
	_refresh_visuals()


func set_enabled(on: bool) -> void:
	active = on
	dragging = false
	modulate.a = 1.0 if on else 0.45
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	set_process_input(on)
	set_process(on)
	queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	# Clean learnable sine — speed set from swing arc in ShotRoutine (rhythm sync).
	_sway_phase += delta * _sway_speed
	var drift := sin(_sway_phase) * 0.38
	_target_x = clampf(0.5 + drift, 0.08, 0.92)

	if dragging:
		_sample_timer += delta
		if _sample_timer >= 0.05:
			_sample_timer = 0.0
			_track_samples.append(absf(_player_x - _target_x))
			_power_samples.append(absf(power - recommend_power))
			var cap := int(TRACK_HISTORY / 0.05)
			while _track_samples.size() > cap:
				_track_samples.pop_front()
			while _power_samples.size() > cap:
				_power_samples.pop_front()
		_recompute_stability()
		var lean_ok := absf(_player_x - _target_x) <= IN_ZONE_THRESH
		var power_ok := absf(power - recommend_power) <= POWER_IN_ZONE
		if lean_ok and power_ok:
			_dwell += delta
		else:
			_dwell = maxf(_dwell - delta * 1.5, 0.0)

	# Always emit so MeterDisplay tracks live lean target even before finger-1 down.
	updated.emit(power, stability)
	_refresh_visuals()


func _accept_mouse() -> bool:
	## On phones, Godot also emits emulated mouse for each touch — ignore those.
	return not DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_UP, KEY_W:
				power = clampf(power + 0.04, 0.05, 1.0)
				_player_x = clampf(_player_x + randf_range(-0.04, 0.04), 0.0, 1.0)
				_force_sample_error()
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				power = clampf(power - 0.04, 0.05, 1.0)
				_player_x = clampf(_player_x + randf_range(-0.04, 0.04), 0.0, 1.0)
				_force_sample_error()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_player_x = clampf(_player_x - 0.06, 0.0, 1.0)
				dragging = true
				_force_sample_error()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_player_x = clampf(_player_x + 0.06, 0.0, 1.0)
				dragging = true
				_force_sample_error()
				get_viewport().set_input_as_handled()
			# Space/Enter belong to swing impact under concurrent dual-input — don't steal them.
		return

	# Prefer real touch; skip emulated mouse on touchscreens.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local: Vector2 = _to_local(touch.position)
		if touch.pressed and _rect_has_point(local):
			_begin(local)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and dragging:
			_try_commit()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and dragging:
		var drag := event as InputEventScreenDrag
		_update(_to_local(drag.position))
		get_viewport().set_input_as_handled()
		return

	if not _accept_mouse():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _mouse_over_self():
				_begin(get_local_mouse_position())
				get_viewport().set_input_as_handled()
		elif dragging:
			_try_commit()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and dragging:
		_update(get_local_mouse_position())
		get_viewport().set_input_as_handled()


func _force_sample_error() -> void:
	_track_samples.append(absf(_player_x - _target_x))
	_power_samples.append(absf(power - recommend_power))
	var cap := int(TRACK_HISTORY / 0.05)
	while _track_samples.size() > cap:
		_track_samples.pop_front()
	while _power_samples.size() > cap:
		_power_samples.pop_front()
	_recompute_stability()
	updated.emit(power, stability)
	queue_redraw()


func _mouse_over_self() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


func _rect_has_point(local: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local)


func _to_local(screen_pos: Vector2) -> Vector2:
	return screen_pos - global_position


func _begin(pos: Vector2) -> void:
	dragging = true
	_start_pos = pos
	_drag_origin_power = power
	_dwell = 0.0
	_update(pos)


func _update(pos: Vector2) -> void:
	var delta := pos - _start_pos
	power = clampf((-delta.y) / maxf(size.y * 0.85, 80.0) + _drag_origin_power, 0.05, 1.0)
	_player_x = clampf(pos.x / maxf(size.x, 1.0), 0.0, 1.0)
	_recompute_stability()
	updated.emit(power, stability)
	queue_redraw()


func _recompute_stability() -> void:
	var lean_err := absf(_player_x - _target_x)
	if not _track_samples.is_empty():
		var sum := 0.0
		for e in _track_samples:
			sum += e
		lean_err = sum / float(_track_samples.size())
	var lean_stab := clampf(1.0 - lean_err / 0.42, 0.0, 1.0)

	var power_err := absf(power - recommend_power)
	if not _power_samples.is_empty():
		var psum := 0.0
		for e in _power_samples:
			psum += e
		power_err = psum / float(_power_samples.size())
	var power_stab := clampf(1.0 - power_err / 0.28, 0.0, 1.0)

	stability = clampf(lean_stab * 0.55 + power_stab * 0.45, 0.0, 1.0)
	if balance_broken:
		stability = minf(stability, EARLY_RELEASE_STAB_CEIL)


func _try_commit() -> void:
	## End finger-1 drag only — does not resolve the shot (impact tap does).
	if not active:
		return
	if _track_samples.size() < 3:
		stability = minf(stability, 0.25)
	elif _dwell < DWELL_REQUIRED and stability > 0.55:
		stability *= 0.75
	dragging = false
	# Soft early-release: significant stability damage, swing can still finish.
	if not balance_broken:
		balance_broken = true
		stability = minf(stability * EARLY_RELEASE_STAB_MUL, EARLY_RELEASE_STAB_CEIL)
	else:
		stability = minf(stability, EARLY_RELEASE_STAB_CEIL)
	last_power = power
	_refresh_visuals()
	# Emitted for UI/listeners; ShotRoutine does not resolve the shot here.
	committed.emit(power, stability)


func _refresh_visuals() -> void:
	if label:
		var force := BallPhysics.force_factor(power)
		var force_note := "  FORCED" if force > 0.35 else ""
		label.text = "POWER  %d%%\nStab %d%%%s" % [int(power * 100.0), int(stability * 100.0), force_note]
	queue_redraw()


func _draw() -> void:
	# Touch pad only — arcs live on MeterDisplay above thumbs.
	var r := Rect2(Vector2.ZERO, size).grow(-6.0)
	draw_rect(r, Color(0.1, 0.16, 0.12, 0.55), false, 2.0)
	if dragging:
		draw_circle(Vector2(size.x * _player_x, size.y * (1.0 - power)), 10.0, Color(0.4, 0.9, 0.5, 0.7))

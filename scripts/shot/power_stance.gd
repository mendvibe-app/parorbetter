class_name PowerStance
extends Control

## Finger 1 (power + stance) — mobile: hold/drag; desktop: LMB drag.
## Drawn as a tempo arc (power) + lean rail (track gold). Mechanics unchanged.

signal committed(power: float, stability: float)
signal updated(power: float, stability: float)

const TRACK_HISTORY := 0.4
const DWELL_REQUIRED := 0.28
const IN_ZONE_THRESH := 0.22
const POWER_IN_ZONE := 0.07
const DEFAULT_START_POWER := 0.75

var active: bool = false
var dragging: bool = false
var power: float = DEFAULT_START_POWER
var stability: float = 0.5
var timing_scale: float = 1.0

var _start_pos: Vector2 = Vector2.ZERO
var _drag_origin_power: float = DEFAULT_START_POWER
var _player_x: float = 0.5
var _target_x: float = 0.5
var _dwell: float = 0.0
var _track_samples: Array[float] = []
var _power_samples: Array[float] = []
var _sample_timer: float = 0.0
var _sway_phase: float = 0.0
var _noise_phase: float = 0.0
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


func reset() -> void:
	active = true
	dragging = false
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
	_noise_phase = randf() * TAU
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
	var speed := lerpf(2.2, 1.1, clampf(timing_scale, 0.4, 1.2))
	_sway_phase += delta * speed
	_noise_phase += delta * (0.7 + speed * 0.3)
	var drift := sin(_sway_phase) * 0.38 + sin(_noise_phase * 1.7) * 0.18
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
	power = clampf((-delta.y) / 220.0 + _drag_origin_power, 0.05, 1.0)
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


func _try_commit() -> void:
	## End finger-1 drag only — does not resolve the shot (impact tap does).
	if not active:
		return
	if _track_samples.size() < 3:
		stability = minf(stability, 0.25)
	elif _dwell < DWELL_REQUIRED and stability > 0.55:
		stability *= 0.75
	dragging = false
	last_power = power
	_refresh_visuals()
	# Still emitted for listeners; ShotRoutine no longer treats this as phase resolve.
	committed.emit(power, stability)


func _refresh_visuals() -> void:
	if label:
		var est := BallPhysics.estimate_carry_yards(power, club_max_yards, lie)
		var delta_yd := est - remaining_yards
		var fit := "ON TARGET"
		if delta_yd > 8.0:
			fit = "LONG %+d" % int(delta_yd)
		elif delta_yd < -8.0:
			fit = "SHORT %d" % int(delta_yd)
		var lock := "LOCK %.0f%%" % clampf(_dwell / DWELL_REQUIRED * 100.0, 0.0, 100.0)
		var force := BallPhysics.force_factor(power)
		var force_note := ""
		if force > 0.35:
			force_note = "\nFORCED SWING — line suffers"
		label.text = "%s  (max %d yd)\nHold white tick → %d%% for %d yd\nNOW %d%% ≈ %d yd  %s\nLean + power  Stability %d%%\n%s%s" % [
			club_name,
			int(club_max_yards),
			int(recommend_power * 100.0),
			int(remaining_yards),
			int(power * 100.0),
			int(est),
			fit,
			int(stability * 100.0),
			lock,
			force_note,
		]
	queue_redraw()


func _draw() -> void:
	var t_rect: Rect2 = ArcMeters.tempo_rect(size)
	var l_rect: Rect2 = ArcMeters.lean_rect(size)

	# Tempo track
	var track: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, 0.0, 1.0, 36)
	ArcMeters.draw_thick_polyline(self, track, Color(0.12, 0.18, 0.14, 0.95), 16.0)
	ArcMeters.draw_thick_polyline(self, track, Color(0.22, 0.32, 0.24, 0.9), 10.0)

	# Power fill along arc
	var fill_c: Color = Color(0.35, 0.85, 0.45).lerp(Color(0.95, 0.85, 0.2), power)
	if power > 0.92:
		fill_c = Color(0.95, 0.4, 0.25)
	var fill: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, 0.0, power, 28)
	ArcMeters.draw_thick_polyline(self, fill, fill_c, 12.0)

	# Recommend tick
	var rec_p: Vector2 = ArcMeters.tempo_point(t_rect, recommend_power)
	var rec_a: float = ArcMeters.tempo_angle(recommend_power)
	var radial: Vector2 = Vector2(cos(rec_a), -sin(rec_a))
	draw_line(rec_p - radial * 10.0, rec_p + radial * 14.0, Color(1, 1, 1, 0.95), 3.0, true)

	# Lock arc near tip of power
	var lock_t: float = clampf(_dwell / DWELL_REQUIRED, 0.0, 1.0)
	if lock_t > 0.02:
		var lock_pts: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, maxf(power - 0.08, 0.0), power, 10)
		ArcMeters.draw_thick_polyline(self, lock_pts, Color(0.95, 0.9, 0.4, 0.35 + 0.55 * lock_t), 6.0)

	# Power tip ball
	var tip: Vector2 = ArcMeters.tempo_point(t_rect, power)
	draw_circle(tip, 8.0, fill_c)
	draw_arc(tip, 8.0, 0.0, TAU, 20, Color(0.05, 0.08, 0.05, 0.8), 2.0, true)

	# Lean rail
	var lean: PackedVector2Array = ArcMeters.lean_polyline(l_rect, 24)
	ArcMeters.draw_thick_polyline(self, lean, Color(0.14, 0.2, 0.16, 0.95), 14.0)
	ArcMeters.draw_thick_polyline(self, lean, Color(0.25, 0.35, 0.28, 0.85), 8.0)

	# Gold target notch
	var tgt: Vector2 = ArcMeters.lean_point(l_rect, _target_x)
	var gold_a: float = 0.45 + 0.45 * clampf(_dwell / DWELL_REQUIRED, 0.0, 1.0)
	draw_circle(tgt, 11.0, Color(1.0, 0.85, 0.2, gold_a))
	draw_arc(tgt, 14.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.35, gold_a), 2.5, true)

	# Player lean needle
	var ply: Vector2 = ArcMeters.lean_point(l_rect, _player_x)
	var needle_c: Color = Color(0.3, 0.9, 0.5).lerp(Color(0.95, 0.3, 0.25), 1.0 - stability)
	draw_circle(ply, 7.0, needle_c)
	draw_line(ply + Vector2(0, -16), ply + Vector2(0, 16), needle_c, 3.0, true)

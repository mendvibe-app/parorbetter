class_name SwingContact
extends Control

## Finger 2: timing along a golf swing arc (backswing -> impact -> follow-through).
## Touch pad only; arc renders on MeterDisplay. Impact at bottom of the arc.

signal committed(path_error: float, contact: ShotResult.ContactQuality)
signal updated(path_error: float, marker_pos: float)

var active: bool = false
var swinging: bool = false
var path_error: float = 0.0
var marker_pos: float = 0.0
var timing_scale: float = 1.0
var putt_mode: bool = false
var _direction: float = 1.0
var _speed: float = 1.15

@onready var label: Label = $Label


static func arc_speed_for(p_timing_scale: float, p_putt: bool) -> float:
	var ts := clampf(p_timing_scale, 0.35, 1.2)
	if p_putt:
		return lerpf(1.35, 0.75, ts)
	return lerpf(2.7, 1.25, ts)


func arc_speed() -> float:
	return _speed


func sweet_half() -> float:
	return _sweet_half()


func good_half() -> float:
	return _good_half()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	set_process_input(false)
	if label:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_visuals()


func reset(p_timing_scale: float = 1.0, p_putt: bool = false) -> void:
	timing_scale = maxf(0.35, p_timing_scale)
	putt_mode = p_putt
	active = true
	swinging = false
	path_error = 0.0
	marker_pos = 0.05
	_direction = 1.0
	_speed = arc_speed_for(timing_scale, putt_mode)
	_refresh_visuals()
	set_process(false)
	updated.emit(path_error, marker_pos)


func set_enabled(on: bool) -> void:
	active = on
	if not on:
		swinging = false
		set_process(false)
	modulate.a = 1.0 if on else 0.45
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	set_process_input(on)
	queue_redraw()


func _sweet_half() -> float:
	return (0.045 if not putt_mode else 0.032) * timing_scale


func _good_half() -> float:
	return (0.10 if not putt_mode else 0.07) * timing_scale


func _process(delta: float) -> void:
	if not swinging:
		return
	marker_pos += _direction * _speed * delta
	if marker_pos >= 1.0:
		marker_pos = 1.0
		_direction = -1.0
	elif marker_pos <= 0.0:
		marker_pos = 0.0
		_direction = 1.0
	path_error = (marker_pos - 0.5) * 2.0
	_refresh_visuals()
	updated.emit(path_error, marker_pos)


func _accept_mouse() -> bool:
	## On phones, Godot also emits emulated mouse for each touch — ignore those.
	return not DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not active:
		return

	var trigger := false
	if event is InputEventScreenTouch and event.pressed:
		var touch := event as InputEventScreenTouch
		var local: Vector2 = touch.position - global_position
		if Rect2(Vector2.ZERO, size).has_point(local):
			trigger = true
	elif event is InputEventMouseButton and event.pressed and _accept_mouse():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			trigger = true
		elif event.button_index == MOUSE_BUTTON_LEFT and get_global_rect().has_point(get_global_mouse_position()):
			trigger = true
	elif event.is_action_pressed("confirm_shot"):
		trigger = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_F:
			trigger = true

	if not trigger:
		return

	if not swinging:
		_start_swing()
	else:
		_impact()
	get_viewport().set_input_as_handled()


func _start_swing() -> void:
	if swinging:
		return
	swinging = true
	marker_pos = 0.0
	_direction = 1.0
	set_process(true)
	_refresh_visuals()


func _impact() -> void:
	if not swinging:
		return
	swinging = false
	set_process(false)
	path_error = (marker_pos - 0.5) * 2.0
	var contact := _grade_contact(marker_pos)
	_refresh_visuals()
	committed.emit(path_error, contact)


func _grade_contact(pos: float) -> ShotResult.ContactQuality:
	var dist := absf(pos - 0.5)
	var sweet_half := _sweet_half()
	var good_half := _good_half()
	var ok_half := (0.20 if not putt_mode else 0.14) * timing_scale
	if dist <= sweet_half:
		return ShotResult.ContactQuality.PERFECT
	if dist <= good_half:
		return ShotResult.ContactQuality.GOOD
	if dist <= ok_half:
		if pos > 0.5:
			return ShotResult.ContactQuality.THIN
		return ShotResult.ContactQuality.FAT
	return ShotResult.ContactQuality.MISS


func _refresh_visuals() -> void:
	if label:
		var kind := "PUTT" if putt_mode else "SWING"
		if swinging:
			label.text = "%s\nTap yellow BOTTOM" % kind
		else:
			label.text = "%s\nTap to start" % kind
	queue_redraw()


func _draw() -> void:
	# Touch pad only — swing arc lives on MeterDisplay above thumbs.
	var r := Rect2(Vector2.ZERO, size).grow(-6.0)
	draw_rect(r, Color(0.1, 0.16, 0.12, 0.55), false, 2.0)
	if swinging:
		draw_circle(size * 0.5, 8.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0, Color(1.0, 0.9, 0.3, 0.45))

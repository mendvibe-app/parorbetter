class_name SwingContact
extends Control

## Finger 2: timing along a golf swing arc (backswing -> impact -> follow-through).
## Impact / sweet spot at the bottom of the arc. Mechanics unchanged.

signal committed(path_error: float, contact: ShotResult.ContactQuality)
signal updated(path_error: float, marker_pos: float)

const MARKER_TEX := preload("res://assets/ui/swing_marker.png")

var active: bool = false
var swinging: bool = false
var path_error: float = 0.0
var marker_pos: float = 0.0
var timing_scale: float = 1.0
var putt_mode: bool = false
var _direction: float = 1.0
var _speed: float = 1.15

@onready var label: Label = $Label


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
	if putt_mode:
		_speed = lerpf(1.35, 0.75, clampf(timing_scale, 0.35, 1.2))
	else:
		_speed = lerpf(2.7, 1.25, clampf(timing_scale, 0.35, 1.2))
	_refresh_visuals()
	set_process(false)


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
			label.text = "%s  path %+0.2f\nTap yellow at the BOTTOM" % [kind, path_error]
		else:
			label.text = "%s  path %+0.2f\nTap to start the arc" % [kind, path_error]
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = ArcMeters.swing_rect(size)
	var sweet_h: float = _sweet_half()
	var good_h: float = _good_half()

	# Full swing track
	var track: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.0, 1.0, 40)
	ArcMeters.draw_thick_polyline(self, track, Color(0.12, 0.18, 0.16, 0.95), 18.0)
	ArcMeters.draw_thick_polyline(self, track, Color(0.2, 0.28, 0.24, 0.9), 12.0)

	# Good zone around impact
	var good: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.5 - good_h, 0.5 + good_h, 18)
	ArcMeters.draw_thick_polyline(self, good, Color(0.35, 0.55, 0.3, 0.85), 14.0)

	# Sweet / impact at bottom
	var sweet: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.5 - sweet_h, 0.5 + sweet_h, 12)
	ArcMeters.draw_thick_polyline(self, sweet, Color(0.95, 0.85, 0.25, 0.95), 16.0)

	# Impact tick at exact bottom
	var impact: Vector2 = ArcMeters.swing_point(rect, 0.5)
	draw_line(impact + Vector2(0, -10), impact + Vector2(0, 14), Color(1.0, 0.95, 0.4, 0.9), 3.0, true)

	# Ends of the arc
	var back: Vector2 = ArcMeters.swing_point(rect, 0.02)
	var follow: Vector2 = ArcMeters.swing_point(rect, 0.98)
	draw_circle(back, 4.0, Color(0.7, 0.75, 0.7, 0.7))
	draw_circle(follow, 4.0, Color(0.7, 0.75, 0.7, 0.7))

	# Clubhead marker — needle sprite aligned with the arc's radial direction
	var m: Vector2 = ArcMeters.swing_point(rect, marker_pos)
	var a: float = ArcMeters.swing_angle(marker_pos)
	var mh := 72.0
	var mw := mh * float(MARKER_TEX.get_width()) / float(MARKER_TEX.get_height())
	draw_set_transform(m, a + PI / 2.0, Vector2.ONE)
	draw_texture_rect(MARKER_TEX, Rect2(Vector2(-mw / 2.0, -mh / 2.0), Vector2(mw, mh)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if swinging:
		draw_circle(impact, 5.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0, Color(1.0, 0.9, 0.3, 0.35))

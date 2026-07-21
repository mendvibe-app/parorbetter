class_name TempoGesture
extends Control

## Single-thumb swing drag: takeaway → top (reversal) → impact (cross address).
## Emits sample with timestamps + balance raw signals. Desktop: LMB drag.

signal committed(sample: Dictionary)
signal moment(name: String)  ## "takeaway" | "top" | "impact"
signal trail_updated(points: PackedVector2Array)

## Feel-test: if true, finger release after top counts as impact (Golden-Tee flick).
static var RELEASE_IS_IMPACT: bool = false

const DEADZONE_FRAC := 0.10  ## of pad min-dimension
const EMA_ALPHA := 0.35
const VEL_TOP_EPS := 40.0  ## px/s along axis — near-zero = top
const IMPACT_CROSS_FRAC := 0.12  ## back through address band
const MIN_BACKSWING_FRAC := 0.14

var active: bool = false
var dragging: bool = false
var swinging: bool = false  ## takeaway confirmed
var trail: PackedVector2Array = PackedVector2Array()

var _touch_index: int = -1
var _address: Vector2 = Vector2.ZERO
var _smoothed: Vector2 = Vector2.ZERO
var _axis: Vector2 = Vector2.ZERO  ## unit backswing direction (from address)
var _axis_locked: bool = false
var _disp: float = 0.0
var _prev_disp: float = 0.0
var _vel: float = 0.0
var _prev_vel: float = 0.0
var _prev_t: float = 0.0
var _peak_disp: float = 0.0

var _t_takeaway: float = -1.0
var _t_top: float = -1.0
var _t_impact: float = -1.0
var had_top: bool = false

var _max_accel: float = 0.0
var _max_jerk: float = 0.0
var _prev_seg_dir: Vector2 = Vector2.ZERO
var _follow_through: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

@onready var label: Label = $Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	set_process_input(false)
	if label:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_label("Press gold · pull UP · through")


func address_hint() -> Vector2:
	## Suggested thumb start — bottom-center of the pad (natural one-handed rest).
	return Vector2(size.x * 0.5, size.y * 0.78)


func reset() -> void:
	dragging = false
	swinging = false
	trail.clear()
	_touch_index = -1
	_axis = Vector2.ZERO
	_axis_locked = false
	_disp = 0.0
	_prev_disp = 0.0
	_vel = 0.0
	_prev_vel = 0.0
	_peak_disp = 0.0
	_t_takeaway = -1.0
	_t_top = -1.0
	_t_impact = -1.0
	had_top = false
	_max_accel = 0.0
	_max_jerk = 0.0
	_prev_seg_dir = Vector2.ZERO
	_follow_through = 0.0
	_refresh_label("Press gold · pull UP · through")
	queue_redraw()
	trail_updated.emit(trail)


func set_enabled(on: bool) -> void:
	active = on
	if not on:
		dragging = false
		swinging = false
	modulate.a = 1.0 if on else 0.45
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	set_process_input(on)
	set_process(on)  # idle pulse for start target
	queue_redraw()


func _process(_delta: float) -> void:
	if active and not dragging:
		queue_redraw()


func _accept_mouse() -> bool:
	return not DisplayServer.is_touchscreen_available()


func _deadzone() -> float:
	return maxf(minf(size.x, size.y) * DEADZONE_FRAC, 18.0)


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := _to_local(touch.position)
		if touch.pressed and _touch_index < 0 and _rect_has_point(local):
			_begin(local, touch.index)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_end_touch()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and dragging and (event as InputEventScreenDrag).index == _touch_index:
		_update(_to_local((event as InputEventScreenDrag).position))
		get_viewport().set_input_as_handled()
		return

	if not _accept_mouse():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _mouse_over_self():
			_begin(get_local_mouse_position(), 0)
			get_viewport().set_input_as_handled()
		elif not event.pressed and dragging:
			_end_touch()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and dragging:
		_update(get_local_mouse_position())
		get_viewport().set_input_as_handled()


func _mouse_over_self() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


func _rect_has_point(local: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local)


func _to_local(screen_pos: Vector2) -> Vector2:
	return screen_pos - global_position


func _begin(pos: Vector2, index: int) -> void:
	reset()
	dragging = true
	_touch_index = index
	_address = pos
	_smoothed = pos
	_last_pos = pos
	_prev_t = Time.get_ticks_msec() / 1000.0
	_t_takeaway = _prev_t
	trail.append(pos)
	set_process(true)
	moment.emit("takeaway")
	_refresh_label("Takeaway…")
	queue_redraw()


func _update(pos: Vector2) -> void:
	if not dragging:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dt := maxf(now - _prev_t, 0.001)
	_smoothed = _smoothed.lerp(pos, EMA_ALPHA)
	var delta := _smoothed - _address

	# Lock backswing axis from first significant move.
	if not _axis_locked:
		if delta.length() >= _deadzone():
			_axis = delta.normalized()
			_axis_locked = true
			swinging = true
			_refresh_label("Backswing…")
		else:
			_prev_t = now
			_last_pos = _smoothed
			return

	_prev_disp = _disp
	_disp = delta.dot(_axis)
	_prev_vel = _vel
	_vel = (_disp - _prev_disp) / dt
	var accel := (_vel - _prev_vel) / dt
	_max_accel = maxf(_max_accel, absf(accel) / maxf(size.y, 1.0))

	var seg := _smoothed - _last_pos
	if seg.length_squared() > 4.0:
		var seg_dir := seg.normalized()
		if _prev_seg_dir.length_squared() > 0.5:
			var ang := absf(_prev_seg_dir.angle_to(seg_dir))
			_max_jerk = maxf(_max_jerk, ang)
		_prev_seg_dir = seg_dir

	_peak_disp = maxf(_peak_disp, _disp)
	trail.append(_smoothed)
	while trail.size() > 64:
		trail.remove_at(0)
	trail_updated.emit(trail)

	# Top: after enough backswing, velocity near zero or reverses from positive→negative.
	var min_bs := maxf(size.y * MIN_BACKSWING_FRAC, _deadzone() * 1.2)
	if not had_top and _peak_disp >= min_bs:
		var reversing := _prev_vel > VEL_TOP_EPS and _vel <= VEL_TOP_EPS * 0.25
		var peaked := _disp < _peak_disp - _deadzone() * 0.15 and _vel < 0.0
		if reversing or peaked:
			had_top = true
			_t_top = now
			moment.emit("top")
			_refresh_label("Top — through…")

	# Impact: after top, cross back near address along axis.
	if had_top and _t_impact < 0.0:
		var cross := maxf(size.y * IMPACT_CROSS_FRAC, _deadzone() * 0.5)
		if _disp <= cross and _vel < 0.0:
			_finish_impact(now, false)
			return
		# Follow-through past address (negative disp)
		if _disp < 0.0:
			_follow_through = maxf(_follow_through, -_disp / maxf(size.y, 1.0))

	_prev_t = now
	_last_pos = _smoothed
	queue_redraw()


func _end_touch() -> void:
	if not dragging:
		return
	var now := Time.get_ticks_msec() / 1000.0
	# Quick tap / never left deadzone — ignore, don't fail.
	if not _axis_locked or not swinging:
		dragging = false
		_touch_index = -1
		reset()
		return

	if _t_impact < 0.0:
		if had_top and RELEASE_IS_IMPACT:
			_finish_impact(now, false)
		elif had_top:
			# Incomplete follow-through — still grade as mishit.
			_finish_impact(now, true)
		else:
			# Released during backswing — incomplete.
			_t_top = now
			_finish_impact(now, true)
		return

	dragging = false
	_touch_index = -1


func _finish_impact(now: float, incomplete: bool) -> void:
	if _t_impact >= 0.0:
		return
	_t_impact = now
	if _t_top < 0.0:
		_t_top = lerpf(_t_takeaway, _t_impact, 0.75)
	# Tiny backswing after top: nudge so ratio math doesn't explode.
	if _t_impact - _t_top < 0.02:
		_t_impact = _t_top + 0.02

	var pad := maxf(size.y, 1.0)
	var sample := {
		"t_takeaway": _t_takeaway,
		"t_top": _t_top,
		"t_impact": _t_impact,
		"max_accel": _max_accel,
		"max_jerk": _max_jerk,
		"backswing_len": _peak_disp / pad,
		"follow_through_len": _follow_through,
		"incomplete": incomplete,
	}
	moment.emit("impact")
	dragging = false
	swinging = false
	_touch_index = -1
	set_process(false)
	_refresh_label("Committed")
	committed.emit(sample)
	queue_redraw()


func _refresh_label(text: String) -> void:
	if label:
		label.text = text
		# Keep label readable over the start cue; hide once swinging.
		label.modulate.a = 0.0 if dragging or swinging or had_top else 0.95


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-6.0)
	draw_rect(r, Color(0.1, 0.16, 0.12, 0.55), false, 2.0)

	# Idle: scream "start here" + pull-up path. During drag: trail + live thumb.
	if active and not dragging:
		_draw_start_cue()
	else:
		if trail.size() >= 2:
			for i in range(1, trail.size()):
				var a := float(i) / float(trail.size())
				draw_line(trail[i - 1], trail[i], Color(0.4, 0.85, 0.55, 0.25 + 0.55 * a), 3.0, true)
		if dragging:
			# Mark address so "through" has a visible target.
			draw_circle(_address, 8.0, Color(0.95, 0.85, 0.3, 0.55))
			draw_arc(_address, 14.0, 0.0, TAU, 24, Color(0.95, 0.85, 0.3, 0.7), 2.0, true)
			draw_circle(_smoothed, 10.0, Color(0.95, 0.9, 0.35, 0.85))


func _draw_start_cue() -> void:
	var start := address_hint()
	var top := Vector2(size.x * 0.5, size.y * 0.18)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	# Ghost path: start → top (backswing) → back through start (downswing feel).
	var mid := Vector2(size.x * 0.58, size.y * 0.42)
	draw_line(start, top, Color(0.55, 0.75, 0.55, 0.35 * pulse), 4.0, true)
	draw_line(top, mid, Color(0.55, 0.75, 0.55, 0.22), 3.0, true)
	draw_line(mid, start + Vector2(0, 18), Color(0.95, 0.8, 0.35, 0.4), 3.0, true)
	# Arrow head at top of pull
	draw_line(top, top + Vector2(-14, 18), Color(0.6, 0.9, 0.55, 0.7 * pulse), 3.0, true)
	draw_line(top, top + Vector2(14, 18), Color(0.6, 0.9, 0.55, 0.7 * pulse), 3.0, true)
	# Gold start target — the only place that looks tappable
	draw_circle(start, 22.0 + pulse * 6.0, Color(1.0, 0.85, 0.25, 0.2 + 0.2 * pulse))
	draw_circle(start, 14.0, Color(1.0, 0.88, 0.3, 0.85))
	draw_arc(start, 20.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.75 * pulse), 3.0, true)
	draw_string(
		ThemeDB.fallback_font,
		start + Vector2(-36, 36),
		"START",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.CAPTION,
		Color(1.0, 0.92, 0.55, 0.9),
	)

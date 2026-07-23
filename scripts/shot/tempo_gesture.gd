class_name TempoGesture
extends Control

## Single-thumb swing drag: takeaway → top (reversal) → impact (cross address).
## Emits sample with timestamps + balance raw signals. Desktop: LMB drag.

signal committed(sample: Dictionary)
signal moment(name: String)  ## "takeaway" | "top" | "impact"
signal trail_updated(points: PackedVector2Array)
signal live_changed  ## ratio / status changed — meter redraws

## Feel-test: if true, finger release after top counts as impact (Golden-Tee flick).
static var RELEASE_IS_IMPACT: bool = false
## Touch EMA — lower = snappier/jittery, higher = smoother/laggier. F1 knob.
static var EMA_ALPHA: float = 0.35

const DEADZONE_FRAC := 0.10
const VEL_TOP_EPS := 40.0
const IMPACT_CROSS_FRAC := 0.12
const MIN_BACKSWING_FRAC := 0.14
## ponytail: ~4% L/R edge margin — calibrate on-device with gesture nav on
const EDGE_DEADZONE_FRAC := 0.04
const EDGE_DEADZONE_MIN_PX := 24.0
## Ideal Tour-Tempo-ish pacing for the pad ghost (seconds).
const GUIDE_BACK_FULL := 0.75
const GUIDE_BACK_SHORT := 0.50

var active: bool = false
var dragging: bool = false
var swinging: bool = false
var trail: PackedVector2Array = PackedVector2Array()
var shot_type: String = "full"
## Putt: target backswing fraction of lane (set by ShotRoutine). Unused for full/chip.
var putt_target_frac: float = 0.5
var peak_pos: Vector2 = Vector2.ZERO
var status: String = ""  ## PULL | TOP | THROUGH | ""

var _touch_index: int = -1
var _address: Vector2 = Vector2.ZERO
var _smoothed: Vector2 = Vector2.ZERO
var _axis: Vector2 = Vector2.ZERO
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
var _top_flash_until: int = 0

var _max_accel: float = 0.0
var _max_jerk: float = 0.0
var _prev_seg_dir: Vector2 = Vector2.ZERO
var _follow_through: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
## Signed pad-normalized peak lateral (perp to stroke axis). + = right of lane.
var _max_lateral: float = 0.0
var _marker_crossed: bool = false

@onready var label: Label = $Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	set_process_input(false)
	if label:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_label(_idle_prompt())


func _is_putt() -> bool:
	return shot_type == "putt"


func _idle_prompt() -> String:
	return "Press · pull to marker · through" if _is_putt() else "Press gold · pull UP · through"


func address_hint() -> Vector2:
	## Putt pad: shorter, more local lane (still bottom-screen).
	var y := 0.72 if _is_putt() else 0.78
	return Vector2(size.x * 0.5, size.y * y)


func top_hint() -> Vector2:
	var y := 0.28 if _is_putt() else 0.18
	return Vector2(size.x * 0.5, size.y * y)


func _lane_len() -> float:
	return maxf(address_hint().distance_to(top_hint()), 1.0)


func live_backswing_frac() -> float:
	return clampf(_peak_disp / _lane_len(), 0.0, 1.2)


func live_ratio() -> float:
	## Partial ratio after top; -1 before top / invalid. Putt meter uses live_backswing_frac.
	if not had_top or _t_top < 0.0 or _t_takeaway < 0.0:
		return -1.0
	var now := Time.get_ticks_msec() / 1000.0
	var end_t := _t_impact if _t_impact >= 0.0 else now
	var bs := _t_top - _t_takeaway
	var ds := end_t - _t_top
	if ds <= 0.001:
		return 99.0
	if bs <= 0.0:
		return 0.0
	return bs / ds


func trail_color() -> Color:
	if _is_putt():
		return _putt_trail_color()
	var r := live_ratio()
	if r < 0.0:
		return Color(0.55, 0.7, 0.6, 0.75)  # neutral while pulling
	var target := TempoGrade.target_ratio(shot_type)
	var tol := TempoGrade.base_tolerance(shot_type)
	var abs_n := absf(r - target) / maxf(tol, 0.01)
	if abs_n <= TempoGrade.BAND_PERFECT:
		return Color(0.35, 0.92, 0.45, 0.9)
	if abs_n <= TempoGrade.BAND_GOOD:
		return Color(0.95, 0.85, 0.25, 0.9)
	return Color(0.95, 0.35, 0.3, 0.9)


func _putt_trail_color() -> Color:
	if not _axis_locked:
		return Color(0.45, 0.7, 0.85, 0.75)
	var abs_n := absf(live_backswing_frac() - putt_target_frac) / maxf(PuttStroke.BAND_HALF, 0.01)
	if abs_n <= PuttStroke.BAND_PERFECT:
		return Color(0.4, 0.85, 0.95, 0.9)
	if abs_n <= PuttStroke.BAND_GOOD:
		return Color(0.95, 0.85, 0.35, 0.9)
	return Color(0.95, 0.4, 0.35, 0.9)


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
	peak_pos = top_hint()
	_t_takeaway = -1.0
	_t_top = -1.0
	_t_impact = -1.0
	had_top = false
	_top_flash_until = 0
	status = ""
	_max_accel = 0.0
	_max_jerk = 0.0
	_prev_seg_dir = Vector2.ZERO
	_follow_through = 0.0
	_max_lateral = 0.0
	_marker_crossed = false
	_refresh_label(_idle_prompt())
	queue_redraw()
	trail_updated.emit(trail)
	live_changed.emit()


func set_enabled(on: bool) -> void:
	active = on
	if not on:
		dragging = false
		swinging = false
	modulate.a = 1.0 if on else 0.45
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	set_process_input(on)
	set_process(on)
	queue_redraw()


func _process(_delta: float) -> void:
	if active and (not dragging or had_top or _guide_alpha() > 0.02):
		queue_redraw()
		if had_top and dragging and _t_impact < 0.0:
			live_changed.emit()


func _guide_alpha() -> float:
	## Fadeable perfect-swing ghost. Toggle in F1; strong on range / early holes.
	if not GameState.tempo_guide_enabled:
		return 0.0
	if GameState.tempo_guide_forced or GameState.range_mode:
		return 0.9
	if GameState.current_hole <= 3:
		return 0.85
	return clampf(1.0 - GameState.get_form() * 1.35, 0.0, 0.75)


func _guide_back_sec() -> float:
	return GUIDE_BACK_SHORT if TempoGrade.target_ratio(shot_type) < 2.5 else GUIDE_BACK_FULL


func _guide_down_sec() -> float:
	var back := _guide_back_sec()
	return back / maxf(TempoGrade.target_ratio(shot_type), 1.0)


func _ideal_ghost_pos(elapsed: float) -> Dictionary:
	## Returns {pos, phase} phase: pull|top|through|done
	var start := _address if (dragging and _t_takeaway >= 0.0) else address_hint()
	var top := top_hint()
	var back := _guide_back_sec()
	var down := _guide_down_sec()
	if elapsed < 0.0:
		return {"pos": start, "phase": "pull"}
	if elapsed <= back:
		var u := elapsed / back
		var phase := "top" if u > 0.92 else "pull"
		return {"pos": start.lerp(top, u), "phase": phase}
	if elapsed <= back + down:
		var u2 := (elapsed - back) / down
		return {"pos": top.lerp(start, u2), "phase": "through"}
	return {"pos": start, "phase": "done"}


func _accept_mouse() -> bool:
	return not DisplayServer.is_touchscreen_available()


func _deadzone() -> float:
	return maxf(minf(size.x, size.y) * DEADZONE_FRAC, 18.0)


static func edge_margin_px(window_width: float) -> float:
	return maxf(window_width * EDGE_DEADZONE_FRAC, EDGE_DEADZONE_MIN_PX)


static func screen_x_ok(screen_x: float, window_width: float) -> bool:
	## True when touch is clear of OS edge-gesture zones (L/R).
	var m := edge_margin_px(window_width)
	return screen_x >= m and screen_x <= window_width - m


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if dragging and _t_impact < 0.0:
			_abort_swing()


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := _to_local(touch.position)
		if touch.pressed and _touch_index < 0 and _rect_has_point(local):
			# Reject L/R edge starts so OS back-gestures don't steal a swing.
			var vp_w := get_viewport().get_visible_rect().size.x
			if not screen_x_ok(touch.position.x, vp_w):
				return
			_begin(local, touch.index)
			get_viewport().set_input_as_handled()
		elif touch.index == _touch_index and (touch.canceled or not touch.pressed):
			if touch.canceled:
				_abort_swing()
			else:
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
	status = "PULL"
	trail.append(pos)
	set_process(true)
	moment.emit("takeaway")
	_refresh_label("")
	live_changed.emit()
	queue_redraw()


func _update(pos: Vector2) -> void:
	if not dragging:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dt := maxf(now - _prev_t, 0.001)
	_smoothed = _smoothed.lerp(pos, EMA_ALPHA)
	var delta := _smoothed - _address

	if not _axis_locked:
		if delta.length() >= _deadzone():
			_axis = delta.normalized()
			_axis_locked = true
			swinging = true
			status = "PULL"
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

	# Lateral (perp to stroke axis) — putt line grade. Axis points toward top of pad.
	var perp := Vector2(-_axis.y, _axis.x)
	var lat := delta.dot(perp) / maxf(size.y, 1.0)
	if absf(lat) > absf(_max_lateral):
		_max_lateral = lat

	var seg := _smoothed - _last_pos
	if seg.length_squared() > 4.0:
		var seg_dir := seg.normalized()
		if _prev_seg_dir.length_squared() > 0.5:
			var ang := absf(_prev_seg_dir.angle_to(seg_dir))
			_max_jerk = maxf(_max_jerk, ang)
		_prev_seg_dir = seg_dir

	if _disp >= _peak_disp:
		_peak_disp = _disp
		peak_pos = _smoothed
	trail.append(_smoothed)
	while trail.size() > 64:
		trail.remove_at(0)
	trail_updated.emit(trail)

	# Putt: soft tick when pull first crosses the target marker.
	if _is_putt() and not _marker_crossed and not had_top:
		var tgt_disp := putt_target_frac * _lane_len()
		if _peak_disp >= tgt_disp:
			_marker_crossed = true
			moment.emit("marker")

	var min_bs := maxf(size.y * MIN_BACKSWING_FRAC, _deadzone() * 1.2)
	if not had_top and _peak_disp >= min_bs:
		var reversing := _prev_vel > VEL_TOP_EPS and _vel <= VEL_TOP_EPS * 0.25
		var peaked := _disp < _peak_disp - _deadzone() * 0.15 and _vel < 0.0
		if reversing or peaked:
			had_top = true
			_t_top = now
			status = "TOP"
			_top_flash_until = Time.get_ticks_msec() + 320
			moment.emit("top")
			live_changed.emit()

	if had_top and _t_impact < 0.0:
		status = "THROUGH"
		var cross := maxf(size.y * IMPACT_CROSS_FRAC, _deadzone() * 0.5)
		if _disp <= cross and _vel < 0.0:
			_finish_impact(now, false)
			return
		if _disp < 0.0:
			_follow_through = maxf(_follow_through, -_disp / maxf(size.y, 1.0))

	_prev_t = now
	_last_pos = _smoothed
	live_changed.emit()
	queue_redraw()


func _abort_swing() -> void:
	## OS cancel / focus-out — free reset, never a ghost commit.
	if _t_impact >= 0.0:
		return
	if not dragging and not swinging:
		return
	reset()


func _end_touch() -> void:
	if not dragging:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _axis_locked or not swinging:
		dragging = false
		_touch_index = -1
		reset()
		return

	if _t_impact < 0.0:
		if had_top and RELEASE_IS_IMPACT:
			_finish_impact(now, false)
		elif had_top:
			_finish_impact(now, true)
		else:
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
	if _t_impact - _t_top < 0.02:
		_t_impact = _t_top + 0.02

	var pad := maxf(size.y, 1.0)
	var lane := _lane_len()
	var sample := {
		"t_takeaway": _t_takeaway,
		"t_top": _t_top,
		"t_impact": _t_impact,
		"max_accel": _max_accel,
		"max_jerk": _max_jerk,
		"backswing_len": _peak_disp / pad,
		"follow_through_len": _follow_through,
		"backswing_frac": _peak_disp / lane,
		"follow_frac": _follow_through * pad / lane,
		"max_lateral": _max_lateral,
		"incomplete": incomplete,
	}
	status = "THROUGH"
	moment.emit("impact")
	dragging = false
	swinging = false
	_touch_index = -1
	set_process(true)  # keep idle landmarks after commit until disabled
	_refresh_label("")
	committed.emit(sample)
	live_changed.emit()
	queue_redraw()


func _refresh_label(text: String) -> void:
	if label:
		label.text = text
		label.modulate.a = 0.0 if dragging or swinging or had_top or text.is_empty() else 0.95


func _draw() -> void:
	if _is_putt():
		_draw_putt()
		return
	_draw_pad_bounds()
	if active and not dragging and _t_impact < 0.0:
		_draw_idle_coach()
		_draw_tempo_ghost(true)
	else:
		_draw_pull_lane(true)
		_draw_active_landmarks()
		_draw_tempo_ghost(false)
		_draw_trail()
		if dragging:
			draw_circle(_smoothed, 11.0, Color(0.95, 0.9, 0.35, 0.9))
		_draw_status_chip()


func _draw_putt() -> void:
	## Cool palette, narrower lane, target marker + band + mirrored through target.
	var r := Rect2(Vector2.ZERO, size).grow(-8.0)
	draw_rect(r, Color(0.06, 0.12, 0.16, 0.78), true)
	draw_rect(r, Color(0.35, 0.7, 0.85, 0.75), false, 3.0)

	var start := address_hint()
	var top := top_hint()
	var tgt := clampf(putt_target_frac, PuttStroke.MARKER_MIN_FRAC, PuttStroke.MARKER_MAX_FRAC)
	var band := PuttStroke.BAND_HALF
	var mark: Vector2 = start.lerp(top, tgt)
	var band_lo: Vector2 = start.lerp(top, clampf(tgt - band, 0.0, 1.0))
	var band_hi: Vector2 = start.lerp(top, clampf(tgt + band, 0.0, 1.0))
	# Mirrored through target below address (matched halves).
	var through_dir := Vector2(0, 1)
	var through_mark := start + through_dir * (start.distance_to(mark))
	var through_lo := start + through_dir * (start.distance_to(band_lo))
	var through_hi := start + through_dir * (start.distance_to(band_hi))

	# Narrow cool lane
	draw_line(start, top, Color(0.15, 0.28, 0.35, 0.95), 16.0, true)
	draw_line(start, top, Color(0.3, 0.55, 0.7, 0.65), 8.0, true)
	draw_line(start, through_hi, Color(0.15, 0.28, 0.35, 0.55), 12.0, true)

	# Tolerance bands (same space as grade)
	draw_line(band_lo, band_hi, Color(0.35, 0.75, 0.9, 0.35), 22.0, true)
	draw_line(through_lo, through_hi, Color(0.35, 0.75, 0.9, 0.22), 18.0, true)

	# Target ticks
	var tick_c := Color(0.55, 0.95, 1.0, 0.95)
	draw_line(mark + Vector2(-20, 0), mark + Vector2(20, 0), tick_c, 3.5, true)
	draw_string(
		ThemeDB.fallback_font, mark + Vector2(24, 6), "PACE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, tick_c
	)
	draw_line(through_mark + Vector2(-16, 0), through_mark + Vector2(16, 0), Color(0.55, 0.85, 0.95, 0.7), 2.5, true)
	draw_string(
		ThemeDB.fallback_font, through_mark + Vector2(20, 6), "THRU",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.55, 0.85, 0.95, 0.7)
	)

	# Address disc
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	if not dragging and _t_impact < 0.0:
		draw_circle(start, 16.0 + pulse * 4.0, Color(0.45, 0.85, 1.0, 0.18 + 0.15 * pulse))
	draw_circle(start, 11.0, Color(0.55, 0.9, 1.0, 0.9))
	draw_arc(start, 16.0, 0.0, TAU, 24, Color(0.55, 0.9, 1.0, 0.65 * pulse), 2.5, true)

	# Live pull fill
	if dragging and _axis_locked:
		var prog := clampf(_peak_disp / _lane_len(), 0.0, 1.0)
		var tip: Vector2 = start.lerp(top, prog)
		draw_line(start, tip, trail_color(), 8.0, true)

	_draw_trail()
	if dragging:
		draw_circle(_smoothed, 10.0, Color(0.7, 0.95, 1.0, 0.9))
	if status != "":
		_draw_status_chip()


func _draw_tempo_ghost(looping: bool) -> void:
	var a := _guide_alpha()
	if a < 0.05:
		return
	var back := _guide_back_sec()
	var down := _guide_down_sec()
	var cycle := back + down + 0.35  # rest at address before replaying
	var elapsed: float
	if looping:
		elapsed = fmod(Time.get_ticks_msec() / 1000.0, cycle)
	elif dragging and _t_takeaway >= 0.0:
		elapsed = Time.get_ticks_msec() / 1000.0 - _t_takeaway
	else:
		return
	var g: Dictionary = _ideal_ghost_pos(elapsed)
	var pos: Vector2 = g["pos"]
	var phase: String = str(g["phase"])
	var col := Color(0.35, 0.85, 1.0, a * 0.55)
	match phase:
		"top":
			col = Color(0.45, 1.0, 0.55, a * 0.7)
		"through":
			col = Color(1.0, 0.9, 0.35, a * 0.7)
		"done":
			col = Color(0.35, 0.85, 1.0, a * 0.35)
	# Ghost disc + ring — follow this for perfect spacing
	draw_circle(pos, 18.0, Color(col.r, col.g, col.b, col.a * 0.35))
	draw_arc(pos, 20.0, 0.0, TAU, 28, col, 3.0, true)
	draw_circle(pos, 7.0, col)
	if looping and phase != "done":
		draw_string(
			ThemeDB.fallback_font, pos + Vector2(24, 6), "GUIDE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, col
		)
	# Beat labels while looping so the 3:1 is obvious
	if looping:
		var start := address_hint()
		var tip := "follow the blue · ~%.0f:1" % TempoGrade.target_ratio(shot_type)
		draw_string(
			ThemeDB.fallback_font, Vector2(size.x * 0.5 - 120.0, size.y - 28.0), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.6, 0.9, 1.0, a * 0.85)
		)
		# Tiny beat pips on the lane
		var top := top_hint()
		draw_circle(start.lerp(top, 0.33), 4.0, Color(0.5, 0.85, 1.0, a * 0.5))
		draw_circle(start.lerp(top, 0.66), 4.0, Color(0.5, 0.85, 1.0, a * 0.5))
		draw_circle(top, 5.0, Color(0.5, 1.0, 0.6, a * 0.6))


func _draw_pad_bounds() -> void:
	## Whole touchable area — so the player sees where input lives.
	var r := Rect2(Vector2.ZERO, size).grow(-4.0)
	draw_rect(r, Color(0.08, 0.14, 0.11, 0.72), true)
	draw_rect(r, Color(0.45, 0.75, 0.5, 0.85), false, 4.0)
	# Corner ticks reinforce the rectangle
	var tick := 22.0
	var c := Color(0.7, 0.95, 0.7, 0.9)
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var inward := Vector2(
			tick if corner.x < size.x * 0.5 else -tick,
			tick if corner.y < size.y * 0.5 else -tick
		)
		draw_line(corner, corner + Vector2(inward.x, 0), c, 3.0, true)
		draw_line(corner, corner + Vector2(0, inward.y), c, 3.0, true)


func _pull_lane_ends() -> PackedVector2Array:
	## Canonical vertical lane used for teaching (idle + active fill).
	return PackedVector2Array([address_hint(), top_hint()])


func _min_pull_point() -> Vector2:
	## Where a reversal first counts as TOP (MIN_BACKSWING_FRAC along START→TOP).
	var ends := _pull_lane_ends()
	return ends[0].lerp(ends[1], clampf(MIN_BACKSWING_FRAC / 0.60, 0.15, 0.45))


func _draw_pull_lane(show_progress: bool) -> void:
	var ends := _pull_lane_ends()
	var start: Vector2 = ends[0]
	var top: Vector2 = ends[1]
	var min_p := _min_pull_point()
	# Wide track = the full legal pull length
	draw_line(start, top, Color(0.2, 0.32, 0.24, 0.95), 22.0, true)
	draw_line(start, top, Color(0.35, 0.55, 0.4, 0.7), 14.0, true)
	# Min tick — below this, release won't count as a real top
	draw_line(min_p + Vector2(-18, 0), min_p + Vector2(18, 0), Color(0.95, 0.75, 0.3, 0.9), 3.0, true)
	draw_string(
		ThemeDB.fallback_font, min_p + Vector2(22, 8), "MIN",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.95, 0.8, 0.4, 0.9)
	)
	# Full / TOP end cap
	draw_line(top + Vector2(-22, 0), top + Vector2(22, 0), Color(0.5, 0.95, 0.55, 0.95), 4.0, true)
	draw_string(
		ThemeDB.fallback_font, top + Vector2(24, 8), "FULL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.55, 0.95, 0.6, 0.95)
	)
	if show_progress and dragging and _axis_locked:
		var lane_len := start.distance_to(top)
		var prog := clampf(_peak_disp / maxf(lane_len, 1.0), 0.0, 1.0)
		var tip: Vector2 = start.lerp(top, prog)
		draw_line(start, tip, Color(0.45, 0.95, 0.55, 0.85), 10.0, true)


func _draw_idle_coach() -> void:
	var start := address_hint()
	var top := top_hint()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	var follow := start + Vector2(0, size.y * 0.12)
	_draw_pull_lane(false)
	# Return path ghost
	draw_line(top, start + Vector2(8, 0), Color(0.95, 0.8, 0.35, 0.45), 4.0, true)
	draw_line(start, follow, Color(0.5, 0.65, 0.7, 0.35), 3.0, true)
	draw_line(top, top + Vector2(-14, 18), Color(0.6, 0.9, 0.55, 0.75 * pulse), 3.0, true)
	draw_line(top, top + Vector2(14, 18), Color(0.6, 0.9, 0.55, 0.75 * pulse), 3.0, true)
	_draw_landmark(top, "TOP", Color(0.55, 0.9, 0.55, 0.85), 10.0)
	_draw_landmark(follow, "FOLLOW", Color(0.55, 0.7, 0.8, 0.55), 8.0)
	# Gold START
	draw_circle(start, 22.0 + pulse * 6.0, Color(1.0, 0.85, 0.25, 0.2 + 0.2 * pulse))
	draw_circle(start, 14.0, Color(1.0, 0.88, 0.3, 0.9))
	draw_arc(start, 20.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.75 * pulse), 3.0, true)
	draw_string(
		ThemeDB.fallback_font, start + Vector2(-40, 38), "START",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(1.0, 0.92, 0.55, 0.95)
	)


func _draw_active_landmarks() -> void:
	var addr := _address if dragging or _t_takeaway >= 0.0 else address_hint()
	var top_p := peak_pos if _peak_disp > 1.0 else top_hint()
	# Follow zone past address (along −axis if known, else down)
	var follow_dir := -_axis if _axis_locked else Vector2(0, 1)
	var follow := addr + follow_dir * (size.y * 0.14)

	var through_label := "THROUGH" if had_top else "START"
	var through_c := Color(1.0, 0.88, 0.3, 0.95) if had_top else Color(1.0, 0.88, 0.3, 0.75)
	draw_circle(addr, 16.0 if had_top else 12.0, through_c)
	draw_arc(addr, 22.0, 0.0, TAU, 28, through_c, 2.5, true)
	draw_string(
		ThemeDB.fallback_font, addr + Vector2(-48, 36), through_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, through_c
	)

	var top_c := Color(0.35, 0.95, 0.5, 1.0) if Time.get_ticks_msec() < _top_flash_until else Color(0.55, 0.9, 0.55, 0.85)
	var top_r := 16.0 if had_top else 10.0
	_draw_landmark(top_p, "TOP", top_c, top_r)

	draw_circle(follow, 7.0, Color(0.5, 0.7, 0.8, 0.4))
	draw_string(
		ThemeDB.fallback_font, follow + Vector2(-36, 22), "FOLLOW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.55, 0.75, 0.85, 0.55)
	)


func _draw_landmark(p: Vector2, text: String, c: Color, radius: float) -> void:
	draw_circle(p, radius, c)
	draw_arc(p, radius + 5.0, 0.0, TAU, 20, c, 2.0, true)
	draw_string(
		ThemeDB.fallback_font, p + Vector2(-28, -radius - 8), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, c
	)


func _draw_trail() -> void:
	if trail.size() < 2:
		return
	var c := trail_color()
	for i in range(1, trail.size()):
		var a := float(i) / float(trail.size())
		draw_line(trail[i - 1], trail[i], Color(c.r, c.g, c.b, 0.25 + 0.6 * a), 4.0, true)


func _draw_status_chip() -> void:
	if status.is_empty():
		return
	var chip_c := Color(0.25, 0.45, 0.3, 0.85)
	match status:
		"TOP":
			chip_c = Color(0.2, 0.55, 0.3, 0.9)
		"THROUGH":
			chip_c = Color(0.45, 0.4, 0.15, 0.9)
	var chip := Rect2(size.x * 0.5 - 70.0, 8.0, 140.0, 44.0)
	draw_rect(chip, chip_c, true)
	draw_string(
		ThemeDB.fallback_font, chip.position + Vector2(28, 32), status,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.BODY, Color(0.95, 0.98, 0.9, 1.0)
	)

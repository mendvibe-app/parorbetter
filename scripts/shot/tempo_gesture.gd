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
## Early-side half-width at address — impact at the ball, not 12% short of it.
const IMPACT_CROSS_FRAC := 0.02
const IMPACT_CROSS_FLOOR_PX := 6.0
const MIN_BACKSWING_FRAC := 0.14
## ponytail: ~4% L/R edge margin — calibrate on-device with gesture nav on
const EDGE_DEADZONE_FRAC := 0.04
const EDGE_DEADZONE_MIN_PX := 24.0
## Ideal Tour-Tempo-ish pacing for the pad ghost (seconds).
const GUIDE_BACK_FULL := 0.75
const GUIDE_BACK_SHORT := 0.50
const BALL_TEX := preload("res://assets/ball/ball.png")
const BALL_POP_MS := 120.0

var active: bool = false
var dragging: bool = false
var swinging: bool = false
var trail: PackedVector2Array = PackedVector2Array()
var shot_type: String = "full"
## Putt: target backswing fraction of lane (set by ShotRoutine). Unused for full/chip.
var putt_target_frac: float = 0.5
## Practice only — scored strokes stay blind on length (no PACE tick / band).
var putt_show_marker: bool = false
var peak_pos: Vector2 = Vector2.ZERO

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
## msec when axis locked — brief ball pop-in scale.
var _ball_pop_at: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	set_process_input(false)


func _is_putt() -> bool:
	return shot_type == "putt"


func address_hint() -> Vector2:
	## Address toward target on pad (upper); pull DOWN = backswing, through = up.
	## Putt sits lower so soft follow-through fits on-pad (not past the top edge).
	var y := 0.36 if _is_putt() else 0.18
	return Vector2(size.x * 0.5, size.y * y)


func top_hint() -> Vector2:
	## Backswing peak toward player (lower on pad).
	var y := 0.80 if _is_putt() else 0.78
	return Vector2(size.x * 0.5, size.y * y)


func _lane_len() -> float:
	return maxf(address_hint().distance_to(top_hint()), 1.0)


func _lane_through_dir() -> Vector2:
	## Past address, away from top (up toward target on camera).
	var d := address_hint() - top_hint()
	if d.length_squared() < 1.0:
		return Vector2(0, -1)
	return d.normalized()


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
	## Live color = tempo smoothness only — never length-vs-target (that's the answer leak).
	if not _axis_locked:
		return Color(0.45, 0.7, 0.85, 0.75)
	# Mirror TempoGrade.balance accel/jerk pens (putt-aware thresholds).
	var accel_n := clampf((_max_accel - 8.0) / 24.0, 0.0, 1.0)
	var jerk_n := clampf((_max_jerk - 0.6) / 1.4, 0.0, 1.0)
	var rough := maxf(accel_n, jerk_n)
	if rough <= 0.25:
		return Color(0.4, 0.85, 0.95, 0.9)
	if rough <= 0.55:
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
	_max_accel = 0.0
	_max_jerk = 0.0
	_prev_seg_dir = Vector2.ZERO
	_follow_through = 0.0
	_max_lateral = 0.0
	_marker_crossed = false
	_ball_pop_at = 0
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


func _impact_cross() -> float:
	## Small early band at address — ghost through ends at the ball.
	return maxf(size.y * IMPACT_CROSS_FRAC, IMPACT_CROSS_FLOOR_PX)


func _ghost_impact_pos(start: Vector2, top: Vector2) -> Vector2:
	var lane := top - start
	var lane_len := lane.length()
	if lane_len < 1.0:
		return start
	return start + lane * (minf(_impact_cross(), lane_len * 0.45) / lane_len)


func _ideal_ghost_pos(elapsed: float) -> Dictionary:
	## Returns {pos, phase} phase: pull|top|through|done
	## Through ends at impact cross (≈ address) so tracing the ghost matches the grader.
	var start := _address if (dragging and _t_takeaway >= 0.0) else address_hint()
	var top := top_hint()
	var impact_end := _ghost_impact_pos(start, top)
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
		return {"pos": top.lerp(impact_end, u2), "phase": "through"}
	return {"pos": impact_end, "phase": "done"}


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
	trail.append(pos)
	set_process(true)
	moment.emit("takeaway")
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
			_ball_pop_at = Time.get_ticks_msec()
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

	# Lateral (perp to stroke axis) — putt line grade. Axis = first pull direction.
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

	# Putt: soft tick when pull first crosses the target marker (practice only).
	if _is_putt() and putt_show_marker and not _marker_crossed and not had_top:
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
			_top_flash_until = Time.get_ticks_msec() + 320
			moment.emit("top")
			live_changed.emit()

	if had_top and _t_impact < 0.0:
		if _disp <= _impact_cross() and _vel < 0.0:
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
	moment.emit("impact")
	dragging = false
	swinging = false
	_touch_index = -1
	set_process(true)  # keep idle landmarks after commit until disabled
	committed.emit(sample)
	live_changed.emit()
	queue_redraw()


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


func _draw_putt() -> void:
	## Cool palette. Golf shape: address → pace feel → through the ball (soft follow on-pad).
	var r := Rect2(Vector2.ZERO, size).grow(-8.0)
	draw_rect(r, Color(0.06, 0.12, 0.16, 0.78), true)
	draw_rect(r, Color(0.35, 0.7, 0.85, 0.75), false, 3.0)

	var start := address_hint()
	var top := top_hint()
	var lane := _lane_len()
	var addr := _address if dragging or _t_takeaway >= 0.0 else start

	# Arc-width lane: edge grows with distance (line affordance, no length answer).
	_draw_putt_arc_lane(start, top, Color(0.15, 0.28, 0.35, 0.95), Color(0.3, 0.55, 0.7, 0.55))
	# Soft feet scale — scoring zone labeled; lag ticks so long putts aren't blank.
	_draw_putt_soft_scale(start, top)
	# Soft follow past address — room to finish, clamped on-pad (not a stop target).
	_draw_putt_follow_cue(addr)

	if putt_show_marker:
		_draw_putt_practice_marker(start, top)

	# Address: cyan idle → course ball once stroke commits (stays through follow).
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	_draw_putt_address(addr, pulse)

	# Live pull fill (color = smoothness, not length)
	if dragging and _axis_locked:
		var prog := clampf(_peak_disp / lane, 0.0, 1.0)
		var tip: Vector2 = start.lerp(top, prog)
		draw_line(start, tip, trail_color(), 8.0, true)

	_draw_trail()
	if dragging:
		draw_circle(_smoothed, 10.0, Color(0.7, 0.95, 1.0, 0.9))


func _putt_follow_len(addr: Vector2) -> float:
	## Soft stub past address; never past the pad's top margin.
	var room := maxf(addr.y - 20.0, 8.0)
	return minf(size.y * 0.12, room)


func _draw_putt_follow_cue(addr: Vector2) -> void:
	var through := _lane_through_dir()
	var tip := addr + through * _putt_follow_len(addr)
	var a := 0.7 if had_top else 0.45
	draw_line(addr, tip, Color(0.4, 0.7, 0.85, 0.35 * a), 6.0, true)
	draw_arc(tip, 10.0, 0.0, TAU, 20, Color(0.5, 0.8, 0.95, 0.55 * a), 2.0, true)


func _draw_putt_address(p: Vector2, pulse: float) -> void:
	if _axis_locked or _t_impact >= 0.0:
		_draw_pad_ball(p, _ball_pop_scale())
		return
	if not dragging and _t_impact < 0.0:
		draw_circle(p, 16.0 + pulse * 4.0, Color(0.45, 0.85, 1.0, 0.18 + 0.15 * pulse))
	draw_circle(p, 11.0, Color(0.55, 0.9, 1.0, 0.9))
	draw_arc(p, 16.0, 0.0, TAU, 24, Color(0.55, 0.9, 1.0, 0.65 * pulse), 2.5, true)


func _draw_putt_arc_lane(start: Vector2, top: Vector2, fill_c: Color, edge_c: Color) -> void:
	## Center line + widening edges from arc_allowance — teaches path, not pace.
	draw_line(start, top, fill_c, 14.0, true)
	var steps := 8
	var perp := Vector2(-(top - start).y, (top - start).x).normalized()
	for i in range(steps):
		var u0 := float(i) / float(steps)
		var u1 := float(i + 1) / float(steps)
		var a0 := PuttStroke.arc_allowance(u0) * size.y
		var a1 := PuttStroke.arc_allowance(u1) * size.y
		var p0: Vector2 = start.lerp(top, u0)
		var p1: Vector2 = start.lerp(top, u1)
		draw_line(p0 + perp * a0, p1 + perp * a1, edge_c, 2.0, true)
		draw_line(p0 - perp * a0, p1 - perp * a1, edge_c, 2.0, true)


func _draw_putt_soft_scale(start: Vector2, top: Vector2) -> void:
	## Ruler in feet via the same map grade uses. Dense ≤15 ft; 30 labeled; lag ticks 45–90.
	var max_yd := BallPhysics.PUTTER_MAX_YD
	for ft in PuttStroke.SCALE_LABELED_FT:
		_draw_putt_scale_tick(start, top, int(ft), max_yd, true)
	for ft in PuttStroke.SCALE_TICK_FT:
		_draw_putt_scale_tick(start, top, int(ft), max_yd, false)


func _draw_putt_scale_tick(
	start: Vector2, top: Vector2, ft: int, club_max_yd: float, labeled: bool
) -> void:
	var frac := PuttStroke.frac_for_ft(float(ft), club_max_yd)
	if frac < PuttStroke.MARKER_MIN_FRAC or frac > PuttStroke.MARKER_MAX_FRAC:
		return
	var mark: Vector2 = start.lerp(top, frac)
	var half := 14.0 if labeled else 10.0
	var a := 0.7 if labeled else 0.4
	var c := Color(0.55, 0.85, 0.95, a)
	draw_line(mark + Vector2(-half, 0), mark + Vector2(half, 0), c, 2.0 if labeled else 1.5, true)
	if labeled:
		draw_string(
			ThemeDB.fallback_font, mark + Vector2(half + 6.0, 6.0), str(ft),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiScale.CAPTION, Color(0.6, 0.88, 0.95, 0.65)
		)


func _draw_putt_practice_marker(start: Vector2, top: Vector2) -> void:
	## Practice-only: PACE tick on the backswing (the length answer). No THRU destination —
	## through is the soft follow cue; mirroring pace past address flies off-pad on long putts.
	var tgt := clampf(putt_target_frac, PuttStroke.MARKER_MIN_FRAC, PuttStroke.MARKER_MAX_FRAC)
	var band := PuttStroke.BAND_HALF
	var mark: Vector2 = start.lerp(top, tgt)
	var band_lo: Vector2 = start.lerp(top, clampf(tgt - band, 0.0, 1.0))
	var band_hi: Vector2 = start.lerp(top, clampf(tgt + band, 0.0, 1.0))
	draw_line(band_lo, band_hi, Color(0.35, 0.75, 0.9, 0.35), 22.0, true)
	var tick_c := Color(0.55, 0.95, 1.0, 0.95)
	draw_line(mark + Vector2(-20, 0), mark + Vector2(20, 0), tick_c, 3.5, true)


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
	# Beat pips while looping so the 3:1 spacing is visible
	if looping:
		var start := address_hint()
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


func _draw_pull_lane(show_progress: bool) -> void:
	var ends := _pull_lane_ends()
	var start: Vector2 = ends[0]
	var top: Vector2 = ends[1]
	# Wide track = the swing path (no engine MIN tick — that's miss feedback only)
	draw_line(start, top, Color(0.2, 0.32, 0.24, 0.95), 22.0, true)
	draw_line(start, top, Color(0.35, 0.55, 0.4, 0.7), 14.0, true)
	# Soft top end-cap — shape cue, not a hard target
	draw_line(top + Vector2(-22, 0), top + Vector2(22, 0), Color(0.5, 0.95, 0.55, 0.95), 4.0, true)
	if show_progress and dragging and _axis_locked:
		var lane_len := start.distance_to(top)
		var prog := clampf(_peak_disp / maxf(lane_len, 1.0), 0.0, 1.0)
		var tip: Vector2 = start.lerp(top, prog)
		draw_line(start, tip, Color(0.45, 0.95, 0.55, 0.85), 10.0, true)


func _follow_cue_end(addr: Vector2) -> Vector2:
	## Soft room past address — "keep going," not a stop target.
	return addr + _lane_through_dir() * (size.y * 0.14)


func _draw_follow_cue(addr: Vector2, a: float = 0.45) -> void:
	var tip := _follow_cue_end(addr)
	draw_line(addr, tip, Color(0.45, 0.7, 0.85, 0.35 * a), 6.0, true)
	# Open ring — space, not a bullseye
	draw_arc(tip, 10.0, 0.0, TAU, 20, Color(0.5, 0.75, 0.9, 0.55 * a), 2.0, true)


func _ball_pop_scale() -> float:
	if _ball_pop_at <= 0:
		return 1.0
	var u := clampf(float(Time.get_ticks_msec() - _ball_pop_at) / BALL_POP_MS, 0.0, 1.0)
	return lerpf(0.7, 1.0, u)


func _draw_pad_ball(p: Vector2, scale_mul: float = 1.0) -> void:
	## Same sprite as the course ball — pad stands in for the real shot.
	var r := 16.0 * scale_mul
	var tex_size := BALL_TEX.get_size()
	var s := (r * 2.0) / maxf(tex_size.x, 1.0)
	draw_set_transform(p, 0.0, Vector2(s, s))
	draw_texture(BALL_TEX, -tex_size * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_address_mark(p: Vector2, pulse: float) -> void:
	## Gold idle touch-target → course ball once the stroke commits (stays through follow).
	if _axis_locked or _t_impact >= 0.0:
		_draw_pad_ball(p, _ball_pop_scale())
		return
	draw_circle(p, 22.0 + pulse * 6.0, Color(1.0, 0.85, 0.25, 0.2 + 0.2 * pulse))
	draw_circle(p, 14.0, Color(1.0, 0.88, 0.3, 0.9))
	draw_arc(p, 20.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.75 * pulse), 3.0, true)


func _draw_idle_coach() -> void:
	var start := address_hint()
	var top := top_hint()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	var through := _lane_through_dir()
	# Chevrons at top point toward address (along backswing return).
	var to_addr := -through
	var chev_a := to_addr.rotated(-0.55) * 22.0
	var chev_b := to_addr.rotated(0.55) * 22.0
	_draw_pull_lane(false)
	_draw_follow_cue(start, 0.7)
	# Return path ghost
	draw_line(top, start + Vector2(8, 0), Color(0.95, 0.8, 0.35, 0.45), 4.0, true)
	draw_line(top, top + chev_a, Color(0.6, 0.9, 0.55, 0.75 * pulse), 3.0, true)
	draw_line(top, top + chev_b, Color(0.6, 0.9, 0.55, 0.75 * pulse), 3.0, true)
	_draw_landmark(top, Color(0.55, 0.9, 0.55, 0.85), 10.0)
	_draw_address_mark(start, pulse)
	# Down chevron under gold — pull toward top
	var down := -through
	var dchev_a := down.rotated(-0.5) * 18.0
	var dchev_b := down.rotated(0.5) * 18.0
	var dbase := start + down * 28.0
	draw_line(dbase, dbase + dchev_a, Color(1.0, 0.9, 0.4, 0.7 * pulse), 3.0, true)
	draw_line(dbase, dbase + dchev_b, Color(1.0, 0.9, 0.4, 0.7 * pulse), 3.0, true)


func _draw_active_landmarks() -> void:
	var addr := _address if dragging or _t_takeaway >= 0.0 else address_hint()
	var top_p := peak_pos if _peak_disp > 1.0 else top_hint()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)

	_draw_follow_cue(addr, 0.55 if had_top else 0.35)
	_draw_address_mark(addr, pulse)

	var top_c := Color(0.35, 0.95, 0.5, 1.0) if Time.get_ticks_msec() < _top_flash_until else Color(0.55, 0.9, 0.55, 0.85)
	var top_r := 16.0 if had_top else 10.0
	_draw_landmark(top_p, top_c, top_r)


func _draw_landmark(p: Vector2, c: Color, radius: float) -> void:
	draw_circle(p, radius, c)
	draw_arc(p, radius + 5.0, 0.0, TAU, 20, c, 2.0, true)


func _draw_trail() -> void:
	if trail.size() < 2:
		return
	var c := trail_color()
	for i in range(1, trail.size()):
		var a := float(i) / float(trail.size())
		draw_line(trail[i - 1], trail[i], Color(c.r, c.g, c.b, 0.25 + 0.6 * a), 4.0, true)

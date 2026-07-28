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
const TEX_START := preload("res://assets/ui/ui_tempo_landmark_start.png")
const TEX_TOP := preload("res://assets/ui/ui_tempo_landmark_top.png")
const TEX_THROUGH := preload("res://assets/ui/ui_tempo_landmark_through.png")
const TEX_LANE := preload("res://assets/ui/ui_tempo_lane.png")
const TEX_COACH := preload("res://assets/ui/ui_tempo_coach_idle.png")
const TEX_PUTT_START := preload("res://assets/ui/ui_putt_landmark_start.png")
const TEX_PUTT_TOP := preload("res://assets/ui/ui_putt_landmark_top.png")
const TEX_PUTT_THROUGH := preload("res://assets/ui/ui_putt_landmark_through.png")
const TEX_PUTT_LANE := preload("res://assets/ui/ui_putt_lane.png")
const TEX_PUTT_COACH := preload("res://assets/ui/ui_putt_coach_idle.png")
const TEX_GOLFER_ADDRESS := preload("res://assets/ui/ui_golfer_address.png")
const TEX_GOLFER_MID := preload("res://assets/ui/ui_golfer_mid.png")
const TEX_GOLFER_TOP := preload("res://assets/ui/ui_golfer_top.png")
const TEX_GOLFER_IMPACT := preload("res://assets/ui/ui_golfer_impact.png")
const TEX_GOLFER_FOLLOW := preload("res://assets/ui/ui_golfer_follow.png")
const TEX_GOLFER_PUTT_ADDRESS := preload("res://assets/ui/ui_golfer_putt_address.png")
const TEX_GOLFER_PUTT_MID := preload("res://assets/ui/ui_golfer_putt_mid.png")
const TEX_GOLFER_PUTT_TOP := preload("res://assets/ui/ui_golfer_putt_top.png")
const TEX_GOLFER_PUTT_IMPACT := preload("res://assets/ui/ui_golfer_putt_impact.png")
const TEX_GOLFER_PUTT_FOLLOW := preload("res://assets/ui/ui_golfer_putt_follow.png")
const TEX_CHIP_START := preload("res://assets/ui/ui_chip_landmark_start.png")
const TEX_CHIP_TOP := preload("res://assets/ui/ui_chip_landmark_top.png")
const TEX_CHIP_THROUGH := preload("res://assets/ui/ui_chip_landmark_through.png")
const TEX_CHIP_LANE := preload("res://assets/ui/ui_chip_lane.png")
const TEX_CHIP_COACH := preload("res://assets/ui/ui_chip_coach_idle.png")
const TEX_GOLFER_CHIP_ADDRESS := preload("res://assets/ui/ui_golfer_chip_address.png")
const TEX_GOLFER_CHIP_MID := preload("res://assets/ui/ui_golfer_chip_mid.png")
const TEX_GOLFER_CHIP_TOP := preload("res://assets/ui/ui_golfer_chip_top.png")
const TEX_GOLFER_CHIP_IMPACT := preload("res://assets/ui/ui_golfer_chip_impact.png")
const TEX_GOLFER_CHIP_FOLLOW := preload("res://assets/ui/ui_golfer_chip_follow.png")
## Chip pad palette — warm sand/wedge tones (art/STYLE.md Sand anchors), so chip
## reads distinct from putt's cool water palette at a glance. Current ui_chip_*
## art is a recolor placeholder of the putt set (see art/prompts/chip_pad.md)
## until dedicated chip art is generated.
const CHIP_BG := Color(0.16, 0.12, 0.07, 0.78)
const CHIP_BORDER := Color(0.83, 0.73, 0.57, 0.75)
const CHIP_ARC_EDGE := Color(0.7, 0.55, 0.35, 0.55)
const CHIP_FOLLOW_LINE := Color(0.85, 0.68, 0.42)
const CHIP_FOLLOW_RING := Color(0.9, 0.78, 0.55)
const CHIP_ADDRESS_GLOW := Color(0.85, 0.68, 0.42)
const CHIP_MARKER_BAND := Color(0.7, 0.55, 0.3, 0.35)
const CHIP_MARKER_TICK := Color(0.95, 0.85, 0.55, 0.95)
const CHIP_DRAG_DOT := Color(1.0, 0.85, 0.55, 0.9)
const BALL_POP_MS := 120.0
const LANDMARK_DIAM := 36.0
const GOLFER_DRAW_H := 120.0
const GOLFER_MARGIN := 12.0
## STYLE sky / grass for the mini stage behind the figure.
const GOLFER_SKY := Color(0.271, 0.478, 0.612, 1.0)  ## #457A9C
const GOLFER_SKY_HI := Color(0.525, 0.761, 0.804, 1.0)  ## #86C2CD
const GOLFER_GRASS := Color(0.329, 0.408, 0.208, 1.0)  ## #546835
const GOLFER_GRASS_TIP := Color(0.392, 0.494, 0.239, 1.0)  ## #647E3D
const GOLFER_STAGE_EDGE := Color(0.102, 0.122, 0.102, 1.0)  ## #1A1F1A

var active: bool = false
var dragging: bool = false
var swinging: bool = false
var trail: PackedVector2Array = PackedVector2Array()
var shot_type: String = "full"
## Putt: target backswing fraction of lane (set by ShotRoutine). Unused for full/pitch.
var putt_target_frac: float = 0.5
## Practice only — scored strokes stay blind on length (no PACE tick / band).
var putt_show_marker: bool = false
## Chip's actual club max carry (set by ShotRoutine) — the soft-scale ruler grades
## its yard ticks against this, not the putter constant putt's ruler defaults to.
var club_max_yards: float = 40.0
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
## Fastest speed reached during the backswing — baseline for the transition check.
var _peak_vel: float = 0.0
## Speed at the exact moment of reversal — compared against _peak_vel to grade
## "did you slow down before turning around" instead of the reversal angle itself.
var _vel_at_top: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = TEXTURE_FILTER_NEAREST
	set_process(false)
	set_process_input(false)


func _is_putt() -> bool:
	return shot_type == "putt"


func _is_chip() -> bool:
	return shot_type == "chip"


func address_hint() -> Vector2:
	## Address toward target on pad (upper); pull DOWN = backswing, through = up.
	## Putt uses more vertical span so 15 vs 30 ft is finger-resolvable. Chip sits
	## between putt and full — shorter reach than putt (no fine ft resolving needed)
	## but shorter than full swing's lane. Starting values for playtesting (Phase 4).
	## Full/pitch moved 0.18→0.30 (playtest): reclaims dead pad space below the old
	## backswing landmark and gives the follow-through floor marker real room
	## instead of overlapping the ball.
	var y := 0.22 if _is_putt() else (0.20 if _is_chip() else 0.30)
	return Vector2(floorf(size.x * 0.5) + 0.5, size.y * y)


func top_hint() -> Vector2:
	## Backswing peak toward player (lower on pad).
	## Full/pitch moved 0.78→0.92 (playtest) to match address_hint()'s move — keeps
	## the same lane length while shifting the whole lane down the pad.
	var y := 0.92 if _is_putt() else (0.85 if _is_chip() else 0.92)
	return Vector2(floorf(size.x * 0.5) + 0.5, size.y * y)


func _lane_peak_pos() -> Vector2:
	## On-lane point at live backswing depth — progress tip + top mark share this.
	return address_hint().lerp(top_hint(), clampf(_peak_disp / _lane_len(), 0.0, 1.2))


func _lane_len() -> float:
	return maxf(address_hint().distance_to(top_hint()), 1.0)


func _bs_floor_pos() -> Vector2:
	## Point on the address→top axis where TempoGrade.balance()'s short-backswing
	## penalty kicks in — floor*size.y is a pixel displacement, not a lane fraction.
	var frac := TempoGrade.bs_floor(shot_type) * size.y / _lane_len()
	return address_hint().lerp(top_hint(), frac)


func _lane_through_dir() -> Vector2:
	## Past address, away from top (up toward target on camera).
	var d := address_hint() - top_hint()
	if d.length_squared() < 1.0:
		return Vector2(0, -1)
	return d.normalized()


func live_backswing_frac() -> float:
	return clampf(_peak_disp / _lane_len(), 0.0, 1.2)


func live_stroke_u() -> float:
	## Spatial swing for golfer pose: -1 idle; 0→1 backswing; 1→0 downswing; <0 follow.
	if not active or (_t_takeaway < 0.0 and not dragging):
		return -1.0
	var lane := _lane_len()
	if lane < 1.0:
		return 0.0
	if _t_impact >= 0.0:
		var hold := _follow_through * maxf(size.y, 1.0) / lane
		return -clampf(maxf(hold, 0.2), 0.0, 1.2)
	if not had_top:
		return clampf(_disp / lane, 0.0, 1.2)
	if _disp < 0.0:
		return clampf(_disp / lane, -1.2, 0.0)
	var peak := maxf(_peak_disp, 1.0)
	return clampf(_disp / peak, 0.0, 1.0)


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
	if _is_putt() or _is_chip():
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
	_peak_vel = 0.0
	_vel_at_top = 0.0
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
			## Lane is the stroke axis (marks + progress share it). Finger may leave —
			## putt path_error uses lateral; full path comes from tempo grade.
			_address = address_hint()
			_axis = (top_hint() - address_hint()).normalized()
			if _axis.length_squared() < 0.5:
				_axis = Vector2(0, 1)
			delta = _smoothed - _address
			_disp = delta.dot(_axis)  # Seed baseline so this lock frame reads as zero
			# velocity/accel instead of a phantom spike computed against the pre-lock
			# default of 0 — that phantom jump was landing at ~400+ on max_accel,
			# dwarfing the real 8-32 penalty range, on every single swing.
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
	var accel_n := absf(accel) / maxf(size.y, 1.0)

	if not had_top:
		_peak_vel = maxf(_peak_vel, absf(_vel))

	# Lateral (perp to stroke axis) — putt line grade. Putt axis = lane.
	var perp := Vector2(-_axis.y, _axis.x)
	var lat := delta.dot(perp) / maxf(size.y, 1.0)
	if absf(lat) > absf(_max_lateral):
		_max_lateral = lat

	var seg := _smoothed - _last_pos
	var jerk_ang := 0.0
	var have_jerk := false
	if seg.length_squared() > 4.0:
		var seg_dir := seg.normalized()
		if _prev_seg_dir.length_squared() > 0.5:
			jerk_ang = absf(_prev_seg_dir.angle_to(seg_dir))
			have_jerk = true
		_prev_seg_dir = seg_dir

	var was_had_top := had_top
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
			_vel_at_top = absf(_vel)
			_t_top = now
			_top_flash_until = Time.get_ticks_msec() + 320
			moment.emit("top")
			live_changed.emit()

	# The frame where velocity actually reverses direction is guaranteed to show
	# a sharp accel/jerk value regardless of swing quality — that's just what a
	# reversal is. Fold both into the running max everywhere EXCEPT that one
	# frame, so a controlled pause at the top doesn't register as a violent spike.
	var is_top_frame := not was_had_top and had_top
	if not is_top_frame:
		_max_accel = maxf(_max_accel, accel_n)
		if have_jerk:
			_max_jerk = maxf(_max_jerk, jerk_ang)

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
		"follow_cap_frac": _putt_follow_cap_frac() if _is_putt() else 1.0,
		"max_lateral": _max_lateral,
		"incomplete": incomplete,
		"vel_at_top": _vel_at_top,
		"peak_vel": _peak_vel,
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
		_draw_golfer()
		return
	if _is_chip():
		_draw_chip()
		_draw_golfer()
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
	_draw_golfer()


func _draw_golfer() -> void:
	## Pose tracks live_stroke_u — top-left stage, does not replace coach.
	if not active and _t_impact < 0.0:
		return
	var pair: Array = _golfer_pose_pair()
	var a: Texture2D = pair[0]
	var b: Texture2D = pair[1]
	var t: float = float(pair[2])
	var tex_h := float(a.get_height())
	var scale := GOLFER_DRAW_H / maxf(tex_h, 1.0)
	var tw := float(a.get_width()) * scale
	var th := GOLFER_DRAW_H
	var origin := Vector2(GOLFER_MARGIN, GOLFER_MARGIN)
	var pad := 6.0
	var stage := Rect2(origin - Vector2(pad, pad), Vector2(tw + pad * 2.0, th + pad * 2.0))
	_draw_golfer_stage(stage)
	var col_a := Color(1, 1, 1, 1.0 - t * 0.85)
	var col_b := Color(1, 1, 1, t)
	draw_texture_rect(a, Rect2(origin, Vector2(tw, th)), false, col_a)
	if t > 0.02:
		draw_texture_rect(b, Rect2(origin, Vector2(tw, th)), false, col_b)


func _draw_golfer_stage(stage: Rect2) -> void:
	## Mini sky + grass window so the figure reads grounded.
	var grass_h := stage.size.y * 0.30
	var sky_h := stage.size.y - grass_h
	var sky := Rect2(stage.position, Vector2(stage.size.x, sky_h))
	var grass := Rect2(Vector2(stage.position.x, stage.position.y + sky_h), Vector2(stage.size.x, grass_h))
	draw_rect(sky, GOLFER_SKY, true)
	## Sparse sky dither (crunchy, not AA).
	var step := 4.0
	var x := sky.position.x
	while x < sky.end.x:
		var y := sky.position.y
		while y < sky.end.y:
			if int(x + y) % 8 == 0:
				draw_rect(Rect2(x, y, 2.0, 2.0), GOLFER_SKY_HI, true)
			y += step
		x += step
	draw_rect(grass, GOLFER_GRASS, true)
	## Horizon tufts.
	var tx := grass.position.x + 2.0
	while tx < grass.end.x - 2.0:
		draw_rect(Rect2(tx, grass.position.y, 2.0, 3.0), GOLFER_GRASS_TIP, true)
		tx += 5.0
	draw_rect(stage, GOLFER_STAGE_EDGE, false, 2.0)


func _golfer_pose_pair() -> Array:
	## Returns [tex_a, tex_b, blend 0..1]. Putt/chip use short-stroke frames.
	var addr: Texture2D
	var mid: Texture2D
	var top: Texture2D
	var impact: Texture2D
	var follow: Texture2D
	if _is_putt():
		addr = TEX_GOLFER_PUTT_ADDRESS
		mid = TEX_GOLFER_PUTT_MID
		top = TEX_GOLFER_PUTT_TOP
		impact = TEX_GOLFER_PUTT_IMPACT
		follow = TEX_GOLFER_PUTT_FOLLOW
	elif _is_chip():
		addr = TEX_GOLFER_CHIP_ADDRESS
		mid = TEX_GOLFER_CHIP_MID
		top = TEX_GOLFER_CHIP_TOP
		impact = TEX_GOLFER_CHIP_IMPACT
		follow = TEX_GOLFER_CHIP_FOLLOW
	else:
		addr = TEX_GOLFER_ADDRESS
		mid = TEX_GOLFER_MID
		top = TEX_GOLFER_TOP
		impact = TEX_GOLFER_IMPACT
		follow = TEX_GOLFER_FOLLOW
	var u := live_stroke_u()
	## Idle sentinel -1 (no takeaway yet) → address. Post-top negatives → follow.
	if u < 0.0:
		if had_top or _t_impact >= 0.0:
			var f := clampf(-u, 0.0, 1.0)
			return [impact, follow, f]
		return [addr, addr, 0.0]
	if not had_top:
		## Backswing 0→1: address → mid → top.
		if u <= 0.5:
			return [addr, mid, clampf(u * 2.0, 0.0, 1.0)]
		return [mid, top, clampf((u - 0.5) * 2.0, 0.0, 1.0)]
	## Downswing 1→0: top → impact.
	return [top, impact, clampf(1.0 - u, 0.0, 1.0)]


func _draw_putt() -> void:
	## Cool water-palette skin; same landmark roles as full swing.
	var r := Rect2(Vector2.ZERO, size).grow(-8.0)
	draw_rect(r, Color(0.06, 0.12, 0.16, 0.78), true)
	draw_rect(r, Color(0.35, 0.7, 0.85, 0.75), false, 3.0)

	var start := address_hint()
	var top := top_hint()
	var lane := _lane_len()
	## After lock, address is snapped to the rail — keep marks on-lane.
	var addr := start if _axis_locked or not dragging else (
		_address if dragging or _t_takeaway >= 0.0 else start
	)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)

	_draw_putt_lane_tex(start, top)
	# Widening edge guides stay procedural (line affordance).
	_draw_putt_arc_edges(start, top, Color(0.3, 0.55, 0.7, 0.55))
	_draw_putt_soft_scale(start, top)
	_draw_putt_follow_cue(addr)

	if putt_show_marker:
		_draw_putt_practice_marker(start, top)

	_draw_landmark_tex(
		TEX_PUTT_TOP,
		top if _peak_disp <= 1.0 else _lane_peak_pos(),
		LANDMARK_DIAM
	)
	_draw_putt_address(addr, pulse)

	if active and not dragging and _t_impact < 0.0:
		var coach_p := start.lerp(top, 0.28)
		_draw_landmark_tex(TEX_PUTT_COACH, coach_p, 44.0, Color(1, 1, 1, 0.55 + 0.35 * pulse))

	if dragging and _axis_locked:
		draw_line(start, _lane_peak_pos(), trail_color(), 8.0, false)

	_draw_trail()
	if dragging:
		draw_circle(_smoothed, 10.0, Color(0.7, 0.95, 1.0, 0.9))


func _draw_putt_lane_tex(start: Vector2, top: Vector2, tex: Texture2D = TEX_PUTT_LANE) -> void:
	var mid := (start + top) * 0.5
	var dist := start.distance_to(top)
	var tex_size := tex.get_size()
	# Match mid-stroke arc width (~2 × arc_allowance(0.5) × pad) so the strip isn't thinner than the grade.
	var sx := 56.0 / maxf(tex_size.x, 1.0)
	var sy := dist / maxf(tex_size.y, 1.0)
	draw_set_transform(mid, (top - start).angle() - PI * 0.5, Vector2(sx, sy))
	draw_texture(tex, -tex_size * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_putt_arc_edges(start: Vector2, top: Vector2, edge_c: Color, arc_scale_mul: float = 1.0) -> void:
	var steps := 8
	var perp := Vector2(-(top - start).y, (top - start).x).normalized()
	for i in range(steps):
		var u0 := float(i) / float(steps)
		var u1 := float(i + 1) / float(steps)
		var a0 := PuttStroke.arc_allowance(u0, arc_scale_mul) * size.y
		var a1 := PuttStroke.arc_allowance(u1, arc_scale_mul) * size.y
		var p0: Vector2 = start.lerp(top, u0)
		var p1: Vector2 = start.lerp(top, u1)
		draw_line(p0 + perp * a0, p1 + perp * a1, edge_c, 2.0, true)
		draw_line(p0 - perp * a0, p1 - perp * a1, edge_c, 2.0, true)


func _putt_follow_room(addr: Vector2) -> float:
	## Pixels past address before the pad's top margin.
	return maxf(addr.y - 20.0, 8.0)


func _putt_follow_target_frac() -> float:
	## Lane-fraction finish to match — live backswing after top, else committed pace.
	if had_top and _peak_disp > 1.0:
		return clampf(_peak_disp / _lane_len(), 0.0, 1.2)
	return clampf(putt_target_frac, PuttStroke.MARKER_MIN_FRAC, PuttStroke.MARKER_MAX_FRAC)


func _putt_follow_cap_frac() -> float:
	## Max follow_frac the pad can show — grade uses the same cap (drawn = graded).
	var lane := _lane_len()
	return clampf(_putt_follow_room(address_hint()) / maxf(lane, 1.0), 0.05, 1.2)


func _putt_follow_len(addr: Vector2) -> float:
	## Finish cue grows with pace/backswing; clamped to pad (not a fixed 12% stub).
	var want := _putt_follow_target_frac() * _lane_len()
	return minf(want, _putt_follow_room(addr))


func _draw_putt_follow_cue(
	addr: Vector2,
	line_rgb: Color = Color(0.45, 0.75, 0.9),
	ring_rgb: Color = Color(0.55, 0.85, 1.0)
) -> void:
	## Soft finish past address — open ring (no slash landmark).
	var through := _lane_through_dir()
	var tip := addr + through * _putt_follow_len(addr)
	var a := 0.7 if had_top else 0.45
	draw_line(addr, tip, Color(line_rgb.r, line_rgb.g, line_rgb.b, 0.28 * a), 5.0, true)
	draw_arc(tip, 11.0, 0.0, TAU, 24, Color(ring_rgb.r, ring_rgb.g, ring_rgb.b, 0.5 * a), 2.5, true)


func _draw_putt_address(
	p: Vector2,
	pulse: float,
	tex_start: Texture2D = TEX_PUTT_START,
	tex_through: Texture2D = TEX_PUTT_THROUGH,
	glow_rgb: Color = Color(0.45, 0.85, 1.0)
) -> void:
	if _axis_locked or _t_impact >= 0.0:
		_draw_pad_ball(p, _ball_pop_scale())
		return
	if not dragging and _t_impact < 0.0:
		draw_circle(p, 16.0 + pulse * 4.0, Color(glow_rgb.r, glow_rgb.g, glow_rgb.b, 0.18 + 0.15 * pulse))
	var tex: Texture2D = tex_through if had_top else tex_start
	_draw_landmark_tex(tex, p, LANDMARK_DIAM * (1.0 + 0.08 * pulse))


func _draw_putt_arc_lane(start: Vector2, top: Vector2, fill_c: Color, edge_c: Color) -> void:
	## Kept for callers/tests; putt draw uses lane tex + _draw_putt_arc_edges.
	draw_line(start, top, fill_c, 14.0, true)
	_draw_putt_arc_edges(start, top, edge_c)


func _draw_putt_soft_scale(start: Vector2, top: Vector2) -> void:
	## Absolute soft ruler — hairlines to cone edge; labels outside so thumb doesn't cover.
	for ft in PuttStroke.SCALE_LABELED_FT:
		_draw_putt_scale_tick(start, top, int(ft), true)
	for ft in PuttStroke.SCALE_TICK_FT:
		_draw_putt_scale_tick(start, top, int(ft), false)


func _draw_putt_scale_tick(start: Vector2, top: Vector2, ft: int, labeled: bool) -> void:
	var frac := PuttStroke.frac_for_ft(float(ft))
	## Floor-collapsed lengths share MARKER_MIN — skip so digits don't stack there.
	if frac <= PuttStroke.MARKER_MIN_FRAC or frac > PuttStroke.MARKER_MAX_FRAC:
		return
	var mark: Vector2 = start.lerp(top, frac)
	var along := top - start
	if along.length_squared() < 1.0:
		return
	## Tick stubs stay screen-right; labels sit left of the lane (not over the fill).
	var perp := Vector2(-along.y, along.x).normalized()
	var half := PuttStroke.arc_allowance(frac) * size.y
	var edge: Vector2 = mark + perp * half
	var thick := 2.0 if labeled else 1.5
	var a := 0.7 if labeled else 0.4
	var c := Color(0.55, 0.85, 0.95, a)
	draw_line(mark, edge, c, thick, true)
	if labeled:
		## Was 22 — the smallest text in the game and the hardest to read (5/7/S
		## blur together in Pixelify Sans without AA). Ticks are ~75px+ apart on
		## the log-spaced scale, so there's room to go bigger without stacking.
		const LABEL_PX := 28
		var s := str(ft)
		var tw := UiScale.FONT.get_string_size(
			s, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX
		).x
		## Right edge of digits clears the lane by a small gap.
		var label_at := Vector2(mark.x - half - 12.0 - tw, mark.y + 6.0)
		draw_string(
			UiScale.FONT, label_at, s,
			HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_PX,
			Color(0.6, 0.88, 0.95, 0.75)
		)


func _draw_chip_soft_scale(start: Vector2, top: Vector2) -> void:
	## Same "absolute soft ruler" idea as putt, but yards (not feet) graded against
	## the actual wedge's club_max_yards — a flat 20yd chip vs an 85yd Gap wedge maps
	## to a very different pad slice than putt's fixed putter-length ruler would.
	for yd in PuttStroke.CHIP_SCALE_LABELED_YD:
		_draw_chip_scale_tick(start, top, float(yd), true)
	for yd in PuttStroke.CHIP_SCALE_TICK_YD:
		_draw_chip_scale_tick(start, top, float(yd), false)


func _draw_chip_scale_tick(start: Vector2, top: Vector2, yd: float, labeled: bool) -> void:
	var frac := PuttStroke.frac_for_yd(yd, maxf(club_max_yards, 1.0))
	## Floor-collapsed lengths share MARKER_MIN — skip so digits don't stack there.
	if frac <= PuttStroke.MARKER_MIN_FRAC or frac > PuttStroke.MARKER_MAX_FRAC:
		return
	var mark: Vector2 = start.lerp(top, frac)
	var along := top - start
	if along.length_squared() < 1.0:
		return
	## Tick stubs stay screen-right; labels sit left of the lane (not over the fill).
	var perp := Vector2(-along.y, along.x).normalized()
	var half := PuttStroke.arc_allowance(frac, PuttStroke.CHIP_ARC_SCALE) * size.y
	var edge: Vector2 = mark + perp * half
	var thick := 2.0 if labeled else 1.5
	var a := 0.7 if labeled else 0.4
	var c := Color(CHIP_BORDER.r, CHIP_BORDER.g, CHIP_BORDER.b, a)
	draw_line(mark, edge, c, thick, true)
	if labeled:
		const LABEL_PX := 28
		var s := "%dy" % int(yd)
		var tw := UiScale.FONT.get_string_size(
			s, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX
		).x
		## Right edge of digits clears the lane by a small gap.
		var label_at := Vector2(mark.x - half - 12.0 - tw, mark.y + 6.0)
		draw_string(
			UiScale.FONT, label_at, s,
			HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_PX,
			Color(CHIP_BORDER.r, CHIP_BORDER.g, CHIP_BORDER.b, 0.85)
		)


func _draw_putt_practice_marker(
	start: Vector2,
	top: Vector2,
	band_c: Color = Color(0.35, 0.75, 0.9, 0.35),
	tick_c: Color = Color(0.55, 0.95, 1.0, 0.95)
) -> void:
	## Practice-only: PACE tick on the backswing (the length answer). No THRU destination —
	## through is the soft follow cue; mirroring pace past address flies off-pad on long putts.
	var tgt := clampf(putt_target_frac, PuttStroke.MARKER_MIN_FRAC, PuttStroke.MARKER_MAX_FRAC)
	var band := PuttStroke.BAND_HALF
	var mark: Vector2 = start.lerp(top, tgt)
	var band_lo: Vector2 = start.lerp(top, clampf(tgt - band, 0.0, 1.0))
	var band_hi: Vector2 = start.lerp(top, clampf(tgt + band, 0.0, 1.0))
	draw_line(band_lo, band_hi, band_c, 22.0, true)
	draw_line(mark + Vector2(-20, 0), mark + Vector2(20, 0), tick_c, 3.5, true)


func _draw_chip() -> void:
	## Warm sand/wedge palette, shorter lane than putt — shares putt's amplitude-pad
	## drawing helpers (lane, arc edges, follow cue, address ball, practice marker)
	## parameterized with chip's own textures/colors so it reads distinct at a glance.
	## Soft-scale ruler is yards (not putt's feet), graded against club_max_yards
	## (the actual wedge's max carry, set by ShotRoutine) rather than putt's fixed
	## putter-length default — playtest feedback: chip had no distance reference at
	## all before this, unlike putt's ruler.
	var r := Rect2(Vector2.ZERO, size).grow(-8.0)
	draw_rect(r, CHIP_BG, true)
	draw_rect(r, CHIP_BORDER, false, 3.0)

	var start := address_hint()
	var top := top_hint()
	var addr := start if _axis_locked or not dragging else (
		_address if dragging or _t_takeaway >= 0.0 else start
	)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)

	_draw_putt_lane_tex(start, top, TEX_CHIP_LANE)
	_draw_putt_arc_edges(start, top, CHIP_ARC_EDGE, PuttStroke.CHIP_ARC_SCALE)
	_draw_chip_soft_scale(start, top)
	_draw_putt_follow_cue(addr, CHIP_FOLLOW_LINE, CHIP_FOLLOW_RING)

	if putt_show_marker:
		_draw_putt_practice_marker(start, top, CHIP_MARKER_BAND, CHIP_MARKER_TICK)

	_draw_landmark_tex(
		TEX_CHIP_TOP,
		top if _peak_disp <= 1.0 else _lane_peak_pos(),
		LANDMARK_DIAM
	)
	_draw_putt_address(addr, pulse, TEX_CHIP_START, TEX_CHIP_THROUGH, CHIP_ADDRESS_GLOW)

	if active and not dragging and _t_impact < 0.0:
		var coach_p := start.lerp(top, 0.28)
		_draw_landmark_tex(TEX_CHIP_COACH, coach_p, 44.0, Color(1, 1, 1, 0.55 + 0.35 * pulse))

	if dragging and _axis_locked:
		draw_line(start, _lane_peak_pos(), trail_color(), 8.0, false)

	_draw_trail()
	if dragging:
		draw_circle(_smoothed, 10.0, CHIP_DRAG_DOT)


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
	var mid := (start + top) * 0.5
	var dist := start.distance_to(top)
	var tex_size := TEX_LANE.get_size()
	var sx := 28.0 / maxf(tex_size.x, 1.0)
	var sy := dist / maxf(tex_size.y, 1.0)
	draw_set_transform(mid, (top - start).angle() - PI * 0.5, Vector2(sx, sy))
	draw_texture(TEX_LANE, -tex_size * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_progress and dragging and _axis_locked:
		## No AA — Godot thick antialiased lines skew the bright spine a px or two.
		draw_line(start, _lane_peak_pos(), Color(0.45, 0.95, 0.55, 0.85), 10.0, false)


func _ft_floor_len(addr: Vector2) -> float:
	## Minimum follow-through TempoGrade.balance() actually requires, clamped to the
	## pad's top margin (same room clamp putt/chip use — drawn = graded).
	return minf(TempoGrade.ft_floor(shot_type) * size.y, _putt_follow_room(addr))


func _follow_cue_end(addr: Vector2) -> Vector2:
	## Anchored to ft_floor — this is the minimum, not a decorative "keep going" ring.
	return addr + _lane_through_dir() * _ft_floor_len(addr)


func _draw_follow_cue(addr: Vector2, a: float = 0.45) -> void:
	## Follow-through floor marker — open ring at the graded minimum length.
	var tip := _follow_cue_end(addr)
	draw_line(addr, tip, Color(0.55, 0.85, 0.55, 0.28 * a), 5.0, true)
	draw_arc(tip, 11.0, 0.0, TAU, 24, Color(0.6, 0.9, 0.55, 0.5 * a), 2.5, true)


func _draw_bs_floor_marker() -> void:
	## Backswing floor — the actual minimum TempoGrade.balance() grades against.
	## Pad marks only (no word labels): a double-tick "rung," amber and distinct from
	## the TEX_TOP chevron texture ("ideal") so players don't confuse "minimum to
	## avoid a penalty" with "target to aim for."
	var along := top_hint() - address_hint()
	if along.length_squared() < 1.0:
		return
	var p := _bs_floor_pos()
	var perp := Vector2(-along.y, along.x).normalized()
	var half := 14.0
	var c := Color(1.0, 0.65, 0.3, 0.85)
	draw_line(p - perp * half, p + perp * half, c, 3.0, true)
	draw_line(p - perp * half + along.normalized() * 4.0, p + perp * half + along.normalized() * 4.0, c, 1.5, true)


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
	## START → THROUGH after top → course ball once the stroke commits.
	if _axis_locked or _t_impact >= 0.0:
		_draw_pad_ball(p, _ball_pop_scale())
		return
	draw_circle(p, 22.0 + pulse * 6.0, Color(1.0, 0.85, 0.25, 0.15 + 0.15 * pulse))
	var tex: Texture2D = TEX_THROUGH if had_top else TEX_START
	_draw_landmark_tex(tex, p, LANDMARK_DIAM * (1.0 + 0.08 * pulse))


func _draw_idle_coach() -> void:
	var start := address_hint()
	var top := top_hint()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	_draw_pull_lane(false)
	_draw_follow_cue(start, 0.7)
	_draw_bs_floor_marker()
	_draw_landmark_tex(TEX_TOP, top, LANDMARK_DIAM)
	_draw_address_mark(start, pulse)
	# Takeaway cue between address and top
	var coach_p := start.lerp(top, 0.28)
	_draw_landmark_tex(TEX_COACH, coach_p, 44.0, Color(1, 1, 1, 0.55 + 0.35 * pulse))


func _draw_active_landmarks() -> void:
	## After lock, address is on the lane — same x as pull-lane progress / impact mark.
	var addr := (
		address_hint() if _axis_locked or _t_impact >= 0.0
		else (_address if dragging or _t_takeaway >= 0.0 else address_hint())
	)
	## Full swing: keep the top chevron on-lane (progress tip). Finger/trail may drift.
	var top_p := _lane_peak_pos() if _peak_disp > 1.0 else top_hint()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)

	_draw_follow_cue(addr, 0.55 if had_top else 0.35)
	_draw_bs_floor_marker()
	_draw_address_mark(addr, pulse)

	var flash := Time.get_ticks_msec() < _top_flash_until
	var top_mod := Color(1.2, 1.2, 1.2, 1.0) if flash else Color(1, 1, 1, 0.9)
	var top_d := LANDMARK_DIAM * (1.25 if had_top else 1.0)
	_draw_landmark_tex(TEX_TOP, top_p, top_d, top_mod)


func _draw_landmark_tex(tex: Texture2D, p: Vector2, diam: float, modulate: Color = Color.WHITE) -> void:
	var tex_size := tex.get_size()
	var s := diam / maxf(tex_size.x, 1.0)
	draw_set_transform(p, 0.0, Vector2(s, s))
	draw_texture(tex, -tex_size * 0.5, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trail() -> void:
	if trail.size() < 2:
		return
	var c := trail_color()
	for i in range(1, trail.size()):
		var a := float(i) / float(trail.size())
		draw_line(trail[i - 1], trail[i], Color(c.r, c.g, c.b, 0.25 + 0.6 * a), 4.0, true)

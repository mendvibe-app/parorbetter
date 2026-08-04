class_name GolfBall
extends CharacterBody2D

## Visual ball with height-based shadow + Trackman-style lofted flight tracer.
## Physics stay 2D top-down; _height fakes loft for arc readability.

signal settled(position: Vector2, lie_hint: String)
signal entered_hazard(kind: String)
signal holed_out
signal perfect_flash

enum State { IDLE, FLIGHT, ROLL, SETTLED }

## Screen-up loft multiplier for tracer (matches old ghost-arc language).
## Lift is divided by camera zoom so close-up chips don't paint a huge screen arc.
const TRACER_LIFT := 0.35
## Target on-screen trail thickness (px). World width = screen / zoom.
const TRACER_SCREEN_W := 3.2
const TRACER_SCREEN_W_PURE := 4.0
const TRACER_CAP := 128
const TRACER_CAP_PURE := 160
## Wet-marker dry: 0 = fresh tip, 1 = fully faded. Advances on roll after flight.
const TRACER_DRY_RATE := 0.95
## Landing target circle (screen px). Faint in air, lights up on first bounce.
const LAND_R_SCREEN := 15.0
const LAND_RING_W_SCREEN := 1.6

var state: State = State.IDLE
var spin: float = 0.0
var wind: Vector2 = Vector2.ZERO
var green_slope: Vector2 = Vector2.ZERO  ## fallback if no hole field
var _slope_hole: HoleData = null
var _green_center: Vector2 = Vector2.ZERO
var _air_timer: float = 0.0
var _air_duration: float = 1.0
var _height: float = 0.0
## Peak visual loft this flight (club loft × base). Used for tree carry checks.
var _height_peak: float = 0.0
var _last_safe_pos: Vector2 = Vector2.ZERO
var _lie: String = "Tee"
## Rough severity: Buried / Average / SittingUp when toggle on; else "".
var _lie_severity: String = ""
var _trail: Line2D
var _trail_grad: Gradient
var _trail_dry: float = 0.0  ## 0 wet … 1 dry (fade from launch toward ball)
var _land_mark: Node2D
var _land_fill: Polygon2D
var _land_ring: Line2D
## 0 = soft pre-land / faded; 1 = impact flash. Only spikes on land, decays on roll.
var _land_pulse: float = 0.0
var _is_perfect_shot: bool = false

var _shot_origin: Vector2 = Vector2.ZERO
var _launch_dir: Vector2 = Vector2(0, -1)
var _pin_dir: Vector2 = Vector2(0, -1)
var _planned_distance_px: float = 0.0
var _landing_speed: float = 0.0
var _air_fraction: float = 0.78
var _is_putt: bool = false
var _spin_vis: float = 0.0
## Sample surface under the ball while rolling (fairway/rough/sand/green).
var ground_lie_at: Callable = Callable()

@onready var visual: Sprite2D = $Visual
@onready var shadow: Sprite2D = $Shadow
@onready var glow: Sprite2D = $Glow
@onready var spin_fx: Sprite2D = $SpinFX
@onready var area: Area2D = $Area


const BALL_R := 3.5
## On-green draw radius — smaller so 40 ft is many ball-widths (flight stays BALL_R).
const BALL_R_PUTT := 1.0
## Side / along break accel scale (px/s² per unit slope). Tuned so mid-slope 40 ft bends ~2 ball-widths.
const PUTT_BREAK_LATERAL := 90.0
const PUTT_BREAK_ALONG := 55.0

var _ball_scale: float = 1.0
var _shadow_scale: float = 1.0
var _glow_scale: float = 1.0

func _ready() -> void:
	_apply_lie_visual()
	_trail = Line2D.new()
	# Width is screen-constant via _sync_trail_visual() (zoom-aware).
	_trail.width = TRACER_SCREEN_W
	_trail.default_color = Color(0.55, 0.95, 1.0, 0.92)
	# Wet-marker gradient: oldest points transparent, tip (at ball) opaque.
	_trail_grad = Gradient.new()
	_trail.gradient = _trail_grad
	_sync_trail_gradient()
	# Solid ribbon reads better as Trackman than the soft trail tex at distance.
	_trail.z_index = 20
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_build_land_mark()
	# Host on hole root so points are true world coords (top_level under ball was flaky).
	call_deferred("_mount_trail")
	area.area_entered.connect(_on_area_entered)
	_last_safe_pos = global_position
	set_physics_process(false)


func _build_land_mark() -> void:
	## Soft white target disc + ring at planned/actual first bounce.
	_land_mark = Node2D.new()
	_land_mark.z_index = 19
	_land_mark.visible = false
	_land_fill = Polygon2D.new()
	_land_fill.color = Color(1, 1, 1, 0.14)
	_land_ring = Line2D.new()
	_land_ring.default_color = Color(1, 1, 1, 0.55)
	_land_ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_land_ring.end_cap_mode = Line2D.LINE_CAP_ROUND
	_land_ring.joint_mode = Line2D.LINE_JOINT_ROUND
	_land_ring.closed = true
	_land_mark.add_child(_land_fill)
	_land_mark.add_child(_land_ring)


func _mount_trail() -> void:
	var host := get_parent()
	if host == null or _trail == null:
		return
	if _trail.get_parent() != host:
		if _trail.get_parent():
			_trail.get_parent().remove_child(_trail)
		host.add_child(_trail)
	_trail.position = Vector2.ZERO
	if _land_mark and _land_mark.get_parent() != host:
		if _land_mark.get_parent():
			_land_mark.get_parent().remove_child(_land_mark)
		host.add_child(_land_mark)


## Clears the flight tracer independent of a full ball reset — call this as soon as
## the previous shot's result is dismissed, so the old tracer doesn't linger through
## the next shot's read/club/aim routine.
func clear_trail() -> void:
	_trail.clear_points()
	_trail_dry = 0.0
	_trail.modulate.a = 1.0
	_sync_trail_gradient()
	_hide_land_mark()


func _camera_zoom() -> float:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	return cam.zoom.x if cam else 1.0


func _sync_trail_visual() -> void:
	## Keep ribbon ~constant on screen; fixed world width blows up when zoomed in (chips).
	if _trail == null:
		return
	var z := maxf(_camera_zoom(), 0.35)
	var sw := TRACER_SCREEN_W_PURE if _is_perfect_shot else TRACER_SCREEN_W
	_trail.width = sw / z
	_sync_trail_gradient()
	_sync_land_mark_visual()


func _sync_trail_gradient() -> void:
	## Wet marker: launch end dries first; tip stays wet until _trail_dry rises on land.
	## RGB from default_color (strike quality); gradient only owns the alpha falloff.
	if _trail_grad == null or _trail == null:
		return
	var c := _trail.default_color
	var peak := clampf(1.0 - _trail_dry, 0.0, 1.0)
	# As dry rises, opaque band shrinks toward the ball (offset 1.0).
	var mid_a := lerpf(0.22, 0.0, _trail_dry) * c.a
	var mid_b := lerpf(0.62, 0.05, _trail_dry) * c.a
	var tip := peak * c.a
	_trail_grad.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	_trail_grad.colors = PackedColorArray([
		Color(c.r, c.g, c.b, 0.0),
		Color(c.r, c.g, c.b, mid_a * peak),
		Color(c.r, c.g, c.b, mid_b * peak),
		Color(c.r, c.g, c.b, tip),
	])


func _planned_land_pos() -> Vector2:
	return _shot_origin + _launch_dir * (_planned_distance_px * _air_fraction)


func _circle_pts(r: float, n: int = 36) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a := TAU * float(i) / float(n)
		pts[i] = Vector2(cos(a), sin(a)) * r
	return pts


func _hide_land_mark() -> void:
	_land_pulse = 0.0
	if _land_mark:
		_land_mark.visible = false
		_land_mark.modulate.a = 1.0


func _show_land_mark(pos: Vector2, flash: bool) -> void:
	if _land_mark == null or _is_putt:
		return
	_land_mark.position = pos
	_land_mark.visible = true
	_land_mark.modulate.a = 1.0
	# Bright only on impact; flight keeps pulse at 0 (soft ring).
	_land_pulse = 1.0 if flash else 0.0
	_sync_land_mark_visual()


func _sync_land_mark_visual() -> void:
	if _land_mark == null or not _land_mark.visible:
		return
	var z := maxf(_camera_zoom(), 0.35)
	var p := _land_pulse
	var r_screen := LAND_R_SCREEN * (1.0 + p * 0.35)
	var r := r_screen / z
	var pts := _circle_pts(r)
	_land_fill.polygon = pts
	_land_ring.points = pts
	_land_ring.width = LAND_RING_W_SCREEN * (1.0 + p * 0.5) / z
	# Soft target in air (p=0); bright only while impact pulse is up.
	_land_fill.color = Color(1.0, 1.0, 1.0, lerpf(0.10, 0.58, p))
	_land_ring.default_color = Color(1.0, 1.0, 1.0, lerpf(0.42, 1.0, p))


func reset_at(pos: Vector2, lie: String = "Tee") -> void:
	global_position = pos
	_last_safe_pos = pos
	_apply_lie_string(lie, true)
	velocity = Vector2.ZERO
	spin = 0.0
	_height = 0.0
	_height_peak = 0.0
	_is_putt = false
	_is_perfect_shot = false
	state = State.IDLE
	_planned_distance_px = 0.0
	_trail.clear_points()
	_trail_dry = 0.0
	_trail.modulate.a = 1.0
	_sync_trail_gradient()
	_hide_land_mark()
	visual.rotation = 0.0
	visual.self_modulate = Color(1, 1, 1)
	shadow.position = Vector2.ZERO
	glow.visible = false
	spin_fx.visible = false
	_apply_lie_visual()
	set_physics_process(false)


func launch(
	result: ShotResult,
	target_pos: Vector2,
	club_max_yards: float,
	p_wind: Vector2,
	p_slope: Vector2,
	p_hole: HoleData = null,
	p_green_center: Vector2 = Vector2.ZERO,
	shot_type: String = "full"
) -> void:
	var to_pin := target_pos - global_position
	_pin_dir = to_pin.normalized()
	if _pin_dir == Vector2.ZERO:
		_pin_dir = Vector2(0, -1)

	var launch_data := BallPhysics.launch_velocity(
		result, to_pin, club_max_yards, _lie, _lie_severity, shot_type
	)
	velocity = launch_data["velocity"]
	spin = launch_data["spin"]
	_air_duration = launch_data["airborne_time"]
	_air_timer = 0.0
	_height = 0.0
	var loft_h := clampf(float(launch_data.get("loft", 0.9)), 0.4, 1.55)
	_height_peak = (28.0 + velocity.length() * 0.02) * loft_h
	_is_putt = bool(launch_data.get("is_putt", _lie == "Green"))
	if _is_putt:
		_height_peak = 0.0
	wind = Vector2.ZERO if _is_putt else p_wind
	green_slope = p_slope
	_slope_hole = p_hole
	_green_center = p_green_center
	_shot_origin = global_position
	_launch_dir = launch_data["launch_dir"]
	# Don't launch nearly backward vs pin (putt break + short greenside path/spin).
	var pin_align := 0.25 if _is_putt else 0.50
	if _launch_dir.dot(_pin_dir) < pin_align:
		_launch_dir = (_launch_dir + _pin_dir * 2.5).normalized()
		if _launch_dir.dot(_pin_dir) < pin_align:
			_launch_dir = _pin_dir
		if _is_putt:
			velocity = _launch_dir * float(launch_data["landing_speed"])
		else:
			velocity = _launch_dir * maxf(velocity.length(), 1.0)
	_planned_distance_px = launch_data["travel_px"]
	_landing_speed = launch_data["landing_speed"]
	_air_fraction = launch_data["air_fraction"]
	_trail.clear_points()
	_trail.position = Vector2.ZERO
	_trail.modulate.a = 1.0
	_trail_dry = 0.0
	_hide_land_mark()
	_is_perfect_shot = result.is_perfect() and result.stance_stability >= 0.72
	if _is_perfect_shot:
		perfect_flash.emit()
		visual.self_modulate = Color(1.0, 0.95, 0.55)
		_trail.default_color = Color(1.0, 0.85, 0.25, 0.95)  # gold — reserved for pure strikes
	else:
		visual.self_modulate = Color(1, 1, 1)
		# Same good/ok/bad palette already used by the swing-trail color and tempo
		# needle (tempo_gesture.trail_color(), meter_display.gd) — reuse, don't invent.
		match result.contact_quality:
			ShotResult.ContactQuality.PERFECT:
				_trail.default_color = Color(0.35, 0.92, 0.45, 0.92)  # green
			ShotResult.ContactQuality.GOOD:
				_trail.default_color = Color(0.95, 0.85, 0.25, 0.92)  # amber
			_:  # THIN, FAT, MISS
				_trail.default_color = Color(0.95, 0.35, 0.3, 0.92)  # red
	_sync_trail_visual()

	if _is_putt or _air_fraction <= 0.001:
		state = State.ROLL
		velocity = _launch_dir * _landing_speed
	else:
		state = State.FLIGHT
		# Soft target where first bounce is planned; lights up in _begin_roll.
		_show_land_mark(_planned_land_pos(), false)
	set_physics_process(true)


func air_progress() -> float:
	## 0..1 through FLIGHT; 1 once rolling/settled. Used by up-and-in camera.
	if state == State.ROLL or state == State.SETTLED:
		return 1.0
	if state != State.FLIGHT:
		return 0.0
	return clampf(_air_timer / maxf(_air_duration, 0.01), 0.0, 1.0)


func get_last_safe() -> Vector2:
	return _last_safe_pos


func set_lie(lie: String) -> void:
	_apply_lie_string(lie, false)
	_apply_lie_visual()


func get_lie() -> String:
	return _lie


func get_lie_severity() -> String:
	return _lie_severity


## Assign lie string + severity roll rules. force_roll: always re-evaluate (reset_at).
func _apply_lie_string(lie: String, force_roll: bool) -> void:
	var prev := _lie
	_lie = lie
	if lie != "Rough" or not GameState.rough_severity_enabled:
		_lie_severity = ""
		return
	# Enter Rough (or forced reset already in Rough): roll once.
	if force_roll or prev != "Rough":
		_lie_severity = BallPhysics.roll_rough_severity()
	# else stay Rough → keep existing severity


func _apply_lie_visual() -> void:
	## Flight stays readable (BALL_R); green shrinks so 18 ft isn't 2 ball-widths.
	var r := BALL_R_PUTT if _lie == "Green" else BALL_R
	var tex_w := float(visual.texture.get_width()) if visual.texture else 961.0
	_ball_scale = (r * 2.0) / tex_w
	visual.scale = Vector2.ONE * _ball_scale
	# Shadow texture holds a wide soft ellipse; size it to a bit over ball width.
	var sh_w := float(shadow.texture.get_width()) if shadow.texture else 512.0
	_shadow_scale = ((r + 2.0) * 2.6) / sh_w
	shadow.scale = Vector2(_shadow_scale, _shadow_scale)
	shadow.modulate.a = 0.85
	# Glow ring ~2.6x ball diameter, spin arcs hug the ball.
	if glow.texture:
		_glow_scale = (r * 5.2) / float(glow.texture.get_width())
		glow.scale = Vector2.ONE * _glow_scale
	if spin_fx.texture:
		spin_fx.scale = Vector2.ONE * (r * 3.4) / float(spin_fx.texture.get_width())


func distance_traveled_yards() -> float:
	return BallPhysics.pixels_to_yards((global_position - _shot_origin).length())


func _physics_process(delta: float) -> void:
	match state:
		State.FLIGHT:
			_process_flight(delta)
		State.ROLL:
			_process_roll(delta)
		_:
			pass
	# Flight: lofted Trackman tracer. Roll: freeze points and dry the ribbon (wet marker)
	# into the land circle. Impact flash on land mark decays during roll only.
	if not _is_putt:
		if state == State.FLIGHT:
			_sync_trail_visual()
			var lift := TRACER_LIFT / maxf(_camera_zoom(), 0.35)
			_trail.add_point(global_position + Vector2(0.0, -_height * lift))
			var cap := TRACER_CAP_PURE if _is_perfect_shot else TRACER_CAP
			if _trail.get_point_count() > cap:
				_trail.remove_point(0)
		elif state == State.ROLL:
			if _trail.get_point_count() > 0:
				# Dry from launch end toward the land circle; drop fully-faded head points.
				_trail_dry = minf(_trail_dry + delta * TRACER_DRY_RATE, 1.0)
				if _trail_dry > 0.28 and _trail.get_point_count() > 6:
					_trail.remove_point(0)
			if _land_mark and _land_mark.visible:
				# Flash only at bounce; ease back to soft then fade out with the roll.
				_land_pulse = maxf(_land_pulse - delta * 2.4, 0.0)
				if _land_pulse <= 0.0:
					_land_mark.modulate.a = maxf(_land_mark.modulate.a - delta * 1.25, 0.0)
					if _land_mark.modulate.a <= 0.02:
						_hide_land_mark()
			_sync_trail_visual()
	_spin_vis += spin * delta * 4.0 + velocity.length() * 0.002
	visual.rotation = _spin_vis
	var s := 1.0 + _height * 0.006
	visual.scale = Vector2.ONE * (_ball_scale * s)
	# Shadow drops "below" ball as height rises (screen +y)
	shadow.position = Vector2(spin * 2.0, 6.0 + _height * 0.35)
	shadow.scale = Vector2(_shadow_scale * (1.0 + _height * 0.012), _shadow_scale * (0.85 + _height * 0.006))
	shadow.modulate.a = clampf(0.85 - _height * 0.012, 0.2, 0.85)
	# Spin arcs show while rolling with meaningful sidespin
	var show_spin := state == State.ROLL and absf(spin) > 0.35
	spin_fx.visible = show_spin
	if show_spin:
		spin_fx.rotation += signf(spin) * delta * 9.0
		spin_fx.modulate.a = clampf(absf(spin) * 0.9, 0.25, 0.85)
	# Gold glow rides along on pure strikes
	if _is_perfect_shot and (state == State.FLIGHT or state == State.ROLL):
		glow.visible = true
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.08
		glow.scale = Vector2.ONE * (_glow_scale * s * pulse)
		glow.modulate.a = 0.8
	elif state == State.SETTLED or state == State.IDLE:
		glow.visible = false


func _traveled_along() -> float:
	return maxf((global_position - _shot_origin).dot(_launch_dir), 0.0)


func _process_flight(delta: float) -> void:
	_air_timer += delta
	var t := _air_timer / maxf(_air_duration, 0.01)
	_height = sin(clampf(t, 0.0, 1.0) * PI) * _height_peak

	velocity += wind * delta * 6.0
	# Curve offline relative to launch. Scale by forward speed so weak short pitches
	# don't get absolute sidespin that reverse/sideways the ball (plan ~3 yd cases).
	var flight_right := Vector2(-_launch_dir.y, _launch_dir.x)
	var along_spd := maxf(velocity.dot(_launch_dir), 0.0)
	var spin_scale := clampf(along_spd / 180.0, 0.08, 1.0)
	velocity += flight_right * spin * 28.0 * delta * spin_scale
	# Never allow flight to reverse past the pin/launch line from spin alone.
	var along_after := velocity.dot(_launch_dir)
	if along_after < along_spd * 0.15:
		var lat := velocity.dot(flight_right)
		velocity = _launch_dir * maxf(along_spd * 0.35, 12.0) + flight_right * lat * 0.55

	var collision := move_and_collide(velocity * delta)
	var along := _traveled_along()
	var air_limit := _planned_distance_px * _air_fraction

	if collision or t >= 1.0 or along >= air_limit:
		_begin_roll()


func _begin_roll() -> void:
	_height = 0.0
	state = State.ROLL
	var speed := _landing_speed
	if speed <= 1.0:
		speed = maxf(velocity.length() * 0.35, 20.0)
	velocity = _launch_dir * speed
	# Snap target to actual first bounce and illuminate — tracer tip dries into this.
	_show_land_mark(global_position, true)
	# Flight ignores ground under the arc; re-check hazards, then sample lie.
	for other in area.get_overlapping_areas():
		_on_area_entered(other)
		if state != State.ROLL:
			return
	_sync_ground_lie()


func _sync_ground_lie() -> void:
	## Real golf: friction follows the surface under the ball right now.
	if state != State.ROLL or not ground_lie_at.is_valid():
		return
	var lie: String = ground_lie_at.call(global_position)
	if lie != _lie:
		set_lie(lie)


func _slope_at_ball() -> Vector2:
	if _slope_hole:
		return _slope_hole.green_slope_at(global_position - _green_center)
	return green_slope


func _process_roll(delta: float) -> void:
	_sync_ground_lie()
	_height = move_toward(_height, 0.0, delta * 80.0)
	var friction := 2.4
	match _lie:
		"Green":
			friction = 1.8
		"Fairway":
			friction = 2.4
		"Rough":
			friction = 4.5
		"Sand":
			friction = 7.0
		"Tee":
			friction = 2.4
		_:
			friction = 3.0

	var slope := _slope_at_ball()
	if _is_putt:
		# Break pulls offline; can fight aim (skill reads matter)
		var right := Vector2(-_pin_dir.y, _pin_dir.x)
		var break_amt := slope.dot(right) * PUTT_BREAK_LATERAL
		var along_break := slope.dot(_pin_dir) * PUTT_BREAK_ALONG
		velocity += right * break_amt * delta
		velocity += _pin_dir * along_break * delta
	elif _lie == "Green":
		velocity += slope * 16.0 * delta

	velocity = velocity.move_toward(Vector2.ZERO, friction * 60.0 * delta)

	if not _is_putt:
		var roll_right := Vector2(-_launch_dir.y, _launch_dir.x)
		var roll_along := maxf(velocity.dot(_launch_dir), 0.0)
		var roll_spin_scale := clampf(roll_along / 120.0, 0.08, 1.0)
		velocity += roll_right * spin * 8.0 * delta * roll_spin_scale
		spin = move_toward(spin, 0.0, delta * 1.8)
		# Keep roll from walking backwards off a short miss.
		if velocity.dot(_pin_dir) < -20.0 and _planned_distance_px < BallPhysics.yards_to_pixels(50.0):
			velocity += _pin_dir * 40.0 * delta
	else:
		# Mild anti-teleport only — break can still pull offline / slightly against aim
		var toward := velocity.dot(_pin_dir)
		if toward < -80.0:
			velocity += _pin_dir * (-toward - 80.0) * 0.2

	var along := _traveled_along()
	var remain := _planned_distance_px - along
	if remain < 40.0 and not _is_putt:
		var limit := maxf(remain * 3.5, 8.0)
		if velocity.length() > limit:
			velocity = velocity.normalized() * limit
	if along >= _planned_distance_px and not _is_putt:
		_finish_settle()
		return
	# Putts: stop by speed, allow break past planned if overhit
	if _is_putt and along >= _planned_distance_px * 1.15:
		velocity *= 0.92

	var collision := move_and_collide(velocity * delta)
	if collision and not _is_putt:
		velocity = velocity.bounce(collision.get_normal()) * 0.3

	if _lie == "Green":
		AudioBus.set_roll_intensity(velocity.length() / 400.0)
	else:
		AudioBus.set_roll_intensity(0.0)

	if velocity.length() < 10.0:
		_finish_settle()


func _finish_settle() -> void:
	velocity = Vector2.ZERO
	state = State.SETTLED
	set_physics_process(false)
	AudioBus.set_roll_intensity(0.0)
	# Finish drying the marker into the land circle after stop (linger under result glance).
	if not _is_putt and (_trail.get_point_count() > 0 or (_land_mark and _land_mark.visible)):
		var tw := create_tween()
		tw.tween_method(_set_trail_dry, _trail_dry, 1.0, 0.85)
		tw.parallel().tween_property(_trail, "modulate:a", 0.0, 1.1)
		if _land_mark and _land_mark.visible:
			tw.parallel().tween_property(_land_mark, "modulate:a", 0.0, 1.15)
	# Keep Trackman arc + land disc until fully dry; next launch/reset clears it.
	if _lie != "Water" and _lie != "OOB":
		_last_safe_pos = global_position
	settled.emit(global_position, _lie)


func _set_trail_dry(v: float) -> void:
	_trail_dry = clampf(v, 0.0, 1.0)
	_sync_trail_gradient()
	# Trim the dried launch end while settling
	if _trail and _trail_dry > 0.4 and _trail.get_point_count() > 4:
		_trail.remove_point(0)


func _on_area_entered(other: Area2D) -> void:
	# Trees: roll always blocks; flight only if below canopy (apex can carry over).
	if other.is_in_group("tree"):
		if state == State.SETTLED or state == State.IDLE:
			return
		if state == State.FLIGHT:
			var need := float(other.get_meta("canopy_h", 30.0))
			if _height >= need:
				return  # over
		_apply_lie_string("Trees", false)
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		settled.emit(global_position, _lie)
		return
	# Ground groups (water/sand/fairway/…) only count on ROLL.
	if state != State.ROLL:
		return
	if other.is_in_group("cup"):
		# Area overlap includes this ball's ~10px sensor; require center inside the cup.
		var cs := other.get_child(0) as CollisionShape2D
		var cup_r: float = cs.shape.radius if cs and cs.shape is CircleShape2D else 3.0
		if global_position.distance_to(other.global_position) > cup_r:
			return
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		holed_out.emit()
		return
	if other.is_in_group("water"):
		# Putting surface wins — island water volumes can graze the green edge.
		for a in area.get_overlapping_areas():
			if a.is_in_group("green"):
				_apply_lie_string("Green", false)
				return
		_apply_lie_string("Water", false)
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		entered_hazard.emit("water")
		return
	if other.is_in_group("oob"):
		_apply_lie_string("OOB", false)
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		entered_hazard.emit("oob")
		return
	if other.is_in_group("sand"):
		_apply_lie_string("Sand", false)
	elif other.is_in_group("green"):
		_apply_lie_string("Green", false)
	elif other.is_in_group("tee"):
		_apply_lie_string("Tee", false)
	elif other.is_in_group("fairway"):
		_apply_lie_string("Fairway", false)
	elif other.is_in_group("rough"):
		_apply_lie_string("Rough", false)


func flash_perfect() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "self_modulate", Color(1, 0.9, 0.35), 0.05)
	tw.tween_property(visual, "self_modulate", Color(1, 1, 1), 0.3)
	# Expanding gold ring burst
	glow.visible = true
	glow.modulate.a = 1.0
	glow.scale = Vector2.ONE * (_glow_scale * 0.4)
	var gw := create_tween()
	gw.tween_property(glow, "scale", Vector2.ONE * (_glow_scale * 1.15), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	gw.parallel().tween_property(glow, "modulate:a", 0.8, 0.28)

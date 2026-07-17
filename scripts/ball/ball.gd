class_name GolfBall
extends CharacterBody2D

## Visual ball with height-based shadow, speed trail, and launch arc ghosts.
## Physics stay 2D top-down; _height fakes loft for arc readability.

signal settled(position: Vector2, lie_hint: String)
signal entered_hazard(kind: String)
signal holed_out
signal perfect_flash

enum State { IDLE, FLIGHT, ROLL, SETTLED }

var state: State = State.IDLE
var spin: float = 0.0
var wind: Vector2 = Vector2.ZERO
var green_slope: Vector2 = Vector2.ZERO
var _air_timer: float = 0.0
var _air_duration: float = 1.0
var _height: float = 0.0
var _last_safe_pos: Vector2 = Vector2.ZERO
var _lie: String = "Tee"
var _on_green: bool = false
var _trail: Line2D
var _ghost_arc: Node2D
var _is_perfect_shot: bool = false

var _shot_origin: Vector2 = Vector2.ZERO
var _launch_dir: Vector2 = Vector2(0, -1)
var _pin_dir: Vector2 = Vector2(0, -1)
var _planned_distance_px: float = 0.0
var _landing_speed: float = 0.0
var _air_fraction: float = 0.78
var _is_putt: bool = false
var _spin_vis: float = 0.0

@onready var visual: Sprite2D = $Visual
@onready var shadow: Sprite2D = $Shadow
@onready var glow: Sprite2D = $Glow
@onready var spin_fx: Sprite2D = $SpinFX
@onready var area: Area2D = $Area


const BALL_R := 9.0
const BALL_R_GREEN := 15.0
const TRAIL_TEX := preload("res://assets/ball/ball_trail.png")

var _ball_scale: float = 1.0
var _shadow_scale: float = 1.0
var _glow_scale: float = 1.0

func _ready() -> void:
	_apply_lie_visual()
	_trail = Line2D.new()
	_trail.width = 5.0
	_trail.default_color = Color(0.85, 0.95, 1.0, 0.45)
	_trail.texture = TRAIL_TEX
	_trail.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	_trail.z_index = -1
	_trail.top_level = true
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_trail)
	_ghost_arc = Node2D.new()
	_ghost_arc.z_index = -2
	_ghost_arc.top_level = true
	add_child(_ghost_arc)
	area.area_entered.connect(_on_area_entered)
	_last_safe_pos = global_position
	set_physics_process(false)


func reset_at(pos: Vector2, lie: String = "Tee") -> void:
	global_position = pos
	_last_safe_pos = pos
	_lie = lie
	velocity = Vector2.ZERO
	spin = 0.0
	_height = 0.0
	_on_green = lie == "Green"
	_is_putt = false
	_is_perfect_shot = false
	state = State.IDLE
	_planned_distance_px = 0.0
	_trail.clear_points()
	_clear_ghosts()
	visual.rotation = 0.0
	visual.self_modulate = Color(1, 1, 1)
	shadow.position = Vector2.ZERO
	glow.visible = false
	spin_fx.visible = false
	_apply_lie_visual()
	set_physics_process(false)


func launch(result: ShotResult, target_pos: Vector2, club_max_yards: float, p_wind: Vector2, p_slope: Vector2) -> void:
	var to_pin := target_pos - global_position
	_pin_dir = to_pin.normalized()
	if _pin_dir == Vector2.ZERO:
		_pin_dir = Vector2(0, -1)

	var launch_data := BallPhysics.launch_velocity(result, to_pin, club_max_yards, _lie)
	velocity = launch_data["velocity"]
	spin = launch_data["spin"]
	_air_duration = launch_data["airborne_time"]
	_air_timer = 0.0
	_height = 0.0
	_is_putt = bool(launch_data.get("is_putt", _lie == "Green"))
	wind = Vector2.ZERO if _is_putt else p_wind
	green_slope = p_slope
	_shot_origin = global_position
	_launch_dir = launch_data["launch_dir"]
	# Soft guard only: don't launch nearly backward; allow offline aim for break reads
	if _is_putt and _launch_dir.dot(_pin_dir) < 0.15:
		_launch_dir = (_launch_dir + _pin_dir).normalized()
		velocity = _launch_dir * float(launch_data["landing_speed"])
	_planned_distance_px = launch_data["travel_px"]
	_landing_speed = launch_data["landing_speed"]
	_air_fraction = launch_data["air_fraction"]
	_trail.clear_points()
	_is_perfect_shot = result.is_perfect() and result.stance_stability >= 0.72
	if _is_perfect_shot:
		perfect_flash.emit()
		visual.self_modulate = Color(1.0, 0.92, 0.45)
		_trail.default_color = Color(1.0, 0.85, 0.25, 0.65)
	else:
		visual.self_modulate = Color(1, 1, 1)
		_trail.default_color = Color(0.85, 0.95, 1.0, 0.45)

	_ghost_arc.global_position = Vector2.ZERO
	_spawn_ghost_arc(launch_data)
	if _is_putt or _air_fraction <= 0.001:
		state = State.ROLL
		velocity = _launch_dir * _landing_speed
	else:
		state = State.FLIGHT
	set_physics_process(true)


func _spawn_ghost_arc(launch_data: Dictionary) -> void:
	_clear_ghosts()
	if _is_putt:
		return
	var travel: float = float(launch_data.get("travel_px", 200.0))
	var air_frac: float = float(launch_data.get("air_fraction", 0.78))
	var dir: Vector2 = launch_data.get("launch_dir", _launch_dir)
	var dots := 7
	for i in dots:
		var t := float(i + 1) / float(dots + 1)
		var along := travel * air_frac * t
		var h := sin(t * PI) * (28.0 + travel * 0.02)
		var p := Polygon2D.new()
		p.color = Color(1, 1, 1, 0.2 + 0.1 * (1.0 - t))
		var pts := PackedVector2Array()
		for k in 8:
			var a := TAU * float(k) / 8.0
			pts.append(Vector2(cos(a), sin(a)) * (3.0 + h * 0.02))
		p.polygon = pts
		p.global_position = _shot_origin + dir * along + Vector2(0, -h * 0.15)
		_ghost_arc.add_child(p)


func _clear_ghosts() -> void:
	if _ghost_arc == null:
		return
	for c in _ghost_arc.get_children():
		c.queue_free()


func get_last_safe() -> Vector2:
	return _last_safe_pos


func set_lie(lie: String) -> void:
	_lie = lie
	_on_green = lie == "Green"
	_apply_lie_visual()


func get_lie() -> String:
	return _lie


func _apply_lie_visual() -> void:
	## Larger ball on green so putt close-ups stay readable.
	var r := BALL_R_GREEN if _lie == "Green" else BALL_R
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
	_trail.add_point(global_position)
	if _trail.get_point_count() > 48:
		_trail.remove_point(0)
	_trail.width = clampf(3.0 + _height * 0.04 + velocity.length() * 0.004, 3.0, 10.0)
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
	_height = sin(clampf(t, 0.0, 1.0) * PI) * (28.0 + velocity.length() * 0.02)

	velocity += wind * delta * 6.0
	velocity += Vector2(spin * 28.0, 0.0) * delta

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


func _process_roll(delta: float) -> void:
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

	if _is_putt:
		# Break pulls offline; can fight aim (skill reads matter)
		var right := Vector2(-_pin_dir.y, _pin_dir.x)
		var break_amt := green_slope.dot(right) * 22.0
		var along_break := green_slope.dot(_pin_dir) * 14.0
		velocity += right * break_amt * delta
		velocity += _pin_dir * along_break * delta
	elif _lie == "Green":
		velocity += green_slope * 16.0 * delta

	velocity = velocity.move_toward(Vector2.ZERO, friction * 60.0 * delta)

	if not _is_putt:
		velocity += Vector2(spin * 8.0, 0.0) * delta
		spin = move_toward(spin, 0.0, delta * 1.8)
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

	if velocity.length() < 10.0:
		_finish_settle()


func _finish_settle() -> void:
	velocity = Vector2.ZERO
	state = State.SETTLED
	set_physics_process(false)
	_clear_ghosts()
	if _lie != "Water" and _lie != "OOB":
		_last_safe_pos = global_position
	settled.emit(global_position, _lie)


func _on_area_entered(other: Area2D) -> void:
	if state == State.SETTLED or state == State.IDLE:
		return
	if other.is_in_group("cup"):
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		_clear_ghosts()
		holed_out.emit()
		return
	if other.is_in_group("water"):
		_lie = "Water"
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		entered_hazard.emit("water")
		return
	if other.is_in_group("oob"):
		_lie = "OOB"
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		entered_hazard.emit("oob")
		return
	if other.is_in_group("sand"):
		_lie = "Sand"
	elif other.is_in_group("green"):
		_lie = "Green"
		_on_green = true
	elif other.is_in_group("fairway"):
		_lie = "Fairway"
	elif other.is_in_group("rough"):
		_lie = "Rough"


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

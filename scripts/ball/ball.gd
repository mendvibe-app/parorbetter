class_name GolfBall
extends CharacterBody2D

## Visual ball with height-based shadow + Trackman-style lofted flight tracer.
## Physics stay 2D top-down; _height fakes loft for arc readability.

signal settled(position: Vector2, lie_hint: String)
signal entered_hazard(kind: String)
signal holed_out
signal perfect_flash
## Fired when play_cup_drop curl+sink tween finishes (banner / reset timing).
signal cup_drop_finished

enum State { IDLE, FLIGHT, ROLL, SETTLED }

## Screen-up loft multiplier for tracer (matches old ghost-arc language).
## Lift is divided by camera zoom so close-up chips don't paint a huge screen arc.
const TRACER_LIFT := 0.35
## Target on-screen trail thickness (px). World width = screen / zoom.
const TRACER_SCREEN_W := 3.2
const TRACER_SCREEN_W_PURE := 4.0
## Hard cap only as safety; flight prefers space sampling and never trims mid-air.
const TRACER_CAP := 280
const TRACER_CAP_PURE := 320
## Target trail points across carry path (space-based sampling).
const TRACER_DESIRED_POINTS := 96.0
const TRACER_MIN_SPACING := 2.5  ## world px floor between samples
## Clear air between ball and tracer tip (screen px → world via zoom). Small gap reads
## more Trackman-like and makes tip/ball overlap easy to spot when wrong.
const TRACER_TIP_GAP_SCREEN := 7.0  ## PLAYTEST TARGET
## Wet-marker dry: 0 = fresh tip, 1 = fully faded. Advances on roll after flight.
## Slightly slower than pre-pacing so longer hang flights still dry into the land disc.
const TRACER_DRY_RATE := 0.72
## Landing target circle (screen px). Faint in air, lights up on first bounce.
const LAND_R_SCREEN := 15.0
const LAND_RING_W_SCREEN := 1.6
## Sidespin curvature ∝ along_spd (was flat 28 * spin_scale). 28/180 matches the
## old linear region at the former clamp knee → full-swing ~2.6× at driver speed.
## Confirmed on device (Phase 5): straight PERFECT + bent path +0.46 feel OK.
const SPIN_CURVE_COEFF := 28.0 / 180.0

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
## Highest _height observed this flight (F1 debug; ≈ peak if full flight).
var _height_max: float = 0.0
## Phase 0 instrumentation — hang/carry/launch for harness cross-check (no gameplay use).
var _hang_time_actual: float = 0.0  ## seconds in FLIGHT, set at _begin_roll
var _carry_px_actual: float = 0.0  ## along-launch distance at first bounce
var _launch_speed: float = 0.0  ## |velocity| after launch finalize
## Punch flight: can duck under canopy band (see tree collision).
var _punch_flight: bool = false
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
## Mean ground speed over hang (air_px/hang); envelope multiplies by flight_speed_scale(t).
var _mean_air_speed: float = 0.0
var _is_putt: bool = false
var _shot_type: String = "full"  ## aim/launch type (visual radius no longer depends on this)
var _spin_vis: float = 0.0
## Sample surface under the ball while rolling (fairway/rough/sand/green).
var ground_lie_at: Callable = Callable()

@onready var visual: Sprite2D = $Visual
@onready var shadow: Sprite2D = $Shadow
@onready var glow: Sprite2D = $Glow
@onready var spin_fx: Sprite2D = $SpinFX
@onready var area: Area2D = $Area


## Deprecated — was flight exaggerate (3.5). Visual ball is always true-scale now.
const BALL_R := 0.102
## True real-world scale (0.75 world-px/ft, from BallPhysics.PX_PER_YARD).
## Real ball radius 0.84" → 0.102 world units through 33/64 sprite fill.
## Ratio to CUP_RADIUS held at real 2.53 (see putt-ball-visible-size.md). Visual only.
## Used for the whole round (tee → putt) — no short-game / flight size belt.
const BALL_R_PUTT := 0.102
## Green break: BallPhysics.green_slope_accel (g·sinθ × GREEN_GRAVITY_SCALE).
## Max roll speed (px/s) to drop in the cup. Faster → lip out / roll over (no teleport make).
## Scaled with BallPhysics.PUTT_PACE_SCALE (was 32). Settle sits below this.
const CUP_CAPTURE_MAX_SPEED := 11.2
## True real-world scale. Real cup radius 2.125" → 0.133 world units through
## 43/64 dark-disc fill. PLAYTEST TARGET — pure geometric radius, zero lip-catch
## cushion. Widen toward 0.185 if dying putts feel unfairly harsh; range derives
## from hole_radius ± ball_radius, see plans/putt-true-scale-phase1.md.
## Must match HoleController.CUP_CAPTURE_RADIUS.
const CUP_CAPTURE_RADIUS := 0.133
## Lip-in presentation — PLAYTEST. Orbit on true-scale grey rim (not pre-scale 1.55).
## (57/64)*CUP_RADIUS(0.198) ≈ 0.177. Arc angle still carries offset signal.
const LIP_ORBIT_MAX := 0.175
## Pour band — PLAYTEST. Compared to offset_ratio (0–1 of CUP_CAPTURE_RADIUS).
## True-scale bug: 0.048 was absolute world-px but compared as a ratio → only ~5%
## of the cup poured; everything else toilet-bowled. Plan target = half the disc.
const LIP_CENTER_OFFSET_MAX := 0.50
const LIP_CENTER_SPEED_MAX := 1.05  ## unused as a hard gate; kept for arc scaling
const LIP_DROP_DUR := 0.18
## Near-edge pours occasionally catch a hair (short curl). True center always pours.
const LIP_POUR_PROMOTE_OFFSET := 0.35
const LIP_POUR_PROMOTE_CHANCE := 0.10
## Lip-out presentation — PLAYTEST. Hot rejects; orbit = rim; make rate frozen.
## Arc length is the legibility metric (not orbit). Half→¾+ turn so horseshoe reads.
const LIP_OUT_ARC_MIN := TAU * 0.55  ## ~198° — above lip-in band
const LIP_OUT_ARC_MAX := TAU * 0.85  ## ~306° horseshoe
const LIP_OUT_DUR_MIN := 0.32
const LIP_OUT_DUR_MAX := 0.62
const LIP_OUT_ORBIT := LIP_ORBIT_MAX
const LIP_OUT_REARM_PAD := 0.04  ## world px past capture disc before re-arm
## Lip-out leave exit speed (px/s) — scaled with PUTT_PACE_SCALE (was 3 / 14).
const LIP_OUT_EXIT_SIT := 1.05
const LIP_OUT_EXIT_MAX := 4.9
## Chip/pitch rim-out: short hop only (playtest: unpaced leave → ~150 yd rocket).
const LIP_OUT_EXIT_CHIP_MAX := 1.15  ## PLAYTEST TARGET
const LIP_OUT_CHIP_LEAVE_MAX_YD := 4.0  ## hard stop from cup for non-putt leave
## Firm putts inside the make gate can still lip out (Pelz — speed kills).
## Below SPEED_MIN ratio always drops if in disc. Chance rises toward the hard max.
const LIP_OUT_CHANCE_SPEED_MIN := 0.55  ## fraction of CUP_CAPTURE_MAX_SPEED
const LIP_OUT_CHANCE_AT_MIN := 0.10  ## just entering firm band
const LIP_OUT_CHANCE_AT_MAX := 0.42  ## at the capture-max gate — often rattles out
## _begin_roll fallback floor — was 20 (post true-scale footgun with putt_decel).
const ROLL_SPEED_FLOOR := 2.0
## Lip-in rim-roll arc — PLAYTEST. Short curl for mild lips; half–¾ only when earned.
## (Was floor 0.50τ → every non-pour looked like a toilet bowl.)
const LIP_IN_ARC_MIN := TAU * 0.12
const LIP_IN_ARC_MAX := TAU * 0.75
const LIP_IN_CURL_DUR_MIN := 0.16
const LIP_IN_CURL_DUR_MAX := 0.55
## Wind exposure (Phase 1 short-game offline) — PLAYTEST TARGETS.
## Scale absolute wind by hang×apex vs full-swing refs so chips are nearly immune
## and drivers keep meaningful drift. Product (not sum): punch low apex earns less.
const WIND_REF_HANG_S := 2.0
const WIND_REF_APEX_PX := 80.0
const WIND_EXPOSURE_MIN := 0.02
const WIND_EXPOSURE_MAX := 1.0
## Path drift scale — wind moves position, not velocity heading. PLAYTEST so driver
## crosswind stays meaningful (~10–20 yd at peak) without chip steer-off (~60° bug).
const WIND_DRIFT_SCALE := 0.12

var _ball_scale: float = 1.0
var _shadow_scale: float = 1.0
var _glow_scale: float = 1.0
## Cup entry stash for lip-in — set in _try_cup_capture; cleared after drop / launch.
## Never cleared in reset_at (handlers call reset_at then play_cup_drop).
var _cup_entry_offset: Vector2 = Vector2.ZERO
var _cup_entry_speed: float = 0.0
var _cup_entry_valid: bool = false
## Lip-out stash — separate from make stash so a horseshoe cannot poison play_cup_drop.
var _lip_out_offset: Vector2 = Vector2.ZERO
var _lip_out_speed: float = 0.0
var _lip_out_dir: Vector2 = Vector2(0, -1)
var _lip_out_cup_pos: Vector2 = Vector2.ZERO
var _lip_out_armed: bool = true
var _lip_out_playing: bool = false
var _lip_out_tween: Tween = null
## After horseshoe: trickle settle like a putt so ft-scale leaves aren't killed by ROLL_SETTLE=10.
var _lip_out_leave: bool = false
var _lip_out_leave_from: Vector2 = Vector2.ZERO  ## cup pos for chip leave governor

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
	_height_max = 0.0
	_hang_time_actual = 0.0
	_carry_px_actual = 0.0
	_launch_speed = 0.0
	_mean_air_speed = 0.0
	_punch_flight = false
	_is_putt = false
	_shot_type = "full"
	_is_perfect_shot = false
	state = State.IDLE
	_planned_distance_px = 0.0
	_trail.clear_points()
	_trail_dry = 0.0
	_trail.modulate.a = 1.0
	_sync_trail_gradient()
	_hide_land_mark()
	visual.rotation = 0.0
	visual.position = Vector2.ZERO  ## clear lip-in offset; stash cleared separately
	visual.self_modulate = Color(1, 1, 1)
	shadow.position = Vector2.ZERO
	glow.visible = false
	spin_fx.visible = false
	_cancel_lip_out()
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
	_clear_cup_entry_stash()
	_cancel_lip_out()
	visual.position = Vector2.ZERO
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
	# Phase 1: apex from launch (apex_for × shot-type × contact); not loft×(28+speed).
	_height_peak = float(launch_data.get("apex", 0.0))
	_height_max = 0.0
	_punch_flight = shot_type == "punch"
	_shot_type = shot_type
	_is_putt = bool(launch_data.get("is_putt", _lie == "Green"))
	_apply_lie_visual()
	if _is_putt:
		_height_peak = 0.0
		_punch_flight = false
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
	var air_px_plan := _planned_distance_px * _air_fraction
	_mean_air_speed = float(
		launch_data.get(
			"mean_air_speed",
			air_px_plan / maxf(_air_duration, 0.05)
		)
	)
	# Ensure impact is peak (pin-align may have rewritten velocity for non-putts).
	if not _is_putt and _mean_air_speed > 0.01:
		var peak := BallPhysics.flight_peak_speed(_mean_air_speed)
		velocity = _launch_dir * peak
	# After pin-align may rewrite velocity; capture magnitude for harness comparison.
	_launch_speed = velocity.length()
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


func flight_height_peak() -> float:
	## Planned apex (formula at launch).
	return _height_peak


func flight_height_max() -> float:
	## Highest loft seen this flight (for F1 / tree-carry tuning).
	return _height_max


func flight_metrics() -> Dictionary:
	## Post-shot instrumentation for the debug panel and harness cross-check.
	return {
		"apex_planned": _height_peak,
		"apex_actual": _height_max,
		"hang_time": _hang_time_actual,
		"carry_px": _carry_px_actual,
		"planned_px": _planned_distance_px,
		"air_fraction": _air_fraction,
		"launch_speed": _launch_speed,
	}


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


func set_visual_shot_type(shot_type: String, _pin_yards: float = -1.0) -> void:
	## Aim picker still reports type; ball draw is always true-scale.
	_shot_type = shot_type
	_apply_lie_visual()


func _visual_ball_radius() -> float:
	## Whole round — same world size as the cup ratio (tee speck is honest; escape hatch = screen floor later).
	return BALL_R_PUTT


func _apply_lie_visual() -> void:
	var r := _visual_ball_radius()
	var tex_w := float(visual.texture.get_width()) if visual.texture else 961.0
	_ball_scale = (r * 2.0) / tex_w
	visual.scale = Vector2.ONE * _ball_scale
	# Shadow texture holds a wide soft ellipse; size it to a bit over ball width.
	var sh_w := float(shadow.texture.get_width()) if shadow.texture else 512.0
	_shadow_scale = ((r + 0.15) * 2.6) / sh_w
	shadow.scale = Vector2(_shadow_scale, _shadow_scale)
	shadow.modulate.a = 0.85
	# Glow / spin hug the ball (world). Trail/land rings stay screen-constant elsewhere.
	if glow.texture:
		_glow_scale = (r * 5.2) / float(glow.texture.get_width())
		glow.scale = Vector2.ONE * _glow_scale
	if spin_fx.texture:
		spin_fx.scale = Vector2.ONE * (r * 3.4) / float(spin_fx.texture.get_width())


func distance_traveled_yards() -> float:
	return BallPhysics.pixels_to_yards((global_position - _shot_origin).length())


func shot_origin() -> Vector2:
	return _shot_origin


func cup_entry_offset() -> Vector2:
	return _cup_entry_offset


func cup_entry_speed() -> float:
	return _cup_entry_speed


func _physics_process(delta: float) -> void:
	match state:
		State.FLIGHT:
			_process_flight(delta)
		State.ROLL:
			_process_roll(delta)
		_:
			pass
	# Flight: lofted Trackman tracer (space-sampled for variable air speed).
	# Tip glued to the ball every frame. Body keeps screen-up loft, then every point
	# is clamped so nothing sits past the tip along launch (apex loft was leading
	# the ribbon past the ball on driver — playtest screenshot 2026-08-17).
	# Roll: freeze points and dry the ribbon (wet marker) into the land circle.
	if not _is_putt:
		if state == State.FLIGHT:
			_sync_trail_visual()
			var lift := TRACER_LIFT / maxf(_camera_zoom(), 0.35)
			var body_pt := global_position + Vector2(0.0, -_height * lift)
			# Tip sits behind the ball: half line-width (cap) + deliberate gap.
			var z := maxf(_camera_zoom(), 0.35)
			var half_w := _trail.width * 0.5
			var tip_gap := TRACER_TIP_GAP_SCREEN / z
			var tip_pt := global_position - _launch_dir * (half_w + tip_gap)
			var n := _trail.get_point_count()
			var air_px := maxf(_planned_distance_px * _air_fraction, 8.0)
			var min_sp := maxf(air_px / TRACER_DESIRED_POINTS, TRACER_MIN_SPACING)
			var t_air := clampf(_air_timer / maxf(_air_duration, 0.01), 0.0, 1.0)
			var dens := clampf(BallPhysics.flight_speed_scale(t_air) / 1.2, 0.55, 1.25)
			min_sp = maxf(min_sp / dens, TRACER_MIN_SPACING * 0.7)
			if n == 0:
				_trail.add_point(tip_pt)
			else:
				_trail.set_point_position(n - 1, tip_pt)
				var commit := false
				if n == 1:
					commit = tip_pt.distance_to(_shot_origin) >= min_sp
				else:
					commit = tip_pt.distance_to(_trail.get_point_position(n - 2)) >= min_sp
				if not commit and n < 10 and _air_timer > float(n) * 0.04:
					commit = true
				if commit:
					# Freeze lofted body sample, then new tip on the ball.
					_trail.set_point_position(n - 1, body_pt)
					_trail.add_point(tip_pt)
					var cap := TRACER_CAP_PURE if _is_perfect_shot else TRACER_CAP
					if _trail.get_point_count() > cap:
						_trail.remove_point(0)
			# Pull any lofted body point that sits past the tip back behind the ball.
			_clamp_trail_behind_tip(tip_pt)
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
	# Putt speeds are low (~5–20 px/s); 0.002 was nearly invisible. Visual only.
	var roll_spin := 0.018 if _is_putt else 0.002  ## PLAYTEST TARGET — putt roll read
	_spin_vis += spin * delta * 4.0 + velocity.length() * roll_spin
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


func _wind_exposure() -> float:
	## Hang × apex vs full-swing refs. Chips near floor; driver ≈ 1. PLAYTEST.
	## Product (not geometric mean): chip 0.93s/17px → ~0.10; driver 2s/80px → 1.0.
	var hang_t := clampf(_air_duration / WIND_REF_HANG_S, 0.0, 1.0)
	var apex_t := clampf(_height_peak / WIND_REF_APEX_PX, 0.0, 1.0)
	return clampf(hang_t * apex_t, WIND_EXPOSURE_MIN, WIND_EXPOSURE_MAX)


func _process_flight(delta: float) -> void:
	_air_timer += delta
	var t := clampf(_air_timer / maxf(_air_duration, 0.01), 0.0, 1.0)
	_height = sin(t * PI) * _height_peak
	if _height > _height_max:
		_height_max = _height

	# Mean speed preserves carry; envelope makes impact hottest then slows (research).
	var mean_spd := _mean_air_speed
	if mean_spd <= 0.01:
		mean_spd = (_planned_distance_px * _air_fraction) / maxf(_air_duration, 0.05)
	var target_spd := BallPhysics.flight_speed_at(mean_spd, t)
	var peak_spd := BallPhysics.flight_peak_speed(mean_spd)

	var flight_right := Vector2(-_launch_dir.y, _launch_dir.x)
	# Along-envelope + keep spin lateral. Wind must NOT enter velocity then renormalize —
	# that turned absolute push into pure heading rotation on slow chips (~60° offline).
	var along_spd := minf(target_spd, peak_spd * 1.02)
	var lat_spd := velocity.dot(flight_right)
	velocity = _launch_dir * along_spd + flight_right * lat_spd
	if absf(spin) > 0.0001:
		velocity += flight_right * spin * SPIN_CURVE_COEFF * along_spd * delta
	# Re-assert along envelope; KEEP spin lateral (no full-vector normalize).
	var lat_after := velocity.dot(flight_right)
	velocity = _launch_dir * along_spd + flight_right * lat_after
	# Wind as path drift — lateral displacement without steering the velocity vector.
	# Base force keeps integrated drift ≈ constant vs FRAC; exposure kills chip wind.
	# hang ∝ 1/sqrt(g); force ∝ sqrt(g) keeps force×hang ≈ legacy at g=535.
	var wind_force := (
		6.0 * sqrt(BallPhysics.GRAVITY_PX / 535.0) * _wind_exposure() * WIND_DRIFT_SCALE
	)
	global_position += wind * delta * wind_force

	var collision := move_and_collide(velocity * delta)
	var along := _traveled_along()
	var path_len := (global_position - _shot_origin).length()
	var air_limit := _planned_distance_px * _air_fraction

	# All four exits are deliberate (Phase 5 CP5 — not unfinished band-aid removal):
	# collision — tree/obstacle; t>=1 — hang clock, required under headwind stall
	#   (path_len-only hangs); along — straight carry; path_len — curved carry
	#   (path >= along, so curves land on path before along).
	if collision or t >= 1.0 or along >= air_limit or path_len >= air_limit:
		_begin_roll()


func _capture_flight_metrics() -> void:
	## Hang/carry for F1 harness cross-check. Call on every FLIGHT exit (roll or settle).
	_hang_time_actual = _air_timer
	_carry_px_actual = _traveled_along()


func _begin_roll() -> void:
	_capture_flight_metrics()
	_height = 0.0
	state = State.ROLL
	var speed := _landing_speed
	if speed <= 1.0:
		speed = maxf(velocity.length() * 0.35, ROLL_SPEED_FLOOR)
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
	# Horseshoe owns position while playing; skip friction/settle/capture.
	if _lip_out_playing:
		return
	_update_lip_out_arming()
	_sync_ground_lie()
	_height = move_toward(_height, 0.0, delta * 80.0)
	var slope := _slope_at_ball()
	if _is_putt or _lie == "Green":
		velocity += BallPhysics.green_slope_accel(slope) * delta

	# Green → putt pace; chip/pitch/flop off-green → chip pace (playtest: rocket rollout).
	var decel: float
	if _is_putt or _lip_out_leave or _lie == "Green":
		decel = BallPhysics.putt_decel_px()
	elif BallPhysics.is_short_game_shot(_shot_type):
		decel = BallPhysics.landing_roll_decel_px(_lie, _shot_type)
	else:
		decel = BallPhysics.roll_decel_px(_lie)
	velocity = velocity.move_toward(Vector2.ZERO, decel * delta)

	if not _is_putt:
		var roll_right := Vector2(-_launch_dir.y, _launch_dir.x)
		var roll_along := maxf(velocity.dot(_launch_dir), 0.0)
		var roll_spin_scale := clampf(roll_along / 120.0, 0.08, 1.0)
		velocity += roll_right * spin * 8.0 * delta * roll_spin_scale
		spin = move_toward(spin, 0.0, delta * 1.8)
		# Keep roll from walking backwards off a short miss (off-green only — slope owns trickle).
		if (
			_lie != "Green"
			and velocity.dot(_pin_dir) < -20.0
			and _planned_distance_px < BallPhysics.yards_to_pixels(50.0)
		):
			velocity += _pin_dir * 40.0 * delta
	else:
		# Mild anti-teleport only — break can still pull offline / slightly against aim
		var toward := velocity.dot(_pin_dir)
		if toward < -80.0:
			velocity += _pin_dir * (-toward - 80.0) * 0.2

	var along := _traveled_along()
	# Phase 5 CP6: remain<40 speed clamp removed. Hard settle at plan kept.
	# Lip-out leave skips plan clamp — sideways trickle must coast on speed, not freeze at pin.
	if along >= _planned_distance_px and not _is_putt and not _lip_out_leave and _lie != "Green":
		_finish_settle()
		return
	# Chip rim-out: never coast drive-length (leave skips plan clamp).
	if (
		_lip_out_leave
		and not _is_putt
		and global_position.distance_to(_lip_out_leave_from)
		> BallPhysics.yards_to_pixels(LIP_OUT_CHIP_LEAVE_MAX_YD)
	):
		_finish_settle()
		return
	# Putts: stop by speed, allow break past planned if overhit
	if _is_putt and along >= _planned_distance_px * 1.15:
		velocity *= 0.92

	var collision := move_and_collide(velocity * delta)
	if collision and not _is_putt:
		velocity = velocity.bounce(collision.get_normal()) * 0.3

	# Cup: re-check every frame so a ball that was too hot on enter can still drop when it dies.
	# Lip-out zeros velocity for the rim ride — must not fall through to settle same frame.
	if _try_cup_capture() or _lip_out_playing:
		return

	if _lie == "Green":
		AudioBus.set_roll_intensity(velocity.length() / 400.0)
	else:
		AudioBus.set_roll_intensity(0.0)

	# Putts / green rolls / lip leave: putt settle so sit band isn't truncated by ROLL_SETTLE=10.
	var settle_spd := (
		BallPhysics.PUTT_SETTLE_SPEED
		if _is_putt or _lip_out_leave or _lie == "Green"
		else BallPhysics.ROLL_SETTLE_SPEED
	)
	if velocity.length() < settle_spd:
		_finish_settle()


func _finish_settle() -> void:
	if _lip_out_playing:
		return
	# Dying on the lip: one last capture attempt (speed is ~0).
	if _try_cup_capture() or _lip_out_playing:
		return
	velocity = Vector2.ZERO
	_lip_out_leave = false
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


## True when the ball drops in (emits settled so hole_controller records the make).
## False = miss / too hot / not over cup.
func _water_area_is_wet(water_area: Area2D, pos: Vector2) -> bool:
	## True if this water volume should wet the ball at pos. No paint meta = full rect
	## (island water_tile). With meta, only opaque creek/pond pixels count.
	if water_area == null:
		return true
	if not water_area.has_meta("water_img") or not water_area.has_meta("water_sprite"):
		return true
	var spr: Sprite2D = water_area.get_meta("water_sprite") as Sprite2D
	var img: Image = water_area.get_meta("water_img") as Image
	if spr == null or img == null:
		return true
	var sz := Vector2(float(img.get_width()), float(img.get_height()))
	var sc := spr.scale
	if absf(sc.x) < 0.001 or absf(sc.y) < 0.001:
		return false
	var local := spr.to_local(pos)
	var ix := int(local.x / sc.x + sz.x * 0.5)
	var iy := int(local.y / sc.y + sz.y * 0.5)
	if ix < 0 or iy < 0 or ix >= int(sz.x) or iy >= int(sz.y):
		return false
	return img.get_pixel(ix, iy).a > 0.5


func _clear_cup_entry_stash() -> void:
	_cup_entry_offset = Vector2.ZERO
	_cup_entry_speed = 0.0
	_cup_entry_valid = false


func _clear_lip_out_stash() -> void:
	_lip_out_offset = Vector2.ZERO
	_lip_out_speed = 0.0
	_lip_out_dir = Vector2(0, -1)
	_lip_out_cup_pos = Vector2.ZERO


func _cancel_lip_out() -> void:
	if _lip_out_tween and is_instance_valid(_lip_out_tween):
		_lip_out_tween.kill()
	_lip_out_tween = null
	_lip_out_playing = false
	_lip_out_leave = false
	_lip_out_armed = true
	_clear_lip_out_stash()


func _cup_disc_at(other: Area2D) -> Dictionary:
	## Sensor radius + world center for a cup area.
	var cs := other.get_child(0) as CollisionShape2D
	var cup_r: float = (
		cs.shape.radius if cs and cs.shape is CircleShape2D else CUP_CAPTURE_RADIUS
	)
	return {"pos": other.global_position, "r": cup_r}


func _over_cup_disc(pad: float = 0.0) -> bool:
	for other in area.get_overlapping_areas():
		if not other.is_in_group("cup"):
			continue
		var d: Dictionary = _cup_disc_at(other)
		if global_position.distance_to(d["pos"]) <= float(d["r"]) + pad:
			return true
	return false


func _update_lip_out_arming() -> void:
	## Re-arm only after leaving the dark disc so one pass cannot double-fire.
	if _lip_out_playing or _lip_out_armed:
		return
	if not _over_cup_disc(LIP_OUT_REARM_PAD):
		_lip_out_armed = true


func _begin_lip_out(cup_pos: Vector2) -> void:
	## Hot reject horseshoe — presentation only. Never emits settled / never sinks.
	if _lip_out_playing or not _lip_out_armed:
		return
	_lip_out_armed = false
	_lip_out_playing = true
	_lip_out_cup_pos = cup_pos
	_lip_out_offset = global_position - cup_pos
	_lip_out_speed = velocity.length()
	if velocity.length_squared() > 0.01:
		_lip_out_dir = velocity.normalized()
	elif _launch_dir.length_squared() > 0.01:
		_lip_out_dir = _launch_dir.normalized()
	else:
		_lip_out_dir = Vector2(0, -1)
	velocity = Vector2.ZERO
	AudioBus.set_roll_intensity(0.0)

	var offset_len := _lip_out_offset.length()
	var offset_ratio := clampf(offset_len / CUP_CAPTURE_RADIUS, 0.0, 1.0)
	var speed_ratio := clampf(
		(_lip_out_speed - CUP_CAPTURE_MAX_SPEED) / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0
	)
	var start_ang: float
	if offset_len < 0.05:
		# Dead-center hot: pick a side perpendicular to approach.
		start_ang = _lip_out_dir.angle() + PI * 0.5
	else:
		start_ang = _lip_out_offset.angle()

	var arc_rad := lerpf(LIP_OUT_ARC_MIN, LIP_OUT_ARC_MAX, offset_ratio)
	arc_rad *= lerpf(0.9, 1.15, speed_ratio)
	var approach := _lip_out_dir
	var cross_z := _lip_out_offset.x * approach.y - _lip_out_offset.y * approach.x
	if offset_len < 0.05:
		cross_z = 1.0
	if cross_z < 0.0:
		arc_rad = -arc_rad
	var curl_dur := lerpf(LIP_OUT_DUR_MIN, LIP_OUT_DUR_MAX, offset_ratio)
	var orbit_r := LIP_OUT_ORBIT
	var arc_sign := signf(arc_rad)
	if arc_sign == 0.0:
		arc_sign = 1.0

	# Ride the rim — node moves so collider matches art (not visual-only ghost).
	visual.position = Vector2.ZERO
	global_position = cup_pos + Vector2.from_angle(start_ang) * orbit_r

	if _lip_out_tween and is_instance_valid(_lip_out_tween):
		_lip_out_tween.kill()
	_lip_out_tween = create_tween()
	var end_ang := start_ang + arc_rad
	_lip_out_tween.tween_method(
		func(a: float) -> void:
			global_position = cup_pos + Vector2.from_angle(a) * orbit_r,
		start_ang,
		end_ang,
		curl_dur
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lip_out_tween.finished.connect(
		func() -> void:
			_finish_lip_out(end_ang, orbit_r, arc_sign),
		CONNECT_ONE_SHOT
	)


func _lip_out_exit_speed() -> float:
	## Rim bleeds most energy; exit band is ft-grounded. Heat + offset set kick tendency;
	## randf stands in for micro-line at the liner (geometry-weighted, not a coin flip).
	## Never use raw _lip_out_speed (chip entry) — that rocketed leaves ~150 yd.
	var heat := clampf(_lip_out_speed / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0)
	var offset_ratio := clampf(_lip_out_offset.length() / CUP_CAPTURE_RADIUS, 0.0, 1.0)
	# Center-hot rattles harder; high-offset horseshoe usually softer exit. PLAYTEST.
	var kick_tend := clampf(
		lerpf(0.25, 1.0, heat) * lerpf(1.0, 0.55, offset_ratio), 0.0, 1.0
	)
	var u := randf()
	var sit_bias := lerpf(2.4, 0.75, kick_tend)  # low tend → more sits
	var leave_t := pow(u, sit_bias)
	var exit_spd := lerpf(LIP_OUT_EXIT_SIT, LIP_OUT_EXIT_MAX, leave_t)
	exit_spd *= lerpf(0.45, 1.0, kick_tend)  # cold lips cannot reach hot max
	exit_spd = clampf(exit_spd, LIP_OUT_EXIT_SIT, LIP_OUT_EXIT_MAX)
	if not _is_putt:
		exit_spd = minf(exit_spd, LIP_OUT_EXIT_CHIP_MAX)
	return exit_spd


func _finish_lip_out(exit_ang: float, orbit_r: float, arc_sign: float) -> void:
	if not _lip_out_playing:
		return
	_lip_out_tween = null
	# End on the rim outside the make disc — no false settle-make.
	global_position = _lip_out_cup_pos + Vector2.from_angle(exit_ang) * orbit_r
	visual.position = Vector2.ZERO
	var exit_tangent := Vector2.from_angle(exit_ang + arc_sign * PI * 0.5)
	velocity = exit_tangent * _lip_out_exit_speed()
	_lip_out_leave_from = _lip_out_cup_pos
	_clear_lip_out_stash()
	_lip_out_playing = false
	_lip_out_leave = true
	# Stay disarmed until _update_lip_out_arming sees leave.
	state = State.ROLL
	set_physics_process(true)


func _try_cup_capture() -> bool:
	if state != State.ROLL or _lip_out_playing:
		return false
	for other in area.get_overlapping_areas():
		if not other.is_in_group("cup"):
			continue
		# Center must reach the dark opening — not the light grass collar on cup.png
		# (full CUP_RADIUS capture felt like short putts got sucked in).
		var d: Dictionary = _cup_disc_at(other)
		var cup_pos: Vector2 = d["pos"]
		var cup_r: float = d["r"]
		if global_position.distance_to(cup_pos) > cup_r:
			continue
		var spd := velocity.length()
		var entry_offset := global_position - cup_pos
		# Always-hot: over the hard max → horseshoe (never makes).
		if spd > CUP_CAPTURE_MAX_SPEED:
			_begin_lip_out(cup_pos)
			return false
		# Firm band inside the gate: chance to lip out even on a good line (speed kills).
		# Soft putts below SPEED_MIN still always drop if center is in the disc.
		var speed_ratio := clampf(spd / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0)
		if speed_ratio >= LIP_OUT_CHANCE_SPEED_MIN:
			var offset_ratio := clampf(entry_offset.length() / CUP_CAPTURE_RADIUS, 0.0, 1.0)
			var t_hot := inverse_lerp(LIP_OUT_CHANCE_SPEED_MIN, 1.0, speed_ratio)
			var lip_chance := lerpf(LIP_OUT_CHANCE_AT_MIN, LIP_OUT_CHANCE_AT_MAX, t_hot)
			# Center-hot rattles more; glancing firm slightly less. PLAYTEST.
			lip_chance *= lerpf(1.12, 0.88, offset_ratio)
			if randf() < lip_chance:
				_begin_lip_out(cup_pos)
				return false
		# Stash entry BEFORE zeroing velocity — play_cup_drop reads after reset_at.
		_cup_entry_offset = entry_offset
		_cup_entry_speed = spd
		_cup_entry_valid = true
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		# Emit settled (not holed_out) so _on_ball_settled records Actual yd + coach
		# and routes practice/short-game/normal hole-out. Capture radius ⊂ CUP_RADIUS.
		settled.emit(global_position, _lie)
		return true
	return false


func _set_trail_dry(v: float) -> void:
	_trail_dry = clampf(v, 0.0, 1.0)
	_sync_trail_gradient()
	# Trim the dried launch end while settling
	if _trail and _trail_dry > 0.4 and _trail.get_point_count() > 4:
		_trail.remove_point(0)


func _clamp_trail_behind_tip(tip_pt: Vector2) -> void:
	## Screen-up loft moves points toward -Y (down-range on portrait). Apex samples
	## can sit past the ball even when their ground sample is behind. Push any point
	## that is ahead of the tip along launch back so the ribbon never outruns the ball.
	if _trail == null:
		return
	var n := _trail.get_point_count()
	if n < 2:
		return
	var along := _launch_dir
	if along.length_squared() < 0.0001:
		along = Vector2(0, -1)
	else:
		along = along.normalized()
	# Keep body at least a hair behind tip (world px).
	var pad := maxf(_trail.width * 0.35, 0.75)
	for i in range(n - 1):
		var p := _trail.get_point_position(i)
		var ahead := (p - tip_pt).dot(along)
		if ahead > -pad:
			_trail.set_point_position(i, p - along * (ahead + pad))


func _on_area_entered(other: Area2D) -> void:
	# Trees: roll always blocks. Flight: over canopy, or punch under the foliage band.
	if other.is_in_group("tree"):
		if state == State.SETTLED or state == State.IDLE:
			return
		if state == State.FLIGHT:
			var canopy := float(other.get_meta("canopy_h", 30.0))
			if _height >= canopy:
				return  # over the top
			# Punch: stay in the under-foliage band (top-down disk = canopy footprint).
			if _punch_flight and _height <= canopy * BallPhysics.PUNCH_UNDER_CANOPY_FRAC:
				return  # under
			# Tree strike ends FLIGHT without _begin_roll — capture hang/carry here.
			_capture_flight_metrics()
		_apply_lie_string("Trees", false)
		velocity = Vector2.ZERO
		state = State.SETTLED
		set_physics_process(false)
		AudioBus.set_roll_intensity(0.0)
		settled.emit(global_position, _lie)
		return
	# Ground groups (water/sand/fairway/…) only count on ROLL.
	# Water/OOB never end FLIGHT directly — after roll, hang/carry already set in _begin_roll.
	if state != State.ROLL:
		return
	if other.is_in_group("cup"):
		_try_cup_capture()
		# Hot horseshoe may have started; do not keep applying ground groups this frame.
		return
	if other.is_in_group("water"):
		# Putting surface wins — island water volumes can graze the green edge.
		for a in area.get_overlapping_areas():
			if a.is_in_group("green"):
				_apply_lie_string("Green", false)
				return
		# Creek/pond sprites are not full rects; AABB over-fires on transparent fringe
		# (playtest: land mark looked dry, game said WATER). Paint-gate like sand.
		if not _water_area_is_wet(other, global_position):
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
	# Order matters when fairway collars under the green: sand/green beat fairway.
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


func _cup_drop_params() -> Dictionary:
	## Shared pour vs rim-roll decision for duration + play_cup_drop.
	## Offset-led: good line → pour. Rim curl only on clear edge catch.
	if not _cup_entry_valid:
		return {"pour": true, "offset_ratio": 0.0, "speed_ratio": 0.0}
	var offset_ratio := clampf(_cup_entry_offset.length() / CUP_CAPTURE_RADIUS, 0.0, 1.0)
	var speed_ratio := clampf(_cup_entry_speed / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0)
	var pour := offset_ratio < LIP_CENTER_OFFSET_MAX
	# True center always pours; near-edge may catch a hair (short curl).
	if pour and offset_ratio >= LIP_POUR_PROMOTE_OFFSET and randf() < LIP_POUR_PROMOTE_CHANCE:
		pour = false
	return {"pour": pour, "offset_ratio": offset_ratio, "speed_ratio": speed_ratio}


func cup_drop_total_duration() -> float:
	## Curl + sink — for hole-out awaits (banner / practice reset).
	## Note: promote luck is re-rolled in play_cup_drop; duration uses a no-luck pour
	## band estimate plus max curl budget so awaits never cut a promoted short curl.
	if not _cup_entry_valid:
		return LIP_DROP_DUR
	var offset_ratio := clampf(_cup_entry_offset.length() / CUP_CAPTURE_RADIUS, 0.0, 1.0)
	var speed_ratio := clampf(_cup_entry_speed / CUP_CAPTURE_MAX_SPEED, 0.0, 1.0)
	var pour := offset_ratio < LIP_CENTER_OFFSET_MAX
	# Budget for rare near-edge promote (worst-case short curl).
	if pour and offset_ratio < LIP_POUR_PROMOTE_OFFSET:
		return LIP_DROP_DUR
	var curl_dur := (
		lerpf(LIP_IN_CURL_DUR_MIN, LIP_IN_CURL_DUR_MAX, offset_ratio)
		+ lerpf(0.0, 0.08, speed_ratio)
	)
	# Short arcs finish faster (matches play_cup_drop scale).
	var arc_span := lerpf(LIP_IN_ARC_MIN, LIP_IN_ARC_MAX, offset_ratio) / LIP_IN_ARC_MAX
	curl_dur *= clampf(arc_span, 0.35, 1.0)
	return curl_dur + LIP_DROP_DUR


func play_cup_drop() -> void:
	## Visual only — pour or rim curl then sink. Call after reset_at(cup).
	## Stash must survive reset_at; cleared here when the tween finishes.
	if visual == null:
		_clear_cup_entry_stash()
		cup_drop_finished.emit()
		return
	var start_s := _ball_scale
	visual.scale = Vector2.ONE * start_s
	visual.self_modulate = Color(1, 1, 1, 1)
	visual.position = Vector2.ZERO
	if shadow:
		shadow.modulate.a = 1.0
	if glow:
		glow.visible = false
	if spin_fx:
		spin_fx.visible = false

	var params: Dictionary = _cup_drop_params()
	var offset_ratio: float = params["offset_ratio"]
	var speed_ratio: float = params["speed_ratio"]
	var rim_roll := _cup_entry_valid and not bool(params["pour"])

	var tw := create_tween()
	if rim_roll:
		# Orbit at rim shelf (grey overhang OK). Arc length from offset; luck inside band.
		var orbit_r := LIP_ORBIT_MAX
		var start_ang := _cup_entry_offset.angle()
		var arc_abs := lerpf(LIP_IN_ARC_MIN, LIP_IN_ARC_MAX, offset_ratio)
		arc_abs *= lerpf(0.85, 1.15, speed_ratio)
		arc_abs *= lerpf(0.82, 1.18, randf())  # micro-line variation
		arc_abs = clampf(arc_abs, LIP_IN_ARC_MIN * 0.85, LIP_IN_ARC_MAX * 1.05)
		# Curl toward the side of the miss (cross of offset × approach).
		var approach := -_cup_entry_offset.normalized()
		if _launch_dir.length_squared() > 0.01:
			approach = _launch_dir
		var cross_z := _cup_entry_offset.x * approach.y - _cup_entry_offset.y * approach.x
		var arc_rad := -arc_abs if cross_z < 0.0 else arc_abs
		var curl_dur := (
			lerpf(LIP_IN_CURL_DUR_MIN, LIP_IN_CURL_DUR_MAX, offset_ratio)
			+ lerpf(0.0, 0.08, speed_ratio)
		)
		curl_dur *= clampf(arc_abs / LIP_IN_ARC_MAX, 0.35, 1.0)
		visual.position = Vector2.from_angle(start_ang) * orbit_r
		tw.tween_method(
			func(a: float) -> void:
				visual.position = Vector2.from_angle(a) * orbit_r,
			start_ang,
			start_ang + arc_rad,
			curl_dur
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position", Vector2.ZERO, LIP_DROP_DUR).set_trans(
			Tween.TRANS_QUAD
		).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(visual, "scale", Vector2.ONE * (start_s * 0.38), LIP_DROP_DUR).set_trans(
			Tween.TRANS_QUAD
		).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(
			visual, "self_modulate", Color(0.15, 0.15, 0.15, 0.35), LIP_DROP_DUR
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if shadow:
			tw.parallel().tween_property(shadow, "modulate:a", 0.0, LIP_DROP_DUR * 0.78)
	else:
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "scale", Vector2.ONE * (start_s * 0.38), LIP_DROP_DUR)
		tw.tween_property(visual, "self_modulate", Color(0.15, 0.15, 0.15, 0.35), LIP_DROP_DUR)
		if shadow:
			tw.tween_property(shadow, "modulate:a", 0.0, LIP_DROP_DUR * 0.78)

	tw.finished.connect(
		func() -> void:
			visual.position = Vector2.ZERO
			_clear_cup_entry_stash()
			cup_drop_finished.emit(),
		CONNECT_ONE_SHOT
	)

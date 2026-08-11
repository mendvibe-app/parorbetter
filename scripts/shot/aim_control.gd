class_name AimControl
extends RefCounted

## Helpers for default aim placement and clamping.


static func default_aim_target(
	ball_pos: Vector2,
	cup_pos: Vector2,
	lie: String,
	club_max_yards: float,
	wind: Vector2 = Vector2.ZERO,
	severity: String = ""
) -> Vector2:
	## Start on the ball→pin line: at the pin if reachable, else at club distance toward pin.
	## Overclub snap past pin only when the *recommended* type is full/punch (true mismatch).
	## Pitch/chip/flop greenside must lock on pin — Full floor must not rewrite the corridor.
	if lie == "Green":
		return cup_pos
	var to_pin := cup_pos - ball_pos
	var pin_dist_px := to_pin.length()
	if pin_dist_px < 1.0:
		return cup_pos
	var pin_yd := BallPhysics.pixels_to_yards(pin_dist_px)
	if lie != "Green":
		var rec := TempoGrade.recommend_shot_type(lie, pin_yd, club_max_yards)
		var solved := BallPhysics.solve_committed_power(
			pin_yd, club_max_yards, lie, wind, severity, rec
		)
		if bool(solved["overclub"]) and BallPhysics.shot_type_uses_full_pocket(rec):
			var total_yd := BallPhysics.estimate_carry_yards(
				float(solved["power"]), club_max_yards, lie, severity, rec
			)
			return point_along_bearing(ball_pos, to_pin, total_yd)
	if pin_yd <= club_max_yards * 1.02:
		return cup_pos
	var along_yd := club_max_yards * 0.95
	return ball_pos + to_pin.normalized() * BallPhysics.yards_to_pixels(along_yd)


static func clamp_aim(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 40.0, 1040.0),
		clampf(pos.y, GREEN_Y_MIN, TEE_Y_MAX)
	)


const GREEN_Y_MIN := -200.0
## Covers max par-5 band (~650 yd → tee Y ≈ 1380) + slack.
const TEE_Y_MAX := 1500.0
## Screen-space nudge so the fingertip doesn't cover the aim marker (touch only).
const TOUCH_AIM_OFFSET_PX := Vector2(0, -72)


static func touch_aim_screen(screen_pos: Vector2) -> Vector2:
	return screen_pos + TOUCH_AIM_OFFSET_PX


static func make_circle_points(center: Vector2, radius_px: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius_px)
	return pts


## Point at `yards` along bearing from ball (bearing is world direction).
static func point_along_bearing(from: Vector2, bearing: Vector2, yards: float) -> Vector2:
	var dir := bearing.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)
	return clamp_aim(from + dir * BallPhysics.yards_to_pixels(maxf(yards, 2.0)))


## Keep distance, change only direction — aim is a corridor, not a yardage pick.
static func retarget_bearing(from: Vector2, world: Vector2, lock_yards: float) -> Vector2:
	var bearing := world - from
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	return point_along_bearing(from, bearing, lock_yards)


## Finds where a straight line from external point `p` is tangent to the circle
## (c, r), picking whichever of the two tangent points sits on the `right`-ward
## side. A tangent line touches the circle at exactly one point, so a cone flank
## built this way meets the circle without ever crossing its boundary — no flat
## cap, no seam. Falls back to the near-axis point on the circle if `p` is
## already inside/on it (degenerate for very short, wide-dispersion shots).
static func _tangent_point(p: Vector2, c: Vector2, r: float, right: Vector2) -> Vector2:
	var d_vec := p - c
	var d := d_vec.length()
	if d <= r + 0.001:
		return c + (d_vec / maxf(d, 0.001)) * r
	var n := d_vec / d
	var phi := acos(clampf(r / d, -1.0, 1.0))
	var t_a := c + n.rotated(phi) * r
	var t_b := c + n.rotated(-phi) * r
	if (t_a - c).dot(right) >= (t_b - c).dot(right):
		return t_a
	return t_b


## Directional aim wedge: tight at the ball (takeoff direction is easy to read),
## flanks run tangent to the dispersion circle so they touch its boundary at a
## single point each — cone and circle always read as one seamless shape, at
## any shot length, with no flat cap ever crossing into or past the circle.
## shape_bend −draw / +fade (mid bulge only).
## power_preview sharpens the near end (narrower, denser) once % is live.
static func make_aim_cone(
	from: Vector2,
	to: Vector2,
	shape_bend: float = 0.0,
	near_half_w: float = 10.0,
	far_half_w: float = 40.0,
	power_preview: bool = false
) -> Dictionary:
	var along := to - from
	var length := along.length()
	# Short putts still need a readable cone — pad length, never replace bearing.
	# (Old floor forced Vector2(0,-1); ~5 ft putts then aimed straight up, not at the cup.)
	if length < 0.001:
		along = Vector2(0, -1)
		length = 8.0
	elif length < 8.0:
		along = along * (8.0 / length)
		length = 8.0
	var dir := along.normalized()
	var right := Vector2(-dir.y, dir.x)
	var near_w := near_half_w * (0.55 if power_preview else 1.0)
	var base_l := from - right * near_w
	var base_r := from + right * near_w
	var tip_r := _tangent_point(base_r, to, far_half_w, right)
	var tip_l := _tangent_point(base_l, to, far_half_w, -right)
	# Bulge the body toward the suggested shape, not the tangent points themselves —
	# nudging those off-axis would break tangency and reopen the seam.
	var axial_r := (tip_r - from).dot(dir)
	var axial_l := (tip_l - from).dot(dir)
	var far_axial := (axial_r + axial_l) * 0.5
	var far_w_r := (tip_r - from).dot(right)
	var far_w_l := -(tip_l - from).dot(right)
	var mid_axial := far_axial * 0.5
	var mid := from + dir * mid_axial + right * (shape_bend * mid_axial * 0.08)
	# Warm near ball → gold into the circle (matches dispersion marker).
	var a0 := 0.22 if power_preview else 0.30
	var a1 := 0.38 if power_preview else 0.18
	var a2 := 0.55 if power_preview else 0.04
	var tip_col := Color(1.0, 0.9, 0.35, a2)
	var pts := PackedVector2Array([
		base_l,
		base_r,
		mid + right * lerpf(near_w, far_w_r, 0.5),
		tip_r,
	])
	var cols := PackedColorArray([
		Color(0.95, 0.95, 0.9, a0),
		Color(0.95, 0.95, 0.9, a0),
		Color(1.0, 0.92, 0.45, a1),
		tip_col,
	])
	# Trace the circle's own near-side arc from tip_r to tip_l instead of a straight
	# chord — the fill's far edge then hugs the circle's curve exactly, so nothing
	# (not even a faint low-alpha edge) cuts across the circle's face.
	var ang_r := (tip_r - to).angle()
	var ang_l := (tip_l - to).angle()
	var delta := wrapf(ang_l - ang_r, -PI, PI)
	var arc_segments := 8
	for i in range(1, arc_segments):
		var a := ang_r + delta * (float(i) / float(arc_segments))
		pts.append(to + Vector2(cos(a), sin(a)) * far_half_w)
		cols.append(tip_col)
	pts.append(tip_l)
	cols.append(tip_col)
	pts.append(mid - right * lerpf(near_w, far_w_l, 0.5))
	cols.append(Color(1.0, 0.92, 0.45, a1))
	return {"points": pts, "colors": cols}


static func aim_offset_label(ball_pos: Vector2, aim: Vector2, cup: Vector2) -> String:
	var pin_dir := (cup - ball_pos).normalized()
	if pin_dir == Vector2.ZERO:
		pin_dir = Vector2(0, -1)
	var right := Vector2(-pin_dir.y, pin_dir.x)
	var to_aim := aim - cup
	var along := -to_aim.dot(pin_dir)  # + = short of pin along approach
	var lateral := to_aim.dot(right)
	var along_yd := BallPhysics.pixels_to_yards(along)
	var lat_yd := BallPhysics.pixels_to_yards(lateral)
	var parts: PackedStringArray = PackedStringArray()
	if absf(lat_yd) >= 1.0:
		parts.append("%s %d yd" % ["R" if lat_yd > 0.0 else "L", int(absf(lat_yd))])
	if absf(along_yd) >= 1.0:
		parts.append("%s %d yd" % ["short" if along_yd > 0.0 else "long", int(absf(along_yd))])
	if parts.is_empty():
		return "on pin line"
	return ", ".join(parts)

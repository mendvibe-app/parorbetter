class_name AimControl
extends RefCounted

## Helpers for default aim placement and clamping.


static func default_aim_target(
	ball_pos: Vector2,
	cup_pos: Vector2,
	lie: String,
	club_max_yards: float
) -> Vector2:
	## Start on the ball→pin line: at the pin if reachable, else at club distance toward pin.
	if lie == "Green":
		return cup_pos
	var to_pin := cup_pos - ball_pos
	var pin_dist_px := to_pin.length()
	if pin_dist_px < 1.0:
		return cup_pos
	var pin_yd := BallPhysics.pixels_to_yards(pin_dist_px)
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
const TEE_Y_MAX := 920.0


static func make_circle_points(center: Vector2, radius_px: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius_px)
	return pts


## Directional aim wedge: wide near the ball, taper + fade outward. shape_bend: −draw / +fade.
static func make_aim_cone(
	from: Vector2,
	to: Vector2,
	shape_bend: float = 0.0,
	near_half_w: float = 36.0,
	far_half_w: float = 6.0
) -> Dictionary:
	var along := to - from
	var length := along.length()
	if length < 8.0:
		along = Vector2(0, -1)
		length = 8.0
	var dir := along.normalized()
	var right := Vector2(-dir.y, dir.x)
	# Soft curve for draw/fade — corridor, not a laser to an XY.
	var mid := from + dir * (length * 0.55) + right * (shape_bend * length * 0.12)
	var tip := from + dir * length + right * (shape_bend * length * 0.22)
	var pts := PackedVector2Array([
		from - right * near_half_w,
		from + right * near_half_w,
		mid + right * lerpf(near_half_w, far_half_w, 0.55),
		tip + right * far_half_w,
		tip - right * far_half_w,
		mid - right * lerpf(near_half_w, far_half_w, 0.55),
	])
	var cols := PackedColorArray([
		Color(1, 1, 1, 0.34),
		Color(1, 1, 1, 0.34),
		Color(1, 1, 1, 0.16),
		Color(1, 1, 1, 0.02),
		Color(1, 1, 1, 0.02),
		Color(1, 1, 1, 0.16),
	])
	return {"points": pts, "colors": cols}


static func wind_label(wind: Vector2) -> String:
	if wind.length() < 4.0:
		return "Wind calm"
	var a := rad_to_deg(atan2(wind.x, -wind.y))
	var dir := "↑ into"
	if a >= -45.0 and a < 45.0:
		dir = "↓ helping"
	elif a >= 45.0 and a < 135.0:
		dir = "→ right-to-left push"
	elif a >= -135.0 and a < -45.0:
		dir = "← left-to-right push"
	return "Wind %d  %s" % [int(wind.length()), dir]


static func wind_aim_hint(wind: Vector2) -> String:
	## Plain advice for where to shift the landing circle.
	if wind.length() < 4.0:
		return "No wind adjust needed"
	# Ball is pushed in wind vector direction (x right, -y up/help toward pin from tee)
	if absf(wind.x) >= absf(wind.y):
		if wind.x > 0.0:
			return "Aim LEFT of target (wind pushes right)"
		return "Aim RIGHT of target (wind pushes left)"
	if wind.y < 0.0:
		return "Club down / aim shorter (helping wind)"
	return "Take more club / aim longer (into wind)"


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

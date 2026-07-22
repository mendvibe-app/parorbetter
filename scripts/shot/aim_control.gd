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


## Directional aim wedge: wide near ball, tapers into the dispersion circle.
## shape_bend −draw / +fade (mid bulge only). Tip stays on from→to so cone meets the circle.
## power_preview sharpens (narrower, denser) once % is live.
static func make_aim_cone(
	from: Vector2,
	to: Vector2,
	shape_bend: float = 0.0,
	near_half_w: float = 42.0,
	far_half_w: float = 14.0,
	power_preview: bool = false
) -> Dictionary:
	var along := to - from
	var length := along.length()
	if length < 8.0:
		along = Vector2(0, -1)
		length = 8.0
	var dir := along.normalized()
	var right := Vector2(-dir.y, dir.x)
	# Stop just short of the circle so cone + circle read as one composition.
	var tip_len := length * (0.92 if power_preview else 0.88)
	# Tip must sit on the aim axis — bending it offline was desyncing the landing circle.
	var tip := from + dir * tip_len
	var mid := from + dir * (tip_len * 0.5) + right * (shape_bend * tip_len * 0.08)
	var near_w := near_half_w * (0.55 if power_preview else 1.0)
	var far_w := far_half_w * (0.7 if power_preview else 1.0)
	var pts := PackedVector2Array([
		from - right * near_w,
		from + right * near_w,
		mid + right * lerpf(near_w, far_w, 0.5),
		tip + right * far_w,
		tip - right * far_w,
		mid - right * lerpf(near_w, far_w, 0.5),
	])
	# Warm near ball → gold into the circle (matches dispersion marker).
	var a0 := 0.22 if power_preview else 0.30
	var a1 := 0.38 if power_preview else 0.18
	var a2 := 0.55 if power_preview else 0.04
	var cols := PackedColorArray([
		Color(0.95, 0.95, 0.9, a0),
		Color(0.95, 0.95, 0.9, a0),
		Color(1.0, 0.92, 0.45, a1),
		Color(1.0, 0.9, 0.35, a2),
		Color(1.0, 0.9, 0.35, a2),
		Color(1.0, 0.92, 0.45, a1),
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

class_name BallPhysics
extends RefCounted

## Club bag + launch. Power is % of club max.
## Distances use a shared yards↔pixels scale so UI estimates match flight.

const PX_PER_YARD := 2.25
## Share of total shot distance spent in the air (rest is roll/bounce).
const AIR_DISTANCE_FRACTION := 0.78


## Simple four-club bag: Driver, Iron, Wedge, Putter.
static func pick_club(remaining_yd: float, lie: String) -> Dictionary:
	if lie == "Green":
		# Scale putter to this putt — avoid a huge 12–50 yd club on tap-ins
		var putt_max := clampf(remaining_yd * 1.6, 4.0, 35.0)
		return {"name": "Putter", "max_yards": putt_max}

	var wedge := {"name": "Wedge", "max_yards": 100.0}
	var iron := {"name": "Iron", "max_yards": 180.0}
	var driver := {"name": "Driver", "max_yards": 260.0}

	if lie == "Sand":
		return wedge

	var need := remaining_yd * 1.08
	if lie == "Rough":
		need = remaining_yd * 1.2

	if need <= float(wedge["max_yards"]):
		return wedge
	if need <= float(iron["max_yards"]):
		return iron
	return driver


static func lie_multiplier(lie: String) -> float:
	match lie:
		"Tee":
			return 1.0
		"Fairway":
			return 1.0
		"Rough":
			return 0.82
		"Sand":
			return 0.7
		"Green":
			return 1.0
		_:
			return 1.0


## Tightens power/swing timing windows off poor lies (1.0 = no change).
static func lie_timing_scale(lie: String) -> float:
	match lie:
		"Rough":
			return 0.82
		"Sand":
			return 0.66
		_:
			return 1.0


static func yards_to_pixels(yards: float) -> float:
	return yards * PX_PER_YARD


static func pixels_to_yards(pixels: float) -> float:
	return pixels / PX_PER_YARD


## Estimated total distance for UI (assumes solid / good contact).
static func estimate_carry_yards(power: float, club_max_yards: float, lie: String) -> float:
	return club_max_yards * clampf(power, 0.0, 1.0) * lie_multiplier(lie)


static func recommended_power(remaining_yd: float, club_max_yards: float, lie: String, wind: Vector2 = Vector2.ZERO) -> float:
	var effective_max := club_max_yards * lie_multiplier(lie)
	if effective_max <= 0.01:
		return 1.0
	var wind_yards := 0.0
	if lie != "Green":
		wind_yards = -wind.y * 0.35 + absf(wind.x) * 0.08
	var need := maxf(remaining_yd + wind_yards, 2.0)
	return clampf(need / effective_max, 0.05, 1.0)


static func contact_multiplier(quality: ShotResult.ContactQuality) -> float:
	match quality:
		ShotResult.ContactQuality.PERFECT:
			return 1.04
		ShotResult.ContactQuality.GOOD:
			return 1.0
		ShotResult.ContactQuality.THIN:
			return 0.82
		ShotResult.ContactQuality.FAT:
			return 0.68
		ShotResult.ContactQuality.MISS:
			return 0.4
		_:
			return 1.0


static func launch_velocity(
	result: ShotResult,
	target_dir: Vector2,
	club_max_yards: float,
	lie: String
) -> Dictionary:
	var dir := target_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)

	var is_putt := lie == "Green"
	var power_mul := result.power * lie_multiplier(lie) * contact_multiplier(result.contact_quality)
	var total_yards := club_max_yards * power_mul
	var total_px := yards_to_pixels(total_yards)

	if is_putt:
		# Contact/path scale line more than full shots; soft clamp only
		var contact_scale := 1.0
		match result.contact_quality:
			ShotResult.ContactQuality.PERFECT:
				contact_scale = 0.55
			ShotResult.ContactQuality.GOOD:
				contact_scale = 0.85
			ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
				contact_scale = 1.35
			_:
				contact_scale = 1.6
		var line_miss := clampf(result.path_error, -1.0, 1.0) * 0.18 * contact_scale * (1.4 - result.stance_stability)
		var dist_err := 1.0
		match result.contact_quality:
			ShotResult.ContactQuality.THIN:
				dist_err = 1.12
			ShotResult.ContactQuality.FAT:
				dist_err = 0.78
			ShotResult.ContactQuality.MISS:
				dist_err = 0.65
			_:
				dist_err = 1.0
		total_yards *= dist_err
		total_px = yards_to_pixels(total_yards)
		var putt_right := Vector2(-dir.y, dir.x)
		var putt_launch := (dir + putt_right * line_miss).normalized()
		if putt_launch.dot(dir) < 0.35:
			putt_launch = (dir + putt_right * signf(line_miss) * 0.55).normalized()
		# Green roll decel ≈ 1.8 * 60 = 108
		var putt_speed := sqrt(2.0 * 108.0 * maxf(total_px, 1.0))
		return {
			"velocity": putt_launch * putt_speed,
			"spin": 0.0,
			"loft": 0.0,
			"carry_yards": total_yards,
			"travel_px": total_px,
			"landing_speed": putt_speed,
			"airborne_time": 0.0,
			"air_fraction": 0.0,
			"launch_dir": putt_launch,
			"is_putt": true,
		}

	var loft := 0.9
	if result.contact_quality == ShotResult.ContactQuality.THIN:
		loft = 0.55
	elif result.contact_quality == ShotResult.ContactQuality.FAT:
		loft = 1.05

	var air_time := lerpf(0.55, 1.15, clampf(result.power, 0.0, 1.0)) * loft
	var air_frac := AIR_DISTANCE_FRACTION
	if lie == "Sand":
		air_frac = 0.55

	var air_px := total_px * air_frac
	var base_speed := air_px / maxf(air_time, 0.05)

	var lateral := (result.path_error * 0.55 + result.intended_shape * 0.25) * (1.35 - result.stance_stability * 0.5)
	var spin := result.path_error * (1.2 - result.stance_stability * 0.5)
	match result.contact_quality:
		ShotResult.ContactQuality.THIN:
			spin *= 1.35
		ShotResult.ContactQuality.FAT:
			spin *= 0.7
		ShotResult.ContactQuality.MISS:
			spin *= 1.6
		ShotResult.ContactQuality.PERFECT:
			spin *= 0.35
		_:
			pass

	var right := Vector2(-dir.y, dir.x)
	var launch_dir := (dir + right * lateral * 0.65).normalized()
	if launch_dir.dot(dir) < 0.2:
		launch_dir = dir
	var velocity := launch_dir * base_speed

	var roll_px := total_px * (1.0 - air_frac)
	var landing_speed := 0.0
	if roll_px > 1.0:
		landing_speed = sqrt(2.0 * 144.0 * roll_px)

	return {
		"velocity": velocity,
		"spin": spin,
		"loft": loft,
		"carry_yards": total_yards,
		"travel_px": total_px,
		"landing_speed": landing_speed,
		"airborne_time": air_time,
		"air_fraction": air_frac,
		"launch_dir": launch_dir,
		"is_putt": false,
	}

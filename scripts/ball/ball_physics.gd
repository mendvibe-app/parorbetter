class_name BallPhysics
extends RefCounted

## Club bag + launch. Power is % of club max.
## Distances use a shared yards↔pixels scale so UI estimates match flight.

const PX_PER_YARD := 2.25
## Share of total shot distance spent in the air (rest is roll/bounce).
const AIR_DISTANCE_FRACTION := 0.78

## Full bag, longest → shortest. Neighbor max gaps ~15–25 yd so overlap is real.
const BAG: Array[Dictionary] = [
	{"name": "Driver", "max_yards": 260.0},
	{"name": "3-Wood", "max_yards": 235.0},
	{"name": "Hybrid", "max_yards": 210.0},
	{"name": "5-Iron", "max_yards": 190.0},
	{"name": "6-Iron", "max_yards": 175.0},
	{"name": "7-Iron", "max_yards": 160.0},
	{"name": "8-Iron", "max_yards": 145.0},
	{"name": "9-Iron", "max_yards": 130.0},
	{"name": "Pitching Wedge", "max_yards": 110.0},
	{"name": "Gap/Sand Wedge", "max_yards": 85.0},
]

## Sensible swing pocket — outside this, force_factor > 0 (accuracy tax).
const POWER_POCKET_LO := 0.60
const POWER_POCKET_HI := 0.92
## Fixed putter range — never derive from remaining (that canceled to a constant %).
const PUTTER_MAX_YD := 35.0


static func is_wedge_family(club_name: String) -> bool:
	return club_name.contains("Wedge")


static func putter_for(_remaining_yd: float = 0.0) -> Dictionary:
	return {"name": "Putter", "max_yards": PUTTER_MAX_YD}


## Clubs the player may choose for this lie (excludes putter — green skips select).
static func clubs_for_lie(lie: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if lie == "Green":
		return out
	for club in BAG:
		var name := String(club["name"])
		if name == "Driver" and lie != "Tee":
			continue
		if lie == "Sand" and not is_wedge_family(name):
			continue
		out.append(club)
	return out


static func shot_need_yards(remaining_yd: float, lie: String) -> float:
	if lie == "Rough":
		return remaining_yd * 1.2
	return remaining_yd * 1.08


## Suggested club: shortest in the available bag that covers need (overlap = real choice).
static func pick_club(remaining_yd: float, lie: String) -> Dictionary:
	if lie == "Green":
		return putter_for(remaining_yd)

	var need := shot_need_yards(remaining_yd, lie)
	var available := clubs_for_lie(lie)
	if available.is_empty():
		return BAG[0]

	# BAG is longest→shortest; walk short→long for first cover.
	var i := available.size() - 1
	while i >= 0:
		if need <= float(available[i]["max_yards"]):
			return available[i]
		i -= 1
	return available[0]


## Percent of club for this distance (same math as recommended_power).
static func club_percent_today(
	remaining_yd: float, club_max_yards: float, lie: String, wind: Vector2 = Vector2.ZERO
) -> float:
	return recommended_power(remaining_yd, club_max_yards, lie, wind)


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


## 0 = in the pocket, 1 = fully forced (mash near 100% or baby a club).
static func force_factor(power: float) -> float:
	var p := clampf(power, 0.0, 1.0)
	if p > POWER_POCKET_HI:
		return clampf((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0, 1.0)
	if p < POWER_POCKET_LO:
		return clampf((POWER_POCKET_LO - p) / POWER_POCKET_LO, 0.0, 1.0)
	return 0.0


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
	var force := 0.0 if is_putt else force_factor(result.power)
	# Putts: tempo power_mul already leaked distance — don't stack contact ×0.4.
	var power_mul := result.power * lie_multiplier(lie)
	if not is_putt:
		power_mul *= contact_multiplier(result.contact_quality)
	# Mash doesn't buy clean extra yards — contact gets jumpy instead.
	if force > 0.0 and result.power > POWER_POCKET_HI:
		power_mul *= lerpf(1.0, 0.94, force)
	var total_yards := club_max_yards * power_mul
	var total_px := yards_to_pixels(total_yards)

	if is_putt:
		# Contact/path scale line; kept milder so tempo testing isn't a line lottery.
		var contact_scale := 1.0
		match result.contact_quality:
			ShotResult.ContactQuality.PERFECT:
				contact_scale = 0.45
			ShotResult.ContactQuality.GOOD:
				contact_scale = 0.70
			ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
				contact_scale = 1.15
			_:
				contact_scale = 1.35
		var line_miss := clampf(result.path_error, -1.0, 1.0) * 0.14 * contact_scale * (1.25 - result.stance_stability * 0.7)
		# THIN/FAT still shift pace; MISS distance already paid in tempo power_mul.
		var dist_err := 1.0
		match result.contact_quality:
			ShotResult.ContactQuality.THIN:
				dist_err = 1.12
			ShotResult.ContactQuality.FAT:
				dist_err = 0.78
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

	var stab_term := 1.35 - result.stance_stability * 0.5
	# Forcing a club (wrong bag choice, then mash/baby) taxes line the way it does IRL.
	var force_mul := 1.0 + force * 0.9
	var lateral := (result.path_error * 0.55 + result.intended_shape * 0.25) * stab_term * force_mul
	var spin := result.path_error * (1.2 - result.stance_stability * 0.5) * (1.0 + force * 0.7)
	# Even a pure path leaks offline when the swing is forced.
	lateral += force * 0.18 * (1.0 if result.path_error >= 0.0 else -1.0)
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

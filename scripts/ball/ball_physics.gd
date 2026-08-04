class_name BallPhysics
extends RefCounted

## Club bag + launch. Power is % of club max.
## Distances use a shared yards↔pixels scale so UI estimates match flight.

const PX_PER_YARD := 2.25
## Mid-iron baseline air share (see air_distance_fraction for per-club identity).
const AIR_DISTANCE_FRACTION := 0.78

## Full bag, longest → shortest. Neighbor max gaps ~15–25 yd so overlap is real.
## loft_mul scales visual apex + air_time (wedges fly higher for tree carries).
const BAG: Array[Dictionary] = [
	{"name": "Driver", "max_yards": 260.0, "loft_mul": 0.62},
	{"name": "3-Wood", "max_yards": 235.0, "loft_mul": 0.70},
	{"name": "Hybrid", "max_yards": 210.0, "loft_mul": 0.78},
	{"name": "5-Iron", "max_yards": 190.0, "loft_mul": 0.90},
	{"name": "6-Iron", "max_yards": 175.0, "loft_mul": 0.98},
	{"name": "7-Iron", "max_yards": 160.0, "loft_mul": 1.05},
	{"name": "8-Iron", "max_yards": 145.0, "loft_mul": 1.15},
	{"name": "9-Iron", "max_yards": 130.0, "loft_mul": 1.28},
	{"name": "Pitching Wedge", "max_yards": 110.0, "loft_mul": 1.42},
	{"name": "Gap/Sand Wedge", "max_yards": 85.0, "loft_mul": 1.52},
]


## Club apex/air loft scale by bag max_yards (launch has yards, not always name).
static func club_loft_mul(club_max_yards: float) -> float:
	if club_max_yards <= 0.0:
		return 1.0
	var best_mul := 1.0
	var best_d := 1.0e9
	for club in BAG:
		var d := absf(float(club["max_yards"]) - club_max_yards)
		if d < best_d:
			best_d = d
			best_mul = float(club.get("loft_mul", 1.0))
	return best_mul


## Clean-strike apex estimate (GOOD contact, same units as ball._height / canopy_h).
static func estimate_height_peak(
	club_max_yards: float, total_yards: float, shot_type: String = "full"
) -> float:
	if club_max_yards <= 0.0 or total_yards <= 0.5:
		return 0.0
	var loft := 0.9 * club_loft_mul(club_max_yards)
	if shot_type == "punch":
		loft *= PUNCH_LOFT_SCALE
	loft = clampf(loft, 0.35, 1.55)
	var power := clampf(total_yards / maxf(club_max_yards, 1.0), 0.05, 1.0)
	var air_time := lerpf(0.55, 1.15, power) * loft
	var air_frac := air_distance_fraction(club_max_yards, shot_type)
	var air_px := yards_to_pixels(total_yards) * air_frac
	var speed := air_px / maxf(air_time, 0.05)
	return (28.0 + speed * 0.02) * loft


## Height along the flight arc at distance `along_px` from the ball (0 on ground/roll).
static func estimate_height_at_along(
	along_px: float, total_px: float, air_frac: float, height_peak: float
) -> float:
	if height_peak <= 0.0 or total_px <= 1.0 or along_px < 0.0:
		return 0.0
	var air_px := total_px * clampf(air_frac, 0.05, 1.0)
	if along_px >= air_px:
		return 0.0  # landed / rolling — trees block on ground
	var t := clampf(along_px / maxf(air_px, 0.01), 0.0, 1.0)
	return sin(t * PI) * height_peak


## Closest-point distance along segment from→to to disk (c,r). -1 if no hit.
static func segment_hits_disk(from: Vector2, to: Vector2, c: Vector2, r: float) -> float:
	var along := to - from
	var len_sq := along.length_squared()
	if len_sq < 0.0001:
		return 0.0 if from.distance_to(c) <= r else -1.0
	var t := clampf((c - from).dot(along) / len_sq, 0.0, 1.0)
	var closest := from + along * t
	if closest.distance_to(c) > r:
		return -1.0
	return along.length() * t


## Sensible swing pocket — outside this, force_factor > 0 (accuracy tax).
const POWER_POCKET_LO := 0.60
const POWER_POCKET_HI := 0.92
## Fixed putter range — never derive from remaining (that canceled to a constant %).
## 25 yd = 75 ft: covers long lags with headroom past the hole (was 40 yd / 120 ft,
## calibrated to a corner-to-corner putt on the largest generated green — putts
## longer than 75 ft clamp to full pad, which is acceptable and realistic).
const PUTTER_MAX_YD := 25.0


static func is_wedge_family(club_name: String) -> bool:
	return club_name.contains("Wedge")


## Bag index for display order (Driver → … → wedges → Putter). Unknown clubs last.
static func club_bag_rank(club_name: String) -> int:
	var i := 0
	for club in BAG:
		if String(club["name"]) == club_name:
			return i
		i += 1
	if club_name == "Putter":
		return BAG.size()
	return 1000


## Compact labels for coach / tight UI: 3W, Hy, 5I, PW, SW, Pt.
static func club_short_name(club_name: String) -> String:
	match club_name:
		"Driver":
			return "Dr"
		"Hybrid":
			return "Hy"
		"Pitching Wedge":
			return "PW"
		"Gap/Sand Wedge":
			return "SW"
		"Putter":
			return "Pt"
		_:
			if club_name.ends_with("-Iron"):
				return club_name.replace("-Iron", "I")
			if club_name.ends_with("-Wood"):
				return club_name.replace("-Wood", "W")
			return club_name


static func sort_club_names_by_bag(names: Array) -> Array:
	var out: Array = names.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return club_bag_rank(str(a)) < club_bag_rank(str(b))
	)
	return out


## Realistic full-width (left-right) landing-pattern spread in yards for a
## typical mid-handicap amateur, by club category — launch-monitor/on-course
## ballpark figures. Longer clubs disperse much wider than short ones, so the
## aim/landing circle should shrink with the club, not stay a fixed size.
## Returns (low, high) — low = skilled/tight end, high = weak/wide end.
static func lateral_spread_range_yards(club_max_yards: float) -> Vector2:
	if club_max_yards >= 245.0:  # Driver
		return Vector2(40.0, 60.0)
	if club_max_yards >= 180.0:  # 3-Wood / Hybrid / long irons (4-5)
		return Vector2(25.0, 45.0)
	if club_max_yards >= 150.0:  # Mid irons (6-7)
		return Vector2(18.0, 35.0)
	if club_max_yards >= 120.0:  # Short irons (8-9)
		return Vector2(12.0, 25.0)
	if club_max_yards >= 95.0:  # Pitching Wedge
		return Vector2(10.0, 18.0)
	return Vector2(8.0, 18.0)  # Gap / Sand / Lob wedges


## Punch: lower apex (canopy duck) + more roll. Playtest knobs.
const PUNCH_LOFT_SCALE := 0.48
const PUNCH_AIR_FRAC_SCALE := 0.72
const PUNCH_SPIN_SCALE := 0.55
## Flight under foliage if height ≤ this × canopy_h (see ball tree collision).
const PUNCH_UNDER_CANOPY_FRAC := 0.88


## Carry share of total distance by club category (rest is roll). Same yard buckets
## as lateral_spread_range_yards. Full-swing defaults — short game overrides below.
static func air_distance_fraction(club_max_yards: float, shot_type: String = "full") -> float:
	var full := _air_fraction_full(club_max_yards)
	# Chip/pitch were using full-wedge carry (0.90–0.94) so they never released.
	if shot_type == "chip":
		# Mostly roll — releases past the pitch mark.
		return clampf(lerpf(0.48, 0.58, clampf((club_max_yards - 85.0) / 50.0, 0.0, 1.0)), 0.45, 0.62)
	if shot_type == "pitch":
		# More carry than chip, still more release than a stock full wedge.
		return clampf(lerpf(full, 0.72, 0.55), 0.68, 0.82)
	if shot_type == "punch":
		# Flatter flight — less carry share, more runout after land.
		return clampf(full * PUNCH_AIR_FRAC_SCALE, 0.52, 0.78)
	return full


static func _air_fraction_full(club_max_yards: float) -> float:
	if club_max_yards >= 245.0:  # Driver — low, hot, releases hard
		return 0.68
	if club_max_yards >= 180.0:  # 3W / Hybrid / long iron
		return 0.72
	if club_max_yards >= 150.0:  # Mid (6–7) — baseline
		return AIR_DISTANCE_FRACTION
	if club_max_yards >= 120.0:  # Short (8–9)
		return 0.84
	if club_max_yards >= 95.0:  # PW
		return 0.90
	return 0.94  # Gap / Sand


## Path-spin multiplier — mild club identity (pre-pack driver 0.75; avoid 0.92 over-flatten).
## Driver 0.78 keeps a bit freer flight than mid; wedge/driver ~1.54 (was 2.0).
static func spin_grip_mul(club_max_yards: float) -> float:
	if club_max_yards >= 245.0:
		return 0.78
	if club_max_yards >= 180.0:
		return 0.88
	if club_max_yards >= 150.0:
		return 1.0
	if club_max_yards >= 120.0:
		return 1.10
	if club_max_yards >= 95.0:
		return 1.15
	return 1.20


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
		# Trees: punch-out — no driver/woods (irons + hybrids + wedges ok).
		if lie == "Trees" and (name == "Driver" or name.contains("Wood")):
			continue
		out.append(club)
	return out


## Rough severity tiers (Rough lie severity epic). Weights sum to 1.0.
const ROUGH_SEV_BURIED := "Buried"
const ROUGH_SEV_AVERAGE := "Average"
const ROUGH_SEV_SITTING := "SittingUp"
## Cumulative: Buried 35%, Average 45%, SittingUp 20%.
const ROUGH_SEV_P_BURIED := 0.35
const ROUGH_SEV_P_AVERAGE := 0.80  # 0.35 + 0.45
const ROUGH_MUL_BURIED := 0.68
const ROUGH_MUL_AVERAGE := 0.82
const ROUGH_MUL_SITTING := 0.94
const ROUGH_TIMING_BURIED := 0.70
const ROUGH_TIMING_AVERAGE := 0.82
const ROUGH_TIMING_SITTING := 0.94


static func roll_rough_severity() -> String:
	var r := randf()
	if r < ROUGH_SEV_P_BURIED:
		return ROUGH_SEV_BURIED
	if r < ROUGH_SEV_P_AVERAGE:
		return ROUGH_SEV_AVERAGE
	return ROUGH_SEV_SITTING


static func shot_need_yards(remaining_yd: float, lie: String, severity: String = "") -> float:
	if lie == "Rough":
		var need := remaining_yd * 1.2
		# Buried chokes distance — ask for more club so pick/preview match swing math.
		if (
			GameState.rough_severity_enabled
			and severity == ROUGH_SEV_BURIED
		):
			need *= ROUGH_MUL_AVERAGE / ROUGH_MUL_BURIED
		return need
	if lie == "Trees":
		return remaining_yd * 1.35  # punch-out reality: more club than open rough
	return remaining_yd * 1.08


## Suggested club: shortest in the available bag that covers need (overlap = real choice).
static func pick_club(remaining_yd: float, lie: String, severity: String = "") -> Dictionary:
	if lie == "Green":
		return putter_for(remaining_yd)

	var need := shot_need_yards(remaining_yd, lie, severity)
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


## Compact picker window: up to `count` clubs centered on pick_club (clamped at bag ends).
static func suggest_clubs(
	remaining_yd: float, lie: String, count: int = 3, severity: String = ""
) -> Array[Dictionary]:
	var available := clubs_for_lie(lie)
	if available.is_empty() or count <= 0:
		return []
	var picked := pick_club(remaining_yd, lie, severity)
	var idx := 0
	for i in available.size():
		if String(available[i]["name"]) == String(picked["name"]):
			idx = i
			break
	var window := mini(count, available.size())
	var half := window >> 1
	var start := clampi(idx - half, 0, available.size() - window)
	var out: Array[Dictionary] = []
	for i in range(start, start + window):
		out.append(available[i])
	return out


## Recommended swing fraction for this distance (same math as recommended_power).
## UI shows this as "% swing" only when under a full hit — not "100% today".
static func club_percent_today(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = ""
) -> float:
	return recommended_power(remaining_yd, club_max_yards, lie, wind, severity)


static func lie_multiplier(lie: String, severity: String = "") -> float:
	match lie:
		"Tee":
			return 1.0
		"Fairway":
			return 1.0
		"Rough":
			if not GameState.rough_severity_enabled or severity.is_empty():
				return ROUGH_MUL_AVERAGE
			match severity:
				ROUGH_SEV_BURIED:
					return ROUGH_MUL_BURIED
				ROUGH_SEV_SITTING:
					return ROUGH_MUL_SITTING
				_:
					return ROUGH_MUL_AVERAGE
		"Sand":
			return 0.7
		"Trees":
			return 0.58  # punch-out — shorter than average rough
		"Green":
			return 1.0
		_:
			return 1.0


## Tightens power/swing timing windows off poor lies (1.0 = no change).
static func lie_timing_scale(lie: String, severity: String = "") -> float:
	match lie:
		"Rough":
			if not GameState.rough_severity_enabled or severity.is_empty():
				return ROUGH_TIMING_AVERAGE
			match severity:
				ROUGH_SEV_BURIED:
					return ROUGH_TIMING_BURIED
				ROUGH_SEV_SITTING:
					return ROUGH_TIMING_SITTING
				_:
					return ROUGH_TIMING_AVERAGE
		"Sand":
			return 0.66
		"Trees":
			return 0.62
		_:
			return 1.0


static func yards_to_pixels(yards: float) -> float:
	return yards * PX_PER_YARD


static func pixels_to_yards(pixels: float) -> float:
	return pixels / PX_PER_YARD


## Estimated total distance for UI (assumes solid / good contact).
static func estimate_carry_yards(
	power: float, club_max_yards: float, lie: String, severity: String = ""
) -> float:
	return club_max_yards * clampf(power, 0.0, 1.0) * lie_multiplier(lie, severity)


static func recommended_power(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = ""
) -> float:
	var effective_max := club_max_yards * lie_multiplier(lie, severity)
	if effective_max <= 0.01:
		return 1.0
	var wind_yards := 0.0
	if lie != "Green":
		wind_yards = -wind.y * 0.35 + absf(wind.x) * 0.08
	# Putts get their own floor — 2 ft (a real tap-in), not the full-shot 2 yd / 0.05
	# floor. lie_multiplier("Green") == 1.0, so effective_max == club_max_yards here.
	if lie == "Green":
		var need_putt := maxf(remaining_yd, 0.667)
		return clampf(need_putt / effective_max, 0.0267, 1.0)
	var need := maxf(remaining_yd + wind_yards, 2.0)
	return clampf(need / effective_max, 0.05, 1.0)


## Club-fit solve: uncapped true % + optional POWER_POCKET_LO floor for overclub.
## Shortest available club keeps true % (short-game baby swings). Never floors putts.
static func solve_committed_power(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = ""
) -> Dictionary:
	var true_pct := recommended_power(remaining_yd, club_max_yards, lie, wind, severity)
	var power := true_pct
	var overclub := false
	# Shortest club keeps baby swings (short game); everything else floors at pocket lo.
	if (
		lie != "Green"
		and not is_shortest_available(club_max_yards, lie)
		and true_pct < POWER_POCKET_LO
	):
		power = POWER_POCKET_LO
		overclub = true
	return {"power": power, "true_pct": true_pct, "overclub": overclub}


## True when this club is the shortest available for the lie (Gap on turf/sand).
static func is_shortest_available(club_max_yards: float, lie: String) -> bool:
	var available := clubs_for_lie(lie)
	if available.is_empty():
		return true
	return club_max_yards <= float(available[available.size() - 1]["max_yards"]) + 0.5


## 0 = in the pocket, 1 = fully forced (mash near 100% or baby a longer club).
## Shortest-club partials skip baby tax — that's correct short-game, not wrong bag.
static func force_factor(power: float, club_max_yards: float = 0.0, lie: String = "") -> float:
	var p := clampf(power, 0.0, 1.0)
	if p > POWER_POCKET_HI:
		return clampf((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0, 1.0)
	if p < POWER_POCKET_LO:
		if club_max_yards > 0.0 and not lie.is_empty() and is_shortest_available(club_max_yards, lie):
			return 0.0
		return clampf((POWER_POCKET_LO - p) / POWER_POCKET_LO, 0.0, 1.0)
	return 0.0


static func contact_multiplier(quality: ShotResult.ContactQuality) -> float:
	match quality:
		ShotResult.ContactQuality.PERFECT:
			return 1.06  # pure reads past committed (~15 yd driver / ~5 yd wedge)
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


## Dampen path/spin on very short shots so sidespin can't outrun forward speed.
static func short_shot_line_scale(total_yards: float) -> float:
	# Full line authority by ~40 yd; at 3–8 yd (greenside pitch) keep a small miss only.
	return clampf(total_yards / 40.0, 0.12, 1.0)


static func launch_velocity(
	result: ShotResult,
	target_dir: Vector2,
	club_max_yards: float,
	lie: String,
	severity: String = "",
	shot_type: String = "full"
) -> Dictionary:
	var dir := target_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)

	var is_putt := lie == "Green"
	# Club-fit force from true (uncapped) solve % when present — floored overclub power is always ≥ pocket.
	var force_p := result.power
	if result.true_power > 0.0:
		force_p = result.true_power
	var force := 0.0 if is_putt else force_factor(force_p, club_max_yards, lie)
	# Putts: tempo power_mul already leaked distance — don't stack contact ×0.4.
	var power_mul := result.power * lie_multiplier(lie, severity)
	if not is_putt:
		power_mul *= contact_multiplier(result.contact_quality)
	# Mash doesn't buy clean extra yards — contact gets jumpy instead.
	if force > 0.0 and result.power > POWER_POCKET_HI:
		power_mul *= lerpf(1.0, 0.94, force)
	var total_yards := club_max_yards * power_mul
	# Forced swings lose distance control (bias short + path wobble). In-pocket: no change.
	if force > 0.0 and not is_putt:
		var dist_mul := lerpf(1.0, 0.88, force)
		dist_mul *= 1.0 + clampf(result.path_error, -1.0, 1.0) * force * 0.04
		total_yards *= dist_mul
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
		# Amplitude owns pace; contact owns line only (no FAT/THIN distance stack).
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

	var club_loft := club_loft_mul(club_max_yards)
	var loft := 0.9 * club_loft
	if result.contact_quality == ShotResult.ContactQuality.THIN:
		loft = 0.55 * club_loft
	elif result.contact_quality == ShotResult.ContactQuality.FAT:
		loft = 1.05 * club_loft
	if shot_type == "punch":
		loft *= PUNCH_LOFT_SCALE

	var air_time := lerpf(0.55, 1.15, clampf(result.power, 0.0, 1.0)) * loft
	var air_frac := air_distance_fraction(club_max_yards, shot_type)
	if lie == "Sand" and shot_type == "full":
		air_frac = 0.55

	var air_px := total_px * air_frac
	var base_speed := air_px / maxf(air_time, 0.05)

	var stab_term := 1.35 - result.stance_stability * 0.5
	# Forcing a club (wrong bag choice, then mash/baby) taxes line the way it does IRL.
	var force_mul := 1.0 + force * 0.9
	# path_error = tempo miss; intended_shape = hole bias + swing path blend (shot_routine).
	var lateral := (result.path_error * 0.50 + result.intended_shape * 0.40) * stab_term * force_mul
	var spin := (
		result.path_error * (1.05 - result.stance_stability * 0.45)
		+ result.intended_shape * 0.55
	) * (1.0 + force * 0.7)
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
	spin *= spin_grip_mul(club_max_yards)
	if shot_type == "punch":
		# Punch trades shape control for a low flight — less sidespin authority.
		spin *= PUNCH_SPIN_SCALE
		lateral *= 0.85
	# Short greenside pitches: full-swing path/spin scale on ~3–15 yd total speed makes
	# the ball go sideways/back (playtest: plan 3 yd, path +1, actual flies offline).
	var line_scale := short_shot_line_scale(total_yards)
	lateral *= line_scale
	spin *= line_scale

	var right := Vector2(-dir.y, dir.x)
	# Cap offline aim: keep launch mostly toward target (was 0.2 → nearly 80° offline OK).
	var offline := clampf(lateral * 0.65, -0.85, 0.85)
	var launch_dir := (dir + right * offline).normalized()
	if launch_dir.dot(dir) < 0.55:
		launch_dir = (dir + right * signf(offline) * 0.45).normalized()
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

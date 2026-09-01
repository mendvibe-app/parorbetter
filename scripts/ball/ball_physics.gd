class_name BallPhysics
extends RefCounted

## Club bag + launch. Power is % of club max.
## Distances use a shared yards↔pixels scale so UI estimates match flight.

const PX_PER_YARD := 2.25

## Full bag, longest → shortest. Neighbor max gaps ~15–25 yd so overlap is real.
## loft_mul scales visual apex + air_time (wedges fly higher for tree carries).
## Phase 6: real PW / GW / SW / LW gapping (was merged Gap/Sand at 85).
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
	{"name": "Gap Wedge", "max_yards": 95.0, "loft_mul": 1.48},
	{"name": "Sand Wedge", "max_yards": 80.0, "loft_mul": 1.55},
	{"name": "Lob Wedge", "max_yards": 65.0, "loft_mul": 1.62},
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


## Apex estimate for UI preview (defaults GOOD — no contact yet at aim time).
## Same owner as launch — apex_for / hang_time (Phase 1).
static func estimate_height_peak(
	club_max_yards: float,
	total_yards: float,
	shot_type: String = "full",
	contact: String = "GOOD"
) -> float:
	if club_max_yards <= 0.0 or total_yards <= 0.5:
		return 0.0
	var power := clampf(total_yards / maxf(club_max_yards, 1.0), 0.01, 1.0)
	return apex_for(club_max_yards, power, shot_type, contact)


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
## Lane pad-Y fractions — must match tempo_gesture address_hint/top_hint branches.
const FULL_ADDRESS_Y := 0.30
const FULL_TOP_Y := 0.92
const SHORT_ADDRESS_Y := 0.30  ## pitch / flop / punch mid-lane
const SHORT_TOP_Y := 0.80
const CHIP_ADDRESS_Y := 0.20
const CHIP_TOP_Y := 0.85
## Fixed putter range — never derive from remaining (that canceled to a constant %).
## 25 yd = 75 ft: covers long lags with headroom past the hole (was 40 yd / 120 ft,
## calibrated to a corner-to-corner putt on the largest generated green — putts
## longer than 75 ft clamp to full pad, which is acceptable and realistic).
const PUTTER_MAX_YD := 25.0


## Pad-H length of the lane for this shot type (address → top).
static func lane_pad_len(shot_type: String = "full") -> float:
	match shot_type:
		"pitch", "flop", "punch":
			return absf(SHORT_TOP_Y - SHORT_ADDRESS_Y)
		"chip":
			return absf(CHIP_TOP_Y - CHIP_ADDRESS_Y)
		_:
			return absf(FULL_TOP_Y - FULL_ADDRESS_Y)


## Alias — Phase 1 harness / call sites.
static func full_lane_pad_len() -> float:
	return lane_pad_len("full")


## Power from backswing_len (pad-height). Floor = TempoGrade.bs_floor(shot_type).
## PLAYTEST TARGET — linear. Chip/putt use PuttStroke.power_from_frac instead.
static func power_from_amplitude(backswing_len: float, shot_type: String = "full") -> float:
	var floor_len := TempoGrade.bs_floor(shot_type)
	var full_len := lane_pad_len(shot_type)
	var span := maxf(full_len - floor_len, 0.001)
	var t := clampf((backswing_len - floor_len) / span, 0.0, 1.0)
	return lerpf(POWER_POCKET_LO, 1.0, t)


## Inverse of power_from_amplitude — advisory / pocket marker pad-H length.
static func amplitude_for_power(power: float, shot_type: String = "full") -> float:
	var floor_len := TempoGrade.bs_floor(shot_type)
	var full_len := lane_pad_len(shot_type)
	var p := clampf(power, POWER_POCKET_LO, 1.0)
	var t := (p - POWER_POCKET_LO) / maxf(1.0 - POWER_POCKET_LO, 0.001)
	return floor_len + t * (full_len - floor_len)


## TempoGrade-pad types that read power from amplitude (not aim). Chip/putt = PuttStroke.
static func uses_amplitude_power(shot_type: String) -> bool:
	return (
		shot_type == "full"
		or shot_type == "pitch"
		or shot_type == "flop"
		or shot_type == "punch"
	)


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


static func _bag_max_yards(club_name: String) -> float:
	for club in BAG:
		if String(club["name"]) == club_name:
			return float(club["max_yards"])
	return 0.0


## Which shot types this club can hit, by bag max yards. Full is always available.
## Flop: Sand Wedge + Lob Wedge only (Phase 6).
static func eligible_shot_types(club_max_yards: float) -> Array[String]:
	var types: Array[String] = ["full"]
	if club_max_yards <= 0.0:
		return types
	# 7-Iron and shorter → chip; PW and shorter → pitch (thresholds from BAG).
	if club_max_yards <= _bag_max_yards("7-Iron"):
		types.append("chip")
	if club_max_yards <= _bag_max_yards("Pitching Wedge"):
		types.append("pitch")
	# SW / LW only (max ≤ Sand Wedge) — not PW/GW.
	if club_max_yards <= _bag_max_yards("Sand Wedge") + 0.01:
		types.append("flop")
	return types


## Compact labels for coach / tight UI: 3W, Hy, 5I, PW, GW, SW, LW, Pt.
static func club_short_name(club_name: String) -> String:
	match club_name:
		"Driver":
			return "Dr"
		"Hybrid":
			return "Hy"
		"Pitching Wedge":
			return "PW"
		"Gap Wedge":
			return "GW"
		"Sand Wedge":
			return "SW"
		"Lob Wedge":
			return "LW"
		"Gap/Sand Wedge":  ## legacy coach keys
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
## Full-swing only — short game uses short_game_aim_radius_yards (display).
static func lateral_spread_range_yards(club_max_yards: float) -> Vector2:
	if club_max_yards >= 245.0:  # Driver
		return Vector2(40.0, 60.0)
	if club_max_yards >= 180.0:  # 3-Wood / Hybrid / long irons (4-5)
		return Vector2(25.0, 45.0)
	if club_max_yards >= 150.0:  # Mid irons (6-7)
		return Vector2(18.0, 35.0)
	if club_max_yards >= 120.0:  # Short irons (8-9)
		return Vector2(12.0, 25.0)
	if club_max_yards >= 95.0:  # PW / Gap Wedge
		return Vector2(10.0, 18.0)
	return Vector2(8.0, 18.0)  # Sand / Lob wedges


## Short-game aim-circle radius (yards) from planned rest yards + shot type.
## PLAYTEST TARGETS — epic_short_game_landing_circle table (ft ÷ 3). Display only;
## does not drive launch dispersion. Flop wider than pitch wider than chip.
## Returns base radius before form/force (GameState applies those).
static func short_game_aim_radius_yards(planned_rest_yd: float, shot_type: String) -> float:
	var d_near := 5.0
	var d_far := 20.0
	var r_near := 0.67  ## ~2 ft
	var r_far := 1.33  ## ~4 ft
	match shot_type:
		"pitch":
			d_near = 20.0
			d_far = 50.0
			r_near = 1.67  ## ~5 ft
			r_far = 3.33  ## ~10 ft
		"flop":
			d_near = 10.0
			d_far = 30.0
			r_near = 2.0  ## ~6 ft
			r_far = 4.0  ## ~12 ft
		_:
			pass  # chip defaults above
	var t := 0.0
	if d_far > d_near:
		t = clampf((planned_rest_yd - d_near) / (d_far - d_near), 0.0, 1.0)
	return lerpf(r_near, r_far, t)


## Punch: lower apex (canopy duck) + more roll. Playtest knobs.
const PUNCH_LOFT_SCALE := 0.48
const PUNCH_AIR_FRAC_SCALE := 0.88
const PUNCH_SPIN_SCALE := 0.55
## Flight under foliage if height ≤ this × canopy_h (see ball tree collision).
const PUNCH_UNDER_CANOPY_FRAC := 0.88

## --- Phase 3: carry share of total (PLAYTEST TARGETS, not final) ---
## Long clubs land shallow and release; short clubs land steep and stop.
## Continuous ramp — replaces the old bucket ladder that collapsed mid-iron gapping.
## Ease t^k keeps PW/GW sticky (~3–6% roll) so 7-iron does not inherit wood release.
const CARRY_FRAC_LONG := 0.80   ## driver end (~20% roll)
const CARRY_FRAC_SHORT := 0.98  ## lob wedge end (~2% roll)
const CARRY_FRAC_EASE := 1.5
## Check multiplier: >1 more decel. Driver releases, LW checks.
const CHECK_MUL_LONG := 0.9    ## driver
const CHECK_MUL_SHORT := 1.5   ## lob wedge
## PW and shorter (BAG Pitching Wedge 110). Pitch/flop also check.
const WEDGE_FAMILY_MAX_YD := 110.0
## PURE wedge/pitch/flop first bounce on Green — reverse along launch (not 10 yd).
const SPINBACK_FT := 4.0  ## PLAYTEST TARGET (band 2–6 ft)

## --- Phase 1: apex primary, hang derived (PLAYTEST TARGETS, not final) ---
## Real PGA Tour average max height in FEET, sampled at bag max_yards.
## Looked up by piecewise-linear interp (_real_apex_ft_for) — not nearest-key —
## so a distance retune cannot silently jump apex. Monotonic by construction.
const REAL_APEX_FT := {
	260.0: 102.0, 235.0: 95.0, 210.0: 94.0, 190.0: 93.0, 175.0: 92.0, 160.0: 92.0,
	145.0: 91.0, 130.0: 89.0, 110.0: 87.0, 95.0: 84.0, 80.0: 80.0, 65.0: 76.0,
}
## Game pixels per real foot of height. PLAYTEST TARGET.
const APEX_SCALE := 0.788
## Real gravity in apex px: 32.174 ft/s² × APEX_SCALE. See epic-real-time-pacing.
const GRAVITY_REAL_PX := 25.35
## Fraction of model-real flight duration (FRAC=1 → ~5 s driver hang).
## Tour avg driver hang is ~6.1–6.5 s; full real is too slow on phone.
## PLAYTEST TARGET — 0.40 ≈ 2.0 s driver (~32% Tour). 0.45 still a titch slow on device.
const FLIGHT_DURATION_FRAC := 0.40
## hang = sqrt(8 * apex / GRAVITY_PX). Derived so hang scales with FLIGHT_DURATION_FRAC.
const GRAVITY_PX := GRAVITY_REAL_PX / (FLIGHT_DURATION_FRAC * FLIGHT_DURATION_FRAC)
## ft/s² → px/s² (PX_PER_YARD / 3). PLAYTEST TARGET for roll/putt unit conversion.
const FT_TO_PX := PX_PER_YARD / 3.0
## Shared duration fraction for roll/putt (coherent with flight). PLAYTEST TARGET.
const ROLL_DURATION_FRAC := FLIGHT_DURATION_FRAC
## Shot-type apex multipliers. Pitch is explicit 1.0 (no arm). PLAYTEST TARGETS.
const APEX_SCALE_CHIP := 0.70
const APEX_SCALE_PUNCH := 0.35
const APEX_SCALE_FLOP := 1.80
## Contact apex multipliers — THIN low / FAT balloon (shape, not just distance). PLAYTEST TARGETS.
const APEX_SCALE_CONTACT := {
	"PERFECT": 1.04,
	"GOOD": 1.0,
	"THIN": 0.55,
	"FAT": 1.15,
	"MISS": 0.7,
}


## Carry share of total distance by club category (rest is roll). Same yard buckets
## as lateral_spread_range_yards. Full-swing defaults — short game overrides below.
## Chip/flop air fractions are playtest targets, not final (short-game roadmap Phases 2/5).
const FLOP_MAX_YD := 30.0  ## hard total-distance cap for flop (Phase 5)


## Piecewise-linear REAL_APEX_FT by club_max_yards.
## Exact at every table key (today's bag byte-identical); linear between keys so a
## max_yards nudge cannot jump to a neighbor and silently move apex. Clamp below
## 65 / above 260 to the endpoint values.
## Apex must not change as a side effect of a distance change — that coupling is
## the bug this removes.
static func _real_apex_ft_for(club_max_yards: float) -> float:
	var keys: Array[float] = []
	for k in REAL_APEX_FT.keys():
		keys.append(float(k))
	keys.sort()
	if keys.is_empty():
		return 80.0
	if club_max_yards <= keys[0]:
		return float(REAL_APEX_FT[keys[0]])
	if club_max_yards >= keys[keys.size() - 1]:
		return float(REAL_APEX_FT[keys[keys.size() - 1]])
	for i in range(keys.size() - 1):
		var k0 := keys[i]
		var k1 := keys[i + 1]
		if club_max_yards <= k1:
			var t := (club_max_yards - k0) / (k1 - k0)
			return lerpf(float(REAL_APEX_FT[k0]), float(REAL_APEX_FT[k1]), t)
	return float(REAL_APEX_FT[keys[keys.size() - 1]])


## Contact quality → APEX_SCALE_CONTACT key. Unknown → GOOD (UI preview default).
static func contact_apex_label(quality: ShotResult.ContactQuality) -> String:
	match quality:
		ShotResult.ContactQuality.PERFECT:
			return "PERFECT"
		ShotResult.ContactQuality.GOOD:
			return "GOOD"
		ShotResult.ContactQuality.THIN:
			return "THIN"
		ShotResult.ContactQuality.FAT:
			return "FAT"
		ShotResult.ContactQuality.MISS:
			return "MISS"
		_:
			return "GOOD"


## Apex in the same units as _height / canopy_h. Primary quantity — hang derives from it.
## `contact` is a quality label (PERFECT/GOOD/THIN/FAT/MISS); default GOOD for previews.
static func apex_for(
	club_max_yards: float,
	power: float,
	shot_type: String = "full",
	contact: String = "GOOD"
) -> float:
	var a := APEX_SCALE * _real_apex_ft_for(club_max_yards) * clampf(power, 0.01, 1.0)
	match shot_type:
		"chip":
			a *= APEX_SCALE_CHIP
		"punch":
			a *= APEX_SCALE_PUNCH
		"flop":
			a *= APEX_SCALE_FLOP
		_:
			pass  # full / pitch / empty = 1.0
	a *= float(APEX_SCALE_CONTACT.get(contact, 1.0))
	return maxf(a, 0.01)


## Hang time in seconds, derived from apex. Nothing else may invent air time.
static func hang_time(
	club_max_yards: float,
	power: float,
	shot_type: String = "full",
	contact: String = "GOOD"
) -> float:
	return sqrt(8.0 * apex_for(club_max_yards, power, shot_type, contact) / GRAVITY_PX)


static func air_distance_fraction(club_max_yards: float, shot_type: String = "full") -> float:
	var full := _air_fraction_full(club_max_yards)
	if shot_type == "chip":
		# ~67–80% roll (air ~20–33%) — "long putt with a wedge" (Phase 2 playtest target).
		return clampf(
			lerpf(0.28, 0.22, clampf((club_max_yards - 85.0) / 50.0, 0.0, 1.0)), 0.20, 0.33
		)
	if shot_type == "pitch":
		# Absolute — partial wedge lands steep and stops. Pinned so base-ramp retunes
		# do not silently drift pitch rollout (Phase 3 playtest target).
		return 0.90
	if shot_type == "flop":
		# Near-zero roll — soft high stop (air higher than pitch). Playtest target.
		return clampf(lerpf(0.94, 0.97, clampf((110.0 - club_max_yards) / 40.0, 0.0, 1.0)), 0.92, 0.98)
	if shot_type == "punch":
		# Knockdown lands shallow and runs — still less carry share than full.
		return clampf(full * PUNCH_AIR_FRAC_SCALE, 0.52, 0.90)
	return full


static func _air_fraction_full(club_max_yards: float) -> float:
	# Continuous ramp: short clubs stop, long clubs release. Replaces the bucket
	# ladder that collapsed mid-iron carry gaps to <3 yd.
	var t := clampf((club_max_yards - 65.0) / (260.0 - 65.0), 0.0, 1.0)
	t = pow(t, CARRY_FRAC_EASE)
	return lerpf(CARRY_FRAC_SHORT, CARRY_FRAC_LONG, t)


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
	if club_max_yards >= 75.0:
		return 1.18
	return 1.22


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
	severity: String = "",
	launch_dir: Vector2 = Vector2.UP
) -> float:
	return recommended_power(remaining_yd, club_max_yards, lie, wind, severity, launch_dir)


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


## THE single owner of total shot distance. No other code may compute or scale total_yards.
## Pre-swing callers pass GOOD contact and path_error 0 — contact is unknowable until grade.
## force_power < 0 → use power. Launch passes true_power override as force_power while the
## mash gate stays on power (matches historical force_p vs result.power split).
static func resolve_distance(
	club_max_yards: float,
	power: float,
	lie: String,
	severity: String = "",
	contact: ShotResult.ContactQuality = ShotResult.ContactQuality.GOOD,
	shot_type: String = "full",
	path_error: float = 0.0,
	force_power: float = -1.0
) -> float:
	var is_putt := lie == "Green"
	var force_p := power if force_power < 0.0 else force_power
	var force := 0.0 if is_putt else force_factor(force_p, club_max_yards, lie, shot_type)
	# Distance owner: lie × contact. Putt uses a mild Green curve (see contact_multiplier).
	var power_mul := power * lie_multiplier(lie, severity)
	power_mul *= contact_multiplier(contact, lie, shot_type)
	# Mash doesn't buy clean extra yards — contact gets jumpy instead.
	if force > 0.0 and power > POWER_POCKET_HI:
		power_mul *= lerpf(1.0, 0.94, force)
	var total_yards := club_max_yards * power_mul
	# Forced swings lose distance control (bias short + path wobble). In-pocket: no change.
	# Literal 0.88 kept for club_bag_check string assert — update that check if renamed.
	if force > 0.0 and not is_putt:
		var dist_mul := lerpf(1.0, 0.88, force)
		dist_mul *= 1.0 + clampf(path_error, -1.0, 1.0) * force * 0.04
		total_yards *= dist_mul
	if shot_type == "flop":
		total_yards = minf(total_yards, FLOP_MAX_YD)
	return total_yards


## Estimated total distance for UI (assumes solid / good contact).
static func estimate_carry_yards(
	power: float,
	club_max_yards: float,
	lie: String,
	severity: String = "",
	shot_type: String = "full"
) -> float:
	return resolve_distance(
		club_max_yards,
		clampf(power, 0.0, 1.0),
		lie,
		severity,
		ShotResult.ContactQuality.GOOD,
		shot_type,
		0.0
	)


static func recommended_power(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = "",
	launch_dir: Vector2 = Vector2.UP
) -> float:
	var wind_yards := 0.0
	if lie != "Green":
		# Project onto launch: default UP keeps legacy -wind.y / abs(wind.x).
		var dir := launch_dir.normalized() if launch_dir.length_squared() > 0.001 else Vector2.UP
		var head := wind.dot(dir)  # UP → -wind.y (legacy sign)
		var cross := absf(wind.dot(dir.orthogonal()))
		wind_yards = head * 0.35 + cross * 0.08
	# Putts get their own floor — 2 ft (a real tap-in), not the full-shot 2 yd / 0.05
	# floor. lie_multiplier("Green") == 1.0, so effective_max == club_max_yards here.
	if lie == "Green":
		var effective_putt := club_max_yards * lie_multiplier(lie, severity)
		if effective_putt <= 0.01:
			return 1.0
		var need_putt := maxf(remaining_yd, 0.667)
		return clampf(need_putt / effective_putt, 0.0267, 1.0)
	# Peak distance is at POWER_POCKET_HI (mash taxes above). Never recommend a power
	# whose resolved distance is shorter than a lower power's.
	# ponytail: sub-0.60 baby non-monotonicity is pre-existing / out of scope —
	# solve_committed_power floors full/punch to POWER_POCKET_LO.
	var max_yd := resolve_distance(
		club_max_yards, POWER_POCKET_HI, lie, severity,
		ShotResult.ContactQuality.GOOD, "full", 0.0
	)
	var need := maxf(remaining_yd + wind_yards, 2.0)
	if need >= max_yd:
		return POWER_POCKET_HI
	# In-pocket force=0 → distance = club_max * power * lie (GOOD contact).
	var effective_max := club_max_yards * lie_multiplier(lie, severity)
	if effective_max <= 0.01:
		return POWER_POCKET_HI
	return clampf(need / effective_max, 0.05, POWER_POCKET_HI)


## Club-fit solve: uncapped true % + optional POWER_POCKET_LO floor for overclub.
## Full/punch always floor under-pocket (no baby full). Pitch/chip/flop keep true %
## (shot types own short dial). Never floors putts.
static func solve_committed_power(
	remaining_yd: float,
	club_max_yards: float,
	lie: String,
	wind: Vector2 = Vector2.ZERO,
	severity: String = "",
	shot_type: String = "full",
	launch_dir: Vector2 = Vector2.UP
) -> Dictionary:
	var true_pct := recommended_power(
		remaining_yd, club_max_yards, lie, wind, severity, launch_dir
	)
	var power := true_pct
	var overclub := false
	if lie != "Green" and true_pct < POWER_POCKET_LO and shot_type_uses_full_pocket(shot_type):
		power = POWER_POCKET_LO
		overclub = true
	return {"power": power, "true_pct": true_pct, "overclub": overclub}


## Full (and punch) commit to the stock pocket — short aims overshoot.
## Pitch / chip / flop dial true % for short game.
static func shot_type_uses_full_pocket(shot_type: String) -> bool:
	return shot_type == "full" or shot_type == "punch" or shot_type.is_empty()


## True when this club is the shortest available for the lie (LW on turf/sand).
static func is_shortest_available(club_max_yards: float, lie: String) -> bool:
	var available := clubs_for_lie(lie)
	if available.is_empty():
		return true
	return club_max_yards <= float(available[available.size() - 1]["max_yards"]) + 0.5


## 0 = in the pocket, 1 = fully forced (mash near 100% or baby a longer club).
## Shortest-club partials skip baby tax only for pitch/chip/flop — full still taxes.
static func force_factor(
	power: float, club_max_yards: float = 0.0, lie: String = "", shot_type: String = "full"
) -> float:
	var p := clampf(power, 0.0, 1.0)
	if p > POWER_POCKET_HI:
		return clampf((p - POWER_POCKET_HI) / (1.0 - POWER_POCKET_HI), 0.0, 1.0)
	if p < POWER_POCKET_LO:
		if (
			club_max_yards > 0.0
			and not lie.is_empty()
			and is_shortest_available(club_max_yards, lie)
			and not shot_type_uses_full_pocket(shot_type)
		):
			return 0.0
		return clampf((POWER_POCKET_LO - p) / POWER_POCKET_LO, 0.0, 1.0)
	return 0.0


static func contact_multiplier(
	quality: ShotResult.ContactQuality, lie: String = "", shot_type: String = ""
) -> float:
	if lie == "Green":
		## PLAYTEST TARGET — putt-only; amplitude already owns the big miss.
		match quality:
			ShotResult.ContactQuality.THIN:
				return 1.06  ## skid / runs
			ShotResult.ContactQuality.FAT:
				return 0.90  ## dies
			ShotResult.ContactQuality.MISS:
				return 0.78
			_:
				return 1.0  ## PERFECT/GOOD — no 1.06 make-rate gift
	# Chip: committed yards. Full-swing PERFECT still reads a bit past (~15 yd driver).
	if shot_type == "chip" and quality == ShotResult.ContactQuality.PERFECT:
		return 1.0
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


## Putt launch offline scale. PLAYTEST — 0.14 made a 6 ft THIN ~1 in at the cup
## (still a make). 0.84 → ~5 in on a floor mishit (path 0.08, THIN, bal ~0.5).
const PUTT_LINE_MISS_SCALE := 0.84

## Putt launch offline (unitless). F1 `flat N in @ cup` is this × pin yards × 36.
static func putt_line_miss(result: ShotResult) -> float:
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
	return (
		clampf(result.path_error, -1.0, 1.0)
		* PUTT_LINE_MISS_SCALE
		* contact_scale
		* (1.25 - result.stance_stability * 0.7)
	)


## Roll friction in ft/s² (real-ish). Green 1.8 is stimpmeter-true; non-green
## values are effective decelerations including bounce loss (no bounce model).
## Decel px/s² = value * FT_TO_PX / ROLL_DURATION_FRAC². Single owner —
## landing_speed and GolfBall._process_roll both read here.
static func roll_friction_for(lie: String) -> float:
	match lie:
		"Green":
			return 1.8  ## stimp-10 real; no bounce on putt
		"Fairway", "Tee":
			return 10.0  ## PLAYTEST TARGET — effective with bounce (was 2.4 + wrong *60)
		"Rough":
			return 18.0  ## PLAYTEST TARGET
		"Sand":
			return 28.0  ## PLAYTEST TARGET
		_:
			return 12.0


## Deceleration in px/s² for roll/putt (shared duration fraction with flight).
static func roll_decel_px(lie: String) -> float:
	var f := ROLL_DURATION_FRAC
	return roll_friction_for(lie) * FT_TO_PX / maxf(f * f, 0.01)


## On-screen putt pace after true-scale zoom (Phase 2 camera). Distance unchanged:
## v' = k v, a' = k² a ⇒ s = v²/(2a) same; duration × 1/k. PLAYTEST TARGET (~30 ft zoom ratio).
const PUTT_PACE_SCALE := 0.35
## Chip/pitch/flop rollout on fairway/fringe — same idea (chips are ~70% roll).
const CHIP_PACE_SCALE := 0.38  ## PLAYTEST TARGET


## Green putt decel with pace scale (use for putt launch + putt roll only).
static func putt_decel_px() -> float:
	var k := PUTT_PACE_SCALE
	return roll_decel_px("Green") * k * k


static func is_short_game_shot(shot_type: String) -> bool:
	return shot_type == "chip" or shot_type == "pitch" or shot_type == "flop"


## Wedge family (full) or pitch/flop — check-and-stop; PURE can spin back on Green.
static func is_checking_club(club_max_yards: float, shot_type: String) -> bool:
	if shot_type == "pitch" or shot_type == "flop":
		return true
	return shot_type == "full" and club_max_yards <= WEDGE_FAMILY_MAX_YD + 0.5


## >1 more decel (check). Driver ~0.9 release, LW ~1.5. Chip is identity (hopping putt).
static func roll_check_mul(
	club_max_yards: float, shot_type: String, contact: String = "GOOD"
) -> float:
	var t := clampf((club_max_yards - 65.0) / (260.0 - 65.0), 0.0, 1.0)
	var full := lerpf(CHECK_MUL_SHORT, CHECK_MUL_LONG, t)
	var mul := full
	match shot_type:
		"pitch":
			mul = full * 1.25
		"flop":
			mul = full * 1.4
		"punch":
			mul = full * 0.85
		"chip", "putt":
			mul = 1.0
		_:
			pass
	if contact == "THIN":
		mul *= 0.92  ## slightly less check = more release
	return mul


## Roll decel: putt / chip-on-Green → stimp; else lie × check. Green approaches
## use fairway-class friction (not putt stimp) so a PW does not skate.
static func landing_roll_decel_px(
	lie: String,
	shot_type: String = "full",
	club_max_yards: float = 160.0,
	contact: String = "GOOD"
) -> float:
	if shot_type == "putt" or (shot_type == "chip" and lie == "Green"):
		return putt_decel_px()
	var check := roll_check_mul(club_max_yards, shot_type, contact)
	var a := roll_decel_px("Fairway") if lie == "Green" else roll_decel_px(lie)
	if lie != "Green" and is_short_game_shot(shot_type):
		var k := CHIP_PACE_SCALE
		a *= k * k
	return a * check


## Real g (ft/s²). Apex uses GRAVITY_REAL_PX (× APEX_SCALE); green roll uses this.
const GREEN_GRAVITY_FT := 32.174
## Sliding g over-breaks vs Pelz/AimPoint (rolling ball + grass). PLAYTEST TARGET.
## 0.45 ≈ 19 in break on a dying 20-ft 2% putt (Pelz 20 in). Full 1.0 if gyro later.
const GREEN_GRAVITY_SCALE := 0.45


static func green_gravity_px(pace_k: float = PUTT_PACE_SCALE) -> float:
	## px/s² per unit grade. Same FRAC²·k² as putt_decel so path stays yard-correct.
	var f := ROLL_DURATION_FRAC
	return GREEN_GRAVITY_FT * GREEN_GRAVITY_SCALE * FT_TO_PX / maxf(f * f, 0.01) * pace_k * pace_k


static func green_slope_accel(slope: Vector2, pace_k: float = PUTT_PACE_SCALE) -> Vector2:
	## Downhill accel. slope is percent grade (0.02 = 2%). One owner for putt + on-green roll.
	return slope * green_gravity_px(pace_k)


## Putts launch slower under PUTT_PACE_SCALE; settle must sit under that band.
const PUTT_SETTLE_SPEED := 0.525  ## was 1.5 × PUTT_PACE_SCALE
const ROLL_SETTLE_SPEED := 10.0


## Aim-preview rest after on-green roll. slope_at(world) → grade; ZERO off green.
## ponytail: coarse Euler, 8s cap. Live roll stays in GolfBall._process_roll.
static func preview_green_roll(
	land: Vector2, dir: Vector2, roll_px: float, slope_at: Callable
) -> Vector2:
	if roll_px < 2.0 or dir.length_squared() < 0.0001:
		return land
	var decel := putt_decel_px()
	var vel := dir.normalized() * sqrt(2.0 * decel * roll_px)
	var pos := land
	var dt := 1.0 / 30.0
	for _i in 240:
		if vel.length() < PUTT_SETTLE_SPEED:
			break
		if slope_at.is_valid():
			vel += green_slope_accel(slope_at.call(pos)) * dt
		vel = vel.move_toward(Vector2.ZERO, decel * dt)
		pos += vel * dt
	return pos


## Launch speed in px/s from already-resolved carry px + hang. Thin owner — does not
## re-derive resolve_distance / air_frac. Callers supply air_px and air_time.
## This is the **mean** ground speed over hang (distance-preserving). Peak at impact
## is mean × flight_speed_scale(0). See Golf_Ball_Speed_Physics_Research.pdf.
static func launch_speed_for(air_px: float, air_time: float) -> float:
	return air_px / maxf(air_time, 0.05)


## --- Flight speed envelope (research: peak at face, slow through air) ---
## Piecewise-linear raw knots (t, scale). Peak at impact, min near apex, mild
## descent recovery. Divided by FLIGHT_ENV_MEAN so ∫scale dt over [0,1] ≈ 1
## → carry distance stays owned by resolve_distance / air_frac.
## PLAYTEST TARGETS — land/peak ≈ 0.55 (Tour-ish 40–60% band).
const FLIGHT_ENV_T: Array[float] = [0.0, 0.20, 0.50, 0.72, 1.0]
const FLIGHT_ENV_S: Array[float] = [1.0, 0.70, 0.42, 0.48, 0.55]
## Trapezoid mean of FLIGHT_ENV_S over FLIGHT_ENV_T (precomputed).
const FLIGHT_ENV_MEAN := 0.5812


## Multiplier on mean air speed at normalized flight time t∈[0,1].
## scale(0)≈1.72 peak · scale(0.5)≈0.72 apex · scale(1)≈0.95 land · mean≈1.
static func flight_speed_scale(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	var raw := FLIGHT_ENV_S[FLIGHT_ENV_S.size() - 1]
	for i in range(FLIGHT_ENV_T.size() - 1):
		var t0: float = FLIGHT_ENV_T[i]
		var t1: float = FLIGHT_ENV_T[i + 1]
		if u <= t1 or i == FLIGHT_ENV_T.size() - 2:
			var s0: float = FLIGHT_ENV_S[i]
			var s1: float = FLIGHT_ENV_S[i + 1]
			var f := (u - t0) / maxf(t1 - t0, 0.0001)
			raw = lerpf(s0, s1, clampf(f, 0.0, 1.0))
			break
	return raw / maxf(FLIGHT_ENV_MEAN, 0.01)


## Peak ground speed at impact from mean (air_px/hang).
static func flight_peak_speed(mean_speed: float) -> float:
	return mean_speed * flight_speed_scale(0.0)


## Instantaneous target ground speed at flight progress t.
static func flight_speed_at(mean_speed: float, t: float) -> float:
	return mean_speed * flight_speed_scale(t)


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
	# force still drives lateral/spin accuracy tax below; distance has one owner.
	var force := 0.0 if is_putt else force_factor(force_p, club_max_yards, lie, shot_type)
	var total_yards := resolve_distance(
		club_max_yards,
		result.power,
		lie,
		severity,
		result.contact_quality,
		shot_type,
		result.path_error,
		force_p
	)
	var total_px := yards_to_pixels(total_yards)

	if is_putt:
		var line_miss := putt_line_miss(result)
		var putt_right := Vector2(-dir.y, dir.x)
		var putt_launch := (dir + putt_right * line_miss).normalized()
		if putt_launch.dot(dir) < 0.35:
			putt_launch = (dir + putt_right * signf(line_miss) * 0.55).normalized()
		# Green roll: a = putt_decel_px(); v = sqrt(2 a s) — pace scale keeps yards, slows screen.
		var putt_speed := sqrt(2.0 * putt_decel_px() * maxf(total_px, 1.0))
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
			"line_miss": line_miss,
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
	elif shot_type == "flop":
		loft *= 1.35  ## open-face pop — playtest loft scale

	# Hang from apex_for (incl. contact scale); no loft-lerp hang tax.
	var contact := contact_apex_label(result.contact_quality)
	var air_time := hang_time(club_max_yards, result.power, shot_type, contact)
	var apex := apex_for(club_max_yards, result.power, shot_type, contact)
	var air_frac := air_distance_fraction(club_max_yards, shot_type)
	if lie == "Sand" and shot_type == "full":
		# Relative to full air share — not an absolute. Absolute 0.55 was calibrated
		# against the old driver bucket (0.68) and goes silently wrong when the
		# carry scale moves (same failure mode as the old apex 28.0 constant).
		# 0.55/0.68 preserves the original ~19% sand tax. Do not "simplify" to a literal.
		air_frac = _air_fraction_full(club_max_yards) * (0.55 / 0.68)

	var air_px := total_px * air_frac
	# Mean ground speed (distance / hang). Peak at face is mean × flight_speed_scale(0).
	var mean_speed := launch_speed_for(air_px, air_time)
	var peak_speed := flight_peak_speed(mean_speed)

	var stab_term := 1.35 - result.stance_stability * 0.5
	# Forcing a club (wrong bag choice, then mash/baby) taxes line the way it does IRL.
	var force_mul := 1.0 + force * 0.9
	# Unified direction (full/pitch/punch): path_error == intended_shape from shot_routine
	# (swipe + gated tempo pull). Putt returns earlier with its own path_error.
	var lateral := result.intended_shape * 0.85 * stab_term * force_mul
	var spin := result.intended_shape * 0.95 * (1.0 + force * 0.7)
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
	# Curvature ∝ along_spd owns low-speed shape; launch lateral is not distance-damped.

	var right := Vector2(-dir.y, dir.x)
	# Cap offline aim: keep launch mostly toward target (was 0.2 → nearly 80° offline OK).
	var offline := clampf(lateral * 0.65, -0.85, 0.85)
	var launch_dir := (dir + right * offline).normalized()
	if launch_dir.dot(dir) < 0.55:
		launch_dir = (dir + right * signf(offline) * 0.45).normalized()
	# Research: max speed at face separation — never post-impact acceleration above peak.
	var velocity := launch_dir * peak_speed

	var roll_px := total_px * (1.0 - air_frac)
	var landing_speed := 0.0
	if roll_px > 1.0:
		var a_roll := landing_roll_decel_px(lie, shot_type, club_max_yards, contact)
		landing_speed = sqrt(2.0 * a_roll * roll_px)

	return {
		"velocity": velocity,
		"spin": spin,
		"loft": loft,
		"carry_yards": total_yards,
		"travel_px": total_px,
		"landing_speed": landing_speed,
		"airborne_time": air_time,
		"air_fraction": air_frac,
		"mean_air_speed": mean_speed,
		"launch_dir": launch_dir,
		"apex": apex,
		"is_putt": false,
	}

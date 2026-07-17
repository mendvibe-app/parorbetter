class_name HoleGenerator
extends RefCounted

## Data-driven hole / course factory.
## Randomness varies flavor within a band; hole number drives difficulty.

const DEFAULT_HOLE_COUNT := 18
const BUNKER_BASE_CHANCE := 0.75
const WATER_BASE_CHANCE := 0.30

## Base green-shape weights (Oval 35%, Kidney 25%, Tiered 15%, L 10%, Peninsula 8%, Complex 7%).
const GREEN_SHAPE_ITEMS: Array = [
	HoleData.GreenShape.OVAL,
	HoleData.GreenShape.KIDNEY,
	HoleData.GreenShape.TIERED,
	HoleData.GreenShape.L_SHAPED,
	HoleData.GreenShape.PENINSULA,
	HoleData.GreenShape.COMPLEX,
]
const GREEN_SHAPE_WEIGHTS_BASE: Array[float] = [0.35, 0.25, 0.15, 0.10, 0.08, 0.07]

## Yardage bands: short / medium / long [min, max] per par.
const YARDAGE: Dictionary = {
	3: {
		"bands": [[120.0, 160.0], [160.0, 210.0], [210.0, 250.0]],
		"weights": [0.25, 0.50, 0.25],
	},
	4: {
		"bands": [[300.0, 360.0], [360.0, 440.0], [440.0, 500.0]],
		"weights": [0.20, 0.55, 0.25],
	},
	5: {
		"bands": [[450.0, 520.0], [520.0, 590.0], [590.0, 650.0]],
		"weights": [0.30, 0.50, 0.20],
	},
}


static func difficulty_t(hole_number: int, total_holes: int = DEFAULT_HOLE_COUNT) -> float:
	## Ease-in so early holes stay forgiving and the finale is clearly hardest.
	var u := float(hole_number - 1) / float(maxi(total_holes - 1, 1))
	return u * u


static func pick_weighted(rng: RandomNumberGenerator, items: Array, weights: Array) -> Variant:
	assert(items.size() == weights.size() and items.size() > 0)
	var total := 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return items[rng.randi_range(0, items.size() - 1)]
	var roll := rng.randf() * total
	var acc := 0.0
	for i in items.size():
		acc += maxf(float(weights[i]), 0.0)
		if roll <= acc:
			return items[i]
	return items[items.size() - 1]


static func theme_modifiers(theme: HoleData.CourseTheme) -> Dictionary:
	## Multipliers / biases applied around the difficulty curve (never flatten it).
	match theme:
		HoleData.CourseTheme.LINKS:
			return {
				"wind_mult": 1.35,
				"bunker_mult": 1.15,
				"water_mult": 0.55,
				"fairway_mult": 0.95,
				"slope_mult": 1.1,
			}
		HoleData.CourseTheme.DESERT:
			return {
				"wind_mult": 1.1,
				"bunker_mult": 1.35,
				"water_mult": 0.15,
				"fairway_mult": 0.88,
				"slope_mult": 0.95,
			}
		_:
			return {
				"wind_mult": 1.0,
				"bunker_mult": 1.0,
				"water_mult": 1.0,
				"fairway_mult": 1.0,
				"slope_mult": 1.0,
			}


static func generate_course(
	course_seed: int = 0,
	theme: HoleData.CourseTheme = HoleData.CourseTheme.PARKLAND,
	hole_count: int = DEFAULT_HOLE_COUNT
) -> Array[HoleData]:
	var rng := RandomNumberGenerator.new()
	if course_seed == 0:
		rng.randomize()
	else:
		rng.seed = course_seed

	var pars := _par_bag_for_course(hole_count, rng)
	var holes: Array[HoleData] = []
	var prev_complexity := -1.0
	for i in hole_count:
		var hole_num := i + 1
		var hole := generate_hole(hole_num, rng, theme, hole_count, pars[i])
		# Structural ramp: complexity never drops below the previous hole.
		if prev_complexity >= 0.0:
			hole.complexity = maxf(hole.complexity, prev_complexity)
		prev_complexity = hole.complexity
		holes.append(hole)
	return holes


static func generate_hole(
	hole_number: int,
	rng: RandomNumberGenerator,
	theme: HoleData.CourseTheme = HoleData.CourseTheme.PARKLAND,
	total_holes: int = DEFAULT_HOLE_COUNT,
	par_override: int = 0
) -> HoleData:
	var t := difficulty_t(hole_number, total_holes)
	var mods := theme_modifiers(theme)

	var par: int
	if par_override >= 3 and par_override <= 5:
		par = par_override
	else:
		par = int(pick_weighted(rng, [3, 4, 5], [0.22, 0.56, 0.22]))

	var distance := _pick_yardage(rng, par, t)
	var green_shape: HoleData.GreenShape = _pick_green_shape(rng, t)
	var layout := _layout_for_shape(green_shape, t, rng)
	var has_bunker := rng.randf() < _bunker_chance(t, mods)
	var has_water := rng.randf() < _water_chance(t, mods)
	# Late holes almost always keep at least one hazard.
	if t >= 0.55 and not has_bunker and not has_water:
		has_bunker = true
	# Island / peninsula layouts need water for identity.
	if layout == HoleData.LayoutStyle.ISLAND or green_shape == HoleData.GreenShape.PENINSULA:
		has_water = true
	var hazard_count := (1 if has_bunker else 0) + (1 if has_water else 0)
	if t >= 0.75 and has_bunker and has_water and rng.randf() < 0.45:
		hazard_count += 1  # extra bunker feel / complexity bump

	var green_size := lerpf(0.92, 0.38, t) + rng.randf_range(-0.04, 0.04)
	green_size = clampf(green_size, 0.28, 1.0)
	var radii := _green_radii(green_shape, green_size, rng)

	var fairway_width := lerpf(165.0, 68.0, t) * float(mods.get("fairway_mult", 1.0))
	fairway_width += rng.randf_range(-8.0, 8.0)
	fairway_width = clampf(fairway_width, 60.0, 180.0)

	var wind_mag := lerpf(4.0, 52.0, t) * float(mods.get("wind_mult", 1.0))
	wind_mag *= rng.randf_range(0.85, 1.15)
	var wind_angle := rng.randf_range(0.0, TAU)
	var wind := Vector2(cos(wind_angle), sin(wind_angle)) * wind_mag
	# Prefer crosswind-ish Y components for readable UI (horizontal on portrait).
	wind.x = clampf(wind.x, -60.0, 60.0)
	wind.y = clampf(wind.y * 0.35, -20.0, 20.0)

	var slope_mag := lerpf(0.04, 0.42, t) * float(mods.get("slope_mult", 1.0))
	var slope := Vector2(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	).normalized() * slope_mag
	if slope.length_squared() < 0.0001:
		slope = Vector2(slope_mag, 0.0)

	var timing := lerpf(1.18, 0.52, t) + rng.randf_range(-0.03, 0.03)
	timing = clampf(timing, 0.45, 1.25)

	var complexity := clampf(t + rng.randf_range(-0.03, 0.03), 0.0, 1.0)

	var hazard_bias := HoleData.HazardBias.NONE
	if has_bunker or has_water:
		if t < 0.2 and rng.randf() < 0.55:
			hazard_bias = HoleData.HazardBias.NONE
		else:
			hazard_bias = HoleData.HazardBias.LEFT if rng.randf() < 0.5 else HoleData.HazardBias.RIGHT

	var suggested := _suggested_shape(layout, hazard_bias, rng)
	var bend := _fairway_bend(layout, t, rng)
	var tee_x := rng.randf_range(-18.0, 18.0) * lerpf(0.3, 1.0, t)
	var pin := _pin_offset(green_shape, radii, t, rng)

	var d := HoleData.new()
	d.hole_number = hole_number
	d.par = par
	d.distance_yards = distance
	d.fairway_width = fairway_width
	d.green_radius = (radii.x + radii.y) * 0.5
	d.green_radius_x = radii.x
	d.green_radius_y = radii.y
	d.pin_offset = pin
	d.tee_offset_x = tee_x
	d.fairway_bend = bend
	d.layout = layout
	d.wind_vector = wind
	d.green_slope = slope
	d.timing_window_scale = timing
	d.hazard_bias = hazard_bias
	d.suggested_shape = suggested
	d.name_label = _name_for_hole(hole_number, total_holes, layout, green_shape)
	d.green_shape = green_shape
	d.green_size = green_size
	d.hazard_count = hazard_count
	d.has_bunker = has_bunker
	d.has_water = has_water
	d.complexity = complexity
	d.theme = theme
	return d


static func _par_bag_for_course(hole_count: int, rng: RandomNumberGenerator) -> Array[int]:
	## Exact 4/10/4 mix for 18; proportional bags for other lengths.
	var bag: Array[int] = []
	if hole_count == 18:
		for _i in 4:
			bag.append(3)
		for _i in 10:
			bag.append(4)
		for _i in 4:
			bag.append(5)
	else:
		var n3 := clampi(int(round(float(hole_count) * 4.0 / 18.0)), 0, hole_count)
		var n5 := clampi(int(round(float(hole_count) * 4.0 / 18.0)), 0, hole_count - n3)
		var n4 := hole_count - n3 - n5
		for _i in n3:
			bag.append(3)
		for _i in n4:
			bag.append(4)
		for _i in n5:
			bag.append(5)

	_shuffle(bag, rng)
	return _place_pars_by_band(bag, hole_count, rng)


static func _place_pars_by_band(bag: Array[int], hole_count: int, rng: RandomNumberGenerator) -> Array[int]:
	## Keep exact counts; bias short/easy feel early and closers late via light swaps.
	var out: Array[int] = bag.duplicate()
	# Prefer a par 3 in the opening 3 if available.
	for i in mini(3, out.size()):
		if out[i] == 3:
			break
		for j in range(i + 1, out.size()):
			if out[j] == 3:
				var tmp := out[i]
				out[i] = out[j]
				out[j] = tmp
				break
	# Prefer a par 5 in the finishing 3 if available.
	var start := maxi(0, hole_count - 3)
	for i in range(hole_count - 1, start - 1, -1):
		if out[i] == 5:
			break
		for j in range(0, i):
			if out[j] == 5:
				var tmp2 := out[i]
				out[i] = out[j]
				out[j] = tmp2
				break
	# Light shuffle within front / middle / back so it isn't rigid.
	_shuffle_range(out, 0, mini(6, hole_count), rng)
	if hole_count > 9:
		_shuffle_range(out, 6, mini(12, hole_count), rng)
	if hole_count > 12:
		_shuffle_range(out, 12, hole_count, rng)
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _shuffle_range(arr: Array, from_idx: int, to_idx: int, rng: RandomNumberGenerator) -> void:
	var a := maxi(from_idx, 0)
	var b := mini(to_idx, arr.size())
	if b - a <= 1:
		return
	for i in range(b - 1, a, -1):
		var j := rng.randi_range(a, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _pick_yardage(rng: RandomNumberGenerator, par: int, t: float) -> float:
	var info: Dictionary = YARDAGE.get(par, YARDAGE[4])
	var bands: Array = info["bands"]
	var base_w: Array = info["weights"]
	# Shift short→long as difficulty rises.
	var weights: Array[float] = [
		float(base_w[0]) * lerpf(1.35, 0.45, t),
		float(base_w[1]) * lerpf(1.05, 1.0, t),
		float(base_w[2]) * lerpf(0.55, 1.55, t),
	]
	var band: Array = pick_weighted(rng, bands, weights)
	return rng.randf_range(float(band[0]), float(band[1]))


static func _pick_green_shape(rng: RandomNumberGenerator, t: float) -> HoleData.GreenShape:
	## Early: Oval/Kidney. Late: unlock Tiered / L / Peninsula / Complex.
	var easy_boost := lerpf(1.6, 0.55, t)
	var hard_boost := lerpf(0.35, 1.7, t)
	var weights: Array[float] = [
		GREEN_SHAPE_WEIGHTS_BASE[0] * easy_boost,  # OVAL
		GREEN_SHAPE_WEIGHTS_BASE[1] * easy_boost,  # KIDNEY
		GREEN_SHAPE_WEIGHTS_BASE[2] * lerpf(0.5, 1.3, t),  # TIERED
		GREEN_SHAPE_WEIGHTS_BASE[3] * hard_boost,  # L_SHAPED
		GREEN_SHAPE_WEIGHTS_BASE[4] * hard_boost,  # PENINSULA
		GREEN_SHAPE_WEIGHTS_BASE[5] * hard_boost,  # COMPLEX
	]
	return pick_weighted(rng, GREEN_SHAPE_ITEMS, weights)


static func _bunker_chance(t: float, mods: Dictionary) -> float:
	var chance := BUNKER_BASE_CHANCE * float(mods.get("bunker_mult", 1.0))
	# Early holes often skip bunkers; late rarely skip.
	chance *= lerpf(0.45, 1.2, t)
	return clampf(chance, 0.05, 0.98)


static func _water_chance(t: float, mods: Dictionary) -> float:
	var chance := WATER_BASE_CHANCE * float(mods.get("water_mult", 1.0))
	chance *= lerpf(0.25, 1.35, t)
	return clampf(chance, 0.0, 0.85)


static func _layout_for_shape(
	shape: HoleData.GreenShape,
	t: float,
	rng: RandomNumberGenerator
) -> HoleData.LayoutStyle:
	match shape:
		HoleData.GreenShape.PENINSULA:
			return HoleData.LayoutStyle.ISLAND
		HoleData.GreenShape.TIERED, HoleData.GreenShape.COMPLEX:
			return HoleData.LayoutStyle.BI_TIER
		HoleData.GreenShape.L_SHAPED:
			return HoleData.LayoutStyle.CHUTE
		HoleData.GreenShape.KIDNEY:
			return (
				HoleData.LayoutStyle.DOGLEG_LEFT
				if rng.randf() < 0.5
				else HoleData.LayoutStyle.DOGLEG_RIGHT
			)
		_:
			# Oval: escalate layout intensity with difficulty.
			if t < 0.25:
				return HoleData.LayoutStyle.STANDARD
			if t < 0.55:
				return (
					HoleData.LayoutStyle.DOGLEG_LEFT
					if rng.randf() < 0.5
					else HoleData.LayoutStyle.DOGLEG_RIGHT
				)
			if t < 0.8:
				return HoleData.LayoutStyle.CHUTE if rng.randf() < 0.55 else HoleData.LayoutStyle.DOGLEG_RIGHT
			return HoleData.LayoutStyle.ISLAND if rng.randf() < 0.4 else HoleData.LayoutStyle.BI_TIER


static func _green_radii(
	shape: HoleData.GreenShape,
	green_size: float,
	rng: RandomNumberGenerator
) -> Vector2:
	var base := lerpf(28.0, 58.0, green_size)
	var rx := base
	var ry := base
	match shape:
		HoleData.GreenShape.OVAL:
			rx = base * rng.randf_range(1.05, 1.25)
			ry = base * rng.randf_range(0.85, 1.0)
		HoleData.GreenShape.KIDNEY:
			rx = base * rng.randf_range(1.1, 1.35)
			ry = base * rng.randf_range(0.75, 0.95)
		HoleData.GreenShape.TIERED:
			rx = base * rng.randf_range(0.95, 1.15)
			ry = base * rng.randf_range(0.7, 0.9)
		HoleData.GreenShape.L_SHAPED:
			rx = base * rng.randf_range(1.15, 1.4)
			ry = base * rng.randf_range(0.65, 0.85)
		HoleData.GreenShape.PENINSULA:
			rx = base * rng.randf_range(0.85, 1.05)
			ry = base * rng.randf_range(0.85, 1.05)
		HoleData.GreenShape.COMPLEX:
			rx = base * rng.randf_range(0.9, 1.2)
			ry = base * rng.randf_range(0.65, 0.88)
	return Vector2(rx, ry)


static func _pin_offset(
	shape: HoleData.GreenShape,
	radii: Vector2,
	t: float,
	rng: RandomNumberGenerator
) -> Vector2:
	var edge := lerpf(0.15, 0.72, t)
	var ox := rng.randf_range(-radii.x, radii.x) * edge
	var oy := rng.randf_range(-radii.y, radii.y) * edge
	match shape:
		HoleData.GreenShape.TIERED, HoleData.GreenShape.COMPLEX:
			oy = -absf(oy) * lerpf(0.5, 1.0, t)  # favor back tier late
		HoleData.GreenShape.PENINSULA:
			ox *= 1.1
	return Vector2(ox, oy)


static func _fairway_bend(
	layout: HoleData.LayoutStyle,
	t: float,
	rng: RandomNumberGenerator
) -> float:
	var mag := lerpf(20.0, 120.0, t) * rng.randf_range(0.7, 1.15)
	match layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			return mag
		HoleData.LayoutStyle.DOGLEG_LEFT:
			return -mag
		HoleData.LayoutStyle.CHUTE:
			return rng.randf_range(-mag * 0.35, mag * 0.35)
		HoleData.LayoutStyle.ISLAND, HoleData.LayoutStyle.BI_TIER:
			return rng.randf_range(-mag * 0.45, mag * 0.45)
		_:
			return rng.randf_range(-12.0, 12.0) * t


static func _suggested_shape(
	layout: HoleData.LayoutStyle,
	bias: HoleData.HazardBias,
	rng: RandomNumberGenerator
) -> HoleData.SuggestedShape:
	match layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			return HoleData.SuggestedShape.FADE
		HoleData.LayoutStyle.DOGLEG_LEFT:
			return HoleData.SuggestedShape.DRAW
		_:
			if bias == HoleData.HazardBias.RIGHT:
				return HoleData.SuggestedShape.FADE if rng.randf() < 0.65 else HoleData.SuggestedShape.STRAIGHT
			if bias == HoleData.HazardBias.LEFT:
				return HoleData.SuggestedShape.DRAW if rng.randf() < 0.65 else HoleData.SuggestedShape.STRAIGHT
			return HoleData.SuggestedShape.STRAIGHT


static func _name_for_hole(
	hole_number: int,
	total_holes: int,
	layout: HoleData.LayoutStyle,
	shape: HoleData.GreenShape
) -> String:
	if hole_number <= 3:
		var warm := ["Warm-up", "Opening", "Easy Does It", "Get Settled"]
		return warm[(hole_number - 1) % warm.size()]
	if hole_number >= total_holes - 2:
		var close := ["Closer", "Par or Better", "Final Stretch", "Last Call"]
		return close[(total_holes - hole_number) % close.size()]
	match shape:
		HoleData.GreenShape.PENINSULA:
			return "Peninsula"
		HoleData.GreenShape.COMPLEX:
			return "Complex"
		HoleData.GreenShape.TIERED:
			return "Bi-Tier"
		HoleData.GreenShape.L_SHAPED:
			return "Elbow"
		HoleData.GreenShape.KIDNEY:
			return "Kidney"
		_:
			match layout:
				HoleData.LayoutStyle.DOGLEG_LEFT:
					return "Dogleg Left"
				HoleData.LayoutStyle.DOGLEG_RIGHT:
					return "Dogleg Right"
				HoleData.LayoutStyle.CHUTE:
					return "Squeeze"
				HoleData.LayoutStyle.ISLAND:
					return "Island Feel"
				_:
					return "Hole %d" % hole_number

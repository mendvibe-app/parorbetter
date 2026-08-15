class_name HoleGenerator
extends RefCounted

## Data-driven hole / course factory.
## Archetype picks identity; difficulty_t scales intensity and unlocks hard profiles.

const DEFAULT_HOLE_COUNT := 18
const BUNKER_BASE_CHANCE := 0.75
const WATER_BASE_CHANCE := 0.30
## USGA-style pin: ≥4 paces (~15 ft / 5 yd) from green edge and greenside trouble.
const PIN_EDGE_MARGIN_YD := 5.0
## ~3 ft cup shelf for uniform grade around the hole.
const PIN_SHELF_YD := 1.0
const PIN_MAX_LOCAL_SLOPE := 0.18
## PLAYTEST TARGET — expected shot lengths used to derive approach for green sizing.
const EXPECTED_DRIVE_YD := 235.0  ## solid but not maxed Driver
const EXPECTED_LAYUP_YD := 210.0  ## Hybrid second on a par 5
## Brauer / USGA-anchored green area (sq ft). PLAYTEST TARGET.
const GREEN_AREA_FLOOR_SQFT := 4300.0
const GREEN_AREA_CEIL_SQFT := 9000.0
## Width/depth per approach yard (26×31 at 160 yd). PLAYTEST TARGET.
const GREEN_WIDTH_PER_APPR := 0.1625
const GREEN_DEPTH_PER_APPR := 0.1940

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

## Per-par archetypes. yardage/green are weight mults; bunker/water/fairway/bend are scalars.
## t still nudges intensity, but these profiles own the hole's identity.
const ARCHETYPES: Dictionary = {
	3: [
		{
			"id": "long_iron",
			"label": "Long Iron",
			"yardage": [0.2, 0.55, 1.6],
			"green": [0.45, 0.25, 0.15, 0.08, 0.04, 0.03],
			"bunker": 0.95,
			"water": 0.7,
			"trees": 0.55,
			"fairway": 1.05,
			"green_size_bias": 0.08,
			"bend": 0.35,
			"hazard_side": 0.45,
		},
		{
			"id": "short_pitch",
			"label": "Short Pitch",
			"yardage": [1.7, 0.45, 0.1],
			"green": [0.25, 0.2, 0.2, 0.15, 0.08, 0.12],
			"bunker": 1.25,
			"water": 0.55,
			"trees": 0.85,
			"fairway": 0.9,
			"green_size_bias": -0.18,
			"bend": 0.4,
			"hazard_side": 0.7,
		},
		{
			"id": "island_green",
			"label": "Island Green",
			"yardage": [0.35, 1.1, 0.7],
			"green": [0.05, 0.05, 0.1, 0.05, 0.65, 0.1],
			"bunker": 0.55,
			"water": 1.8,
			"trees": 0.25,
			"fairway": 0.95,
			"green_size_bias": -0.12,
			"bend": 0.5,
			"hazard_side": 0.55,
			"force_water": true,
			# ~hole 9 on 18 (difficulty_t = u²); opening par-3s stay long-iron / short-pitch.
			"min_t": 0.22,
		},
	],
	4: [
		{
			"id": "short_sharp",
			"label": "Short & Sharp",
			"yardage": [1.85, 0.4, 0.1],
			"green": [0.4, 0.3, 0.12, 0.1, 0.04, 0.04],
			"bunker": 1.15,
			"water": 0.7,
			"trees": 1.25,
			"fairway": 0.72,
			"green_size_bias": -0.22,
			"bend": 0.55,
			"hazard_side": 0.65,
			"prefer_layout": "chute_or_standard",
		},
		{
			"id": "classic_dogleg",
			"label": "Classic Dogleg",
			"yardage": [0.35, 1.45, 0.45],
			"green": [0.28, 0.42, 0.12, 0.08, 0.05, 0.05],
			"bunker": 1.1,
			"water": 0.9,
			"trees": 0.95,
			"fairway": 0.95,
			"green_size_bias": 0.0,
			"bend": 1.25,
			"hazard_side": 0.75,
			"prefer_dogleg": true,
		},
		{
			"id": "long_bear",
			"label": "Long Bear",
			"yardage": [0.1, 0.45, 1.8],
			"green": [0.5, 0.28, 0.1, 0.06, 0.03, 0.03],
			"bunker": 0.65,
			"water": 0.45,
			"trees": 0.3,
			"fairway": 1.28,
			"green_size_bias": 0.1,
			"bend": 0.35,
			"hazard_side": 0.35,
			"prefer_layout": "standard",
		},
		{
			"id": "risk_reward",
			"label": "Risk-Reward",
			"yardage": [0.85, 1.0, 0.55],
			"green": [0.22, 0.22, 0.12, 0.12, 0.18, 0.14],
			"bunker": 1.45,
			"water": 1.55,
			"trees": 0.7,
			"fairway": 0.88,
			"green_size_bias": -0.08,
			"bend": 1.45,
			"hazard_side": 0.92,
			"prefer_dogleg": true,
			"force_cape": true,  ## Cape shoreline water (Leven/Cape epic)
			"force_water": true,
		},
		{
			"id": "target_green",
			"label": "Target Green",
			"yardage": [0.4, 1.2, 0.55],
			"green": [0.12, 0.15, 0.35, 0.18, 0.08, 0.12],
			"bunker": 1.05,
			"water": 0.75,
			"trees": 0.8,
			"fairway": 1.18,
			"green_size_bias": -0.26,
			"bend": 0.5,
			"hazard_side": 0.55,
			"prefer_layout": "approach",
		},
	],
	5: [
		{
			"id": "reachable",
			"label": "Reachable",
			"yardage": [1.7, 0.55, 0.15],
			"green": [0.25, 0.25, 0.15, 0.1, 0.12, 0.13],
			"bunker": 1.3,
			"water": 1.2,
			"trees": 0.75,
			"fairway": 0.95,
			"green_size_bias": -0.1,
			"bend": 0.9,
			"hazard_side": 0.8,
		},
		{
			"id": "three_shotter",
			"label": "Three-Shotter",
			"yardage": [0.15, 0.55, 1.7],
			"green": [0.45, 0.3, 0.12, 0.08, 0.03, 0.02],
			"bunker": 0.75,
			"water": 0.5,
			"trees": 0.35,
			"fairway": 1.22,
			"green_size_bias": 0.08,
			"bend": 0.4,
			"hazard_side": 0.4,
			"prefer_layout": "standard",
		},
		{
			"id": "hazard_gauntlet",
			"label": "Hazard Gauntlet",
			"yardage": [0.4, 1.1, 0.7],
			"green": [0.18, 0.2, 0.15, 0.12, 0.2, 0.15],
			"bunker": 1.4,
			"water": 1.65,
			"trees": 1.15,
			"fairway": 0.85,
			"green_size_bias": -0.06,
			"bend": 1.15,
			"hazard_side": 0.88,
			"prefer_dogleg": true,
			"force_cape": true,  ## Cape shoreline water (Leven/Cape epic)
			"force_water": true,
		},
	],
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
	var archetype_history: Array = []
	var prev_complexity := -1.0
	for i in hole_count:
		var hole_num := i + 1
		var hole := generate_hole(hole_num, rng, theme, hole_count, pars[i], archetype_history)
		# Structural ramp: complexity never drops below the previous hole.
		if prev_complexity >= 0.0:
			hole.complexity = maxf(hole.complexity, prev_complexity)
		prev_complexity = hole.complexity
		archetype_history.append({"par": hole.par, "id": hole.archetype})
		holes.append(hole)
	return holes


static func generate_hole(
	hole_number: int,
	rng: RandomNumberGenerator,
	theme: HoleData.CourseTheme = HoleData.CourseTheme.PARKLAND,
	total_holes: int = DEFAULT_HOLE_COUNT,
	par_override: int = 0,
	archetype_history: Array = []
) -> HoleData:
	var t := difficulty_t(hole_number, total_holes)
	var mods := theme_modifiers(theme)

	var par: int
	if par_override >= 3 and par_override <= 5:
		par = par_override
	else:
		par = int(pick_weighted(rng, [3, 4, 5], [0.22, 0.56, 0.22]))

	var arch: Dictionary = _pick_archetype(rng, par, archetype_history, t)

	var yardage := _pick_yardage(rng, par, t, arch)
	var green_shape: HoleData.GreenShape = _pick_green_shape(rng, t, arch)
	var layout := _layout_for_archetype(arch, green_shape, t, rng)
	# Sharpened Dogleg Corners epic — only meaningful for dogleg layouts; consumed
	# by HoleController._use_sharp_dogleg() behind the debug A/B flag.
	var corner_position := 0.5
	var corner_tightness := 0.0
	if layout == HoleData.LayoutStyle.DOGLEG_LEFT or layout == HoleData.LayoutStyle.DOGLEG_RIGHT:
		corner_position = rng.randf_range(0.34, 0.62)
		corner_tightness = clampf(rng.randf_range(0.4, 1.0) * lerpf(0.75, 1.1, t), 0.0, 1.0)
	var want_bunker := rng.randf() < _bunker_chance(t, mods, float(arch.get("bunker", 1.0)))
	var want_water := rng.randf() < _water_chance(t, mods, float(arch.get("water", 1.0)))
	if bool(arch.get("force_water", false)):
		want_water = true
	if t >= 0.55 and not want_bunker and not want_water:
		want_bunker = true
	if layout == HoleData.LayoutStyle.ISLAND or green_shape == HoleData.GreenShape.PENINSULA:
		want_water = true
	# Keep the roll so course seeds stay stable vs older generators.
	if t >= 0.75 and want_bunker and want_water:
		rng.randf()

	var size_bias := float(arch.get("green_size_bias", 0.0))
	# Distance-driven green sizing (epic-distance-driven-green-sizing): approach yards,
	# not difficulty t. size_bias + jitter AFTER area clamp so rails keep variety.
	var approach_yd := _approach_yards(par, yardage)
	var target_radii := _green_target_radii_px(approach_yd, size_bias, rng)
	var radii := _green_radii(green_shape, target_radii, rng)
	# Legacy 0–1 green_size for HoleData consumers (normalized by area vs mid range).
	var green_size := clampf(
		(PI * radii.x * radii.y) / (PI * 32.0 * 36.0),
		0.18,
		1.0
	)
	var contour := _pick_contour(rng, t, arch, green_shape)

	var fairway_width := (
		lerpf(165.0, 68.0, t)
		* float(mods.get("fairway_mult", 1.0))
		* float(arch.get("fairway", 1.0))
	)
	fairway_width += rng.randf_range(-8.0, 8.0)
	fairway_width = clampf(fairway_width, 60.0, 180.0)

	var wind_mag := lerpf(4.0, 52.0, t) * float(mods.get("wind_mult", 1.0))
	wind_mag *= rng.randf_range(0.85, 1.15)
	var wind_angle := rng.randf_range(0.0, TAU)
	var wind := Vector2(cos(wind_angle), sin(wind_angle)) * wind_mag
	# Full-circle wind (head/tail = cross) — no Y attenuation.
	wind.x = clampf(wind.x, -60.0, 60.0)
	wind.y = clampf(wind.y, -60.0, 60.0)

	var slope_mag := 0.0 if contour == HoleData.ContourProfile.FLAT else (
		lerpf(0.10, 0.48, rng.randf()) * float(mods.get("slope_mult", 1.0))
	)
	var slope := Vector2.ZERO
	if slope_mag > 0.0:
		slope = Vector2(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized() * slope_mag
		if slope.length_squared() < 0.0001:
			slope = Vector2(slope_mag, 0.0)

	var timing := lerpf(1.18, 0.52, t) + rng.randf_range(-0.03, 0.03)
	timing = clampf(timing, 0.45, 1.25)

	var complexity := clampf(t + rng.randf_range(-0.03, 0.03), 0.0, 1.0)

	var hazard_bias := HoleData.HazardBias.NONE
	var side_p := float(arch.get("hazard_side", 0.5))
	if want_bunker or want_water:
		if t < 0.2 and rng.randf() < lerpf(0.55, 0.25, side_p):
			hazard_bias = HoleData.HazardBias.NONE
		elif rng.randf() < side_p:
			hazard_bias = HoleData.HazardBias.LEFT if rng.randf() < 0.5 else HoleData.HazardBias.RIGHT

	var hazards := _build_hazards(
		want_bunker, want_water, layout, t, hazard_bias, rng, corner_position, arch
	)
	# Trees are hole design, not decoration — density by archetype (links open vs parkland chute).
	for tr in _build_trees(layout, t, hazard_bias, rng, arch, corner_position):
		hazards.append(tr)
	var suggested := _suggested_shape(layout, hazard_bias, rng)
	var bend := _fairway_bend(layout, t, rng) * float(arch.get("bend", 1.0))
	var tee_x := rng.randf_range(-18.0, 18.0) * lerpf(0.3, 1.0, t)
	var pin := _pick_pin(radii, contour, slope, hazards, green_shape, rng)

	var d := HoleData.new()
	d.hole_number = hole_number
	d.par = par
	d.yardage = yardage
	d.fairway_width = fairway_width
	d.green_radius_x = radii.x
	d.green_radius_y = radii.y
	d.pin_offset = pin
	d.tee_offset_x = tee_x
	# Multi-tee: White = yardage; Blue back / Red forward by par spread.
	if par <= 3:
		d.tee_blue_offset_yd = rng.randf_range(10.0, 15.0)
		d.tee_red_offset_yd = -rng.randf_range(8.0, 14.0)
	elif par >= 5:
		d.tee_blue_offset_yd = rng.randf_range(18.0, 28.0)
		d.tee_red_offset_yd = -rng.randf_range(16.0, 24.0)
	else:
		d.tee_blue_offset_yd = rng.randf_range(15.0, 22.0)
		d.tee_red_offset_yd = -rng.randf_range(14.0, 20.0)
	d.fairway_bend = bend
	d.corner_position = corner_position
	d.corner_tightness = corner_tightness
	d.layout = layout
	d.wind_vector = wind
	d.green_slope = slope
	d.timing_window_scale = timing
	d.hazard_bias = hazard_bias
	d.suggested_shape = suggested
	d.name_label = _name_for_hole(
		hole_number, total_holes, layout, green_shape, str(arch.get("label", ""))
	)
	d.green_shape = green_shape
	d.green_size = green_size
	d.contour_profile = contour
	d.hazards = hazards
	d.complexity = complexity
	d.archetype = str(arch.get("id", ""))
	return d


static func _archetypes_for_par(par: int) -> Array:
	return ARCHETYPES.get(par, ARCHETYPES[4])


## Anti-repeat: never back-to-back same id; heavily downweight within a 3-hole span.
## min_t locks hard identities (island, etc.) until the difficulty curve unlocks them.
static func archetype_weight(
	id: String, par: int, history: Array, t: float = 0.0, min_t: float = 0.0
) -> float:
	if t < min_t:
		return 0.0
	var w := 1.0
	var start := maxi(0, history.size() - 3)
	for i in range(start, history.size()):
		var h: Dictionary = history[i]
		if int(h.get("par", 0)) != par or str(h.get("id", "")) != id:
			continue
		if i == history.size() - 1:
			return 0.0
		# Inside the prior 3-hole window (par-4s are densest → harshest).
		w *= 0.08 if par == 4 else 0.18
	# Soft round-level downweight if this id already appeared for this par.
	for h2 in history:
		if int(h2.get("par", 0)) == par and str(h2.get("id", "")) == id:
			w *= 0.55
			break
	return w


static func _pick_archetype(
	rng: RandomNumberGenerator, par: int, history: Array, t: float = 0.0
) -> Dictionary:
	var list: Array = _archetypes_for_par(par)
	var weights: Array[float] = []
	for a in list:
		weights.append(
			archetype_weight(str(a.get("id", "")), par, history, t, float(a.get("min_t", 0.0)))
		)
	return pick_weighted(rng, list, weights)


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


static func _pick_yardage(
	rng: RandomNumberGenerator, par: int, t: float, arch: Dictionary = {}
) -> float:
	var info: Dictionary = YARDAGE.get(par, YARDAGE[4])
	var bands: Array = info["bands"]
	var base_w: Array = info["weights"]
	var arch_w: Array = arch.get("yardage", [1.0, 1.0, 1.0])
	# Archetype owns the band; t only mildly shifts short→long within it.
	var weights: Array[float] = [
		float(base_w[0]) * float(arch_w[0]) * lerpf(1.15, 0.85, t),
		float(base_w[1]) * float(arch_w[1]) * 1.0,
		float(base_w[2]) * float(arch_w[2]) * lerpf(0.85, 1.15, t),
	]
	var band: Array = pick_weighted(rng, bands, weights)
	return rng.randf_range(float(band[0]), float(band[1]))


static func _pick_green_shape(
	rng: RandomNumberGenerator, t: float, arch: Dictionary = {}
) -> HoleData.GreenShape:
	## Archetype shape table first; t softly unlocks harder shapes.
	## Peninsula is hard-locked early so non-island arches can't sneak an island green.
	var arch_g: Array = arch.get("green", [1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var easy_boost := lerpf(1.25, 0.7, t)
	# After warm-up holes, push kidney/tiered/L so greens don't all read as ovals.
	var mid_shape := lerpf(0.85, 1.35, clampf((t - 0.05) / 0.45, 0.0, 1.0))
	var hard_boost := lerpf(0.75, 1.25, t)
	var peninsula_gate := 0.0 if t < 0.22 else hard_boost
	var weights: Array[float] = [
		GREEN_SHAPE_WEIGHTS_BASE[0] * float(arch_g[0]) * easy_boost,
		GREEN_SHAPE_WEIGHTS_BASE[1] * float(arch_g[1]) * easy_boost * mid_shape,
		GREEN_SHAPE_WEIGHTS_BASE[2] * float(arch_g[2]) * lerpf(0.85, 1.15, t) * mid_shape,
		GREEN_SHAPE_WEIGHTS_BASE[3] * float(arch_g[3]) * hard_boost * mid_shape,
		GREEN_SHAPE_WEIGHTS_BASE[4] * float(arch_g[4]) * peninsula_gate,
		GREEN_SHAPE_WEIGHTS_BASE[5] * float(arch_g[5]) * hard_boost,
	]
	return pick_weighted(rng, GREEN_SHAPE_ITEMS, weights)


static func _bunker_chance(t: float, mods: Dictionary, arch_mult: float = 1.0) -> float:
	var chance := BUNKER_BASE_CHANCE * float(mods.get("bunker_mult", 1.0)) * arch_mult
	# t scales intensity inside the archetype (late risk-reward > early risk-reward).
	chance *= lerpf(0.7, 1.15, t)
	return clampf(chance, 0.05, 0.98)


static func _water_chance(t: float, mods: Dictionary, arch_mult: float = 1.0) -> float:
	var chance := WATER_BASE_CHANCE * float(mods.get("water_mult", 1.0)) * arch_mult
	chance *= lerpf(0.55, 1.25, t)
	return clampf(chance, 0.0, 0.9)


static func _layout_for_archetype(
	arch: Dictionary,
	shape: HoleData.GreenShape,
	t: float,
	rng: RandomNumberGenerator
) -> HoleData.LayoutStyle:
	if t >= 0.22 and (
		shape == HoleData.GreenShape.PENINSULA or bool(arch.get("force_water", false))
	):
		if shape == HoleData.GreenShape.PENINSULA or rng.randf() < 0.65:
			return HoleData.LayoutStyle.ISLAND
	if bool(arch.get("prefer_dogleg", false)):
		return (
			HoleData.LayoutStyle.DOGLEG_LEFT
			if rng.randf() < 0.5
			else HoleData.LayoutStyle.DOGLEG_RIGHT
		)
	match str(arch.get("prefer_layout", "")):
		"standard":
			return HoleData.LayoutStyle.STANDARD
		"chute_or_standard":
			return (
				HoleData.LayoutStyle.CHUTE
				if rng.randf() < 0.55
				else HoleData.LayoutStyle.STANDARD
			)
		"approach":
			if shape == HoleData.GreenShape.TIERED or shape == HoleData.GreenShape.COMPLEX:
				return HoleData.LayoutStyle.BI_TIER
			if shape == HoleData.GreenShape.L_SHAPED:
				return HoleData.LayoutStyle.CHUTE
			return HoleData.LayoutStyle.STANDARD if rng.randf() < 0.6 else HoleData.LayoutStyle.BI_TIER
		_:
			return _layout_for_shape(shape, t, rng)


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


## Approach length the green is sized for (par 3 = full yardage).
static func _approach_yards(par: int, yardage: float) -> float:
	var appr := yardage
	if par >= 4:
		appr -= EXPECTED_DRIVE_YD
	if par >= 5:
		appr -= EXPECTED_LAYUP_YD
	return clampf(appr, 60.0, 220.0)


## Target rx/ry in px from approach distance. Clamp area then apply bias/jitter.
static func _green_target_radii_px(
	approach_yd: float, size_bias: float, rng: RandomNumberGenerator
) -> Vector2:
	var w_yd := GREEN_WIDTH_PER_APPR * approach_yd
	var d_yd := GREEN_DEPTH_PER_APPR * approach_yd
	# Area sq ft = π * (w/2) * (d/2) * 9
	var area := PI * (w_yd * 0.5) * (d_yd * 0.5) * 9.0
	var target := clampf(area, GREEN_AREA_FLOOR_SQFT, GREEN_AREA_CEIL_SQFT)
	if area > 0.01:
		var s := sqrt(target / area)
		w_yd *= s
		d_yd *= s
	# AFTER clamp: archetype bias + rng so floor/ceiling holes still vary.
	var j := clampf(1.0 + size_bias * 0.12 + rng.randf_range(-0.05, 0.05), 0.88, 1.12)
	w_yd *= j
	d_yd *= j
	var rx := BallPhysics.yards_to_pixels(w_yd * 0.5)
	var ry := BallPhysics.yards_to_pixels(d_yd * 0.5)
	return Vector2(rx, ry)


## Area-preserving aspect variation (deeper-than-wide). target = pre-shape radii.
static func _green_radii(
	shape: HoleData.GreenShape,
	target: Vector2,
	rng: RandomNumberGenerator
) -> Vector2:
	var mx := 1.0
	var my := 1.0
	match shape:
		HoleData.GreenShape.OVAL:
			mx = rng.randf_range(0.85, 1.00)
			my = rng.randf_range(1.05, 1.25)
		HoleData.GreenShape.KIDNEY:
			mx = rng.randf_range(0.75, 0.95)
			my = rng.randf_range(1.10, 1.35)
		HoleData.GreenShape.TIERED:
			mx = rng.randf_range(0.70, 0.90)
			my = rng.randf_range(0.95, 1.15)
		HoleData.GreenShape.L_SHAPED:
			mx = rng.randf_range(0.65, 0.85)
			my = rng.randf_range(1.15, 1.40)
		HoleData.GreenShape.PENINSULA:
			mx = rng.randf_range(0.85, 1.05)
			my = rng.randf_range(0.85, 1.05)
		HoleData.GreenShape.COMPLEX:
			mx = rng.randf_range(0.65, 0.88)
			my = rng.randf_range(0.90, 1.20)
	# Normalize so mx*my = 1 → same area as target for every shape.
	var p := mx * my
	var n := sqrt(1.0 / maxf(p, 0.01))
	return Vector2(target.x * mx * n, target.y * my * n)


static func _pick_contour(
	rng: RandomNumberGenerator,
	t: float,
	arch: Dictionary,
	shape: HoleData.GreenShape
) -> HoleData.ContourProfile:
	if shape == HoleData.GreenShape.TIERED or shape == HoleData.GreenShape.COMPLEX:
		if t >= 0.15 or rng.randf() < 0.55:
			return HoleData.ContourProfile.BI_TIER
	var items: Array = [
		HoleData.ContourProfile.FLAT,
		HoleData.ContourProfile.SIDE_SLOPE,
		HoleData.ContourProfile.BOWL,
		HoleData.ContourProfile.RIDGE,
		HoleData.ContourProfile.FALSE_FRONT,
		HoleData.ContourProfile.BI_TIER,
	]
	# Early: side/bowl over flat so break shows up in testing; late unlock false-front / bi-tier.
	var weights: Array[float] = [
		lerpf(0.12, 0.03, t),
		lerpf(0.55, 0.28, t),
		lerpf(0.18, 0.22, t),
		lerpf(0.10, 0.15, t),
		0.0 if t < 0.2 else lerpf(0.1, 0.2, t),
		0.0 if t < 0.25 else lerpf(0.08, 0.18, t),
	]
	# Target-green archetypes lean false-front / bi-tier when unlocked.
	if str(arch.get("id", "")) == "target_green" and t >= 0.2:
		weights[4] *= 1.8
		weights[5] *= 1.5
	return pick_weighted(rng, items, weights)


static func _build_hazards(
	want_bunker: bool,
	want_water: bool,
	layout: HoleData.LayoutStyle,
	t: float,
	bias: HoleData.HazardBias,
	rng: RandomNumberGenerator,
	corner_position: float = 0.5,
	arch: Dictionary = {}
) -> Array:
	var side := 1
	if bias == HoleData.HazardBias.LEFT:
		side = -1
	elif bias == HoleData.HazardBias.RIGHT:
		side = 1
	elif rng.randf() < 0.5:
		side = -1

	var out: Array = []
	var is_island := layout == HoleData.LayoutStyle.ISLAND
	var is_dogleg := (
		layout == HoleData.LayoutStyle.DOGLEG_LEFT
		or layout == HoleData.LayoutStyle.DOGLEG_RIGHT
	)
	var dogleg_inside := -1 if layout == HoleData.LayoutStyle.DOGLEG_LEFT else 1

	if is_island and want_water:
		out.append(_haz("water", HoleData.ROLE_ISLAND_RING, 0, 0.05, 70.0, 0))

	# Cape before sand so _cull_hazards(3) cannot drop the identity water.
	var force_cape := is_dogleg and bool(arch.get("force_cape", false))
	if want_water and not is_island and force_cape:
		out.append(_haz(
			"water",
			HoleData.ROLE_SHORELINE,
			dogleg_inside,
			corner_position,
			lerpf(40.0, 56.0, t),
			0
		))

	if want_bunker:
		var greenside_p := lerpf(0.55, 0.9, t)
		var landing_p := 0.35 if layout == HoleData.LayoutStyle.STANDARD else 0.7
		if is_dogleg:
			landing_p = 0.85
			# Inside of dogleg.
			side = dogleg_inside
		if layout == HoleData.LayoutStyle.CHUTE:
			landing_p = 0.4
			greenside_p = 0.75
		if is_island:
			landing_p = 0.35
			greenside_p = 0.65

		var added_sand := false
		if rng.randf() < greenside_p:
			out.append(_haz("sand", HoleData.ROLE_GREENSIDE, side, 0.08, lerpf(32.0, 44.0, t), 1))
			added_sand = true
			# Skip opposite greenside when Cape already holds a hazard slot.
			if t >= 0.55 and rng.randf() < 0.4 and not force_cape:
				out.append(_haz("sand", HoleData.ROLE_GREENSIDE, -side, 0.1, 30.0, 2))
		if (not added_sand or t >= 0.35) and rng.randf() < landing_p:
			var along := rng.randf_range(0.42, 0.62)
			if is_dogleg:
				# Guard the actual corner/elbow, not just "somewhere along the bend"
				# (Sharpened Dogleg Corners epic).
				along = clampf(corner_position + rng.randf_range(-0.05, 0.05), 0.12, 0.88)
			out.append(_haz("sand", HoleData.ROLE_LANDING, side, along, lerpf(38.0, 52.0, t), 0))
			added_sand = true
		if not added_sand:
			out.append(_haz("sand", HoleData.ROLE_LANDING, side, 0.5, 42.0, 0))

	if want_water and not is_island and not force_cape:
		if layout == HoleData.LayoutStyle.CHUTE:
			out.append(_haz("water", HoleData.ROLE_EDGE, -1, 0.4, 50.0, 0))
			out.append(_haz("water", HoleData.ROLE_EDGE, 1, 0.4, 50.0, 0))
		elif rng.randf() < lerpf(0.45, 0.75, t):
			# Leven diagonal ~40% of dogleg carries; keep straight carry in rotation.
			if is_dogleg and rng.randf() < 0.4:
				var d_along := clampf(
					corner_position + rng.randf_range(-0.05, 0.05), 0.12, 0.88
				)
				out.append(_haz(
					"water",
					HoleData.ROLE_DIAGONAL,
					dogleg_inside,
					d_along,
					lerpf(22.0, 36.0, t),
					0
				))
			else:
				out.append(_haz(
					"water",
					HoleData.ROLE_CARRY,
					0,
					rng.randf_range(0.28, 0.48),
					lerpf(22.0, 36.0, t),
					0
				))
		else:
			out.append(_haz(
				"water", HoleData.ROLE_EDGE, side, rng.randf_range(0.25, 0.45), lerpf(40.0, 58.0, t), 0
			))

	return _cull_hazards(out, 3)


static func _haz(kind: String, role: String, side: int, along: float, size: float, art: int) -> Dictionary:
	return {
		"kind": kind,
		"role": role,
		"side": side,
		"along": along,
		"size": size,
		"art": art,
	}


static func _haz_tree(
	role: String, side: int, along: float, size: float, art: int, count: int
) -> Dictionary:
	var h := _haz("tree", role, side, along, size, art)
	h["count"] = maxi(count, 1)
	return h


static func _build_trees(
	layout: HoleData.LayoutStyle,
	t: float,
	bias: HoleData.HazardBias,
	rng: RandomNumberGenerator,
	arch: Dictionary,
	corner_position: float
) -> Array:
	## Real-hole tree design: some holes open (few), some framed/choked (many).
	var dens := float(arch.get("trees", 0.65))
	# Chance of a nearly treeless hole (links / long open).
	if dens < 0.4 and rng.randf() < 0.55:
		return []
	if dens < 0.75 and rng.randf() > lerpf(0.55, 0.92, dens):
		return []

	var side := 1
	if bias == HoleData.HazardBias.LEFT:
		side = -1
	elif bias == HoleData.HazardBias.RIGHT:
		side = 1
	elif rng.randf() < 0.5:
		side = -1

	var out: Array = []
	var is_dogleg := (
		layout == HoleData.LayoutStyle.DOGLEG_LEFT or layout == HoleData.LayoutStyle.DOGLEG_RIGHT
	)
	if is_dogleg:
		side = -1 if layout == HoleData.LayoutStyle.DOGLEG_LEFT else 1

	# Edge line — one side, stretched along a fairway segment (not a continuous hedge).
	var edge_count := int(round(lerpf(2.0, 5.0, dens * rng.randf_range(0.7, 1.0))))
	var edge_along := rng.randf_range(0.28, 0.55)
	out.append(_haz_tree(
		HoleData.ROLE_EDGE, side, edge_along, lerpf(26.0, 36.0, dens), rng.randi_range(0, 7), edge_count
	))
	# Occasional opposite-side scatter (lighter).
	if dens >= 0.7 and rng.randf() < 0.45:
		out.append(_haz_tree(
			HoleData.ROLE_EDGE, -side, rng.randf_range(0.4, 0.7), 28.0, rng.randi_range(0, 7),
			maxi(2, edge_count - 2)
		))

	# Landing / corner clump — guards the elbow or drive zone.
	if dens >= 0.5 and rng.randf() < lerpf(0.35, 0.8, dens):
		var along := rng.randf_range(0.42, 0.62)
		if is_dogleg:
			along = clampf(corner_position + rng.randf_range(-0.04, 0.04), 0.15, 0.85)
		out.append(_haz_tree(
			HoleData.ROLE_LANDING, side, along, lerpf(30.0, 42.0, dens), rng.randi_range(0, 7),
			int(round(lerpf(2.0, 4.0, dens)))
		))

	# Greenside trees — frame the green on mid/hard holes (clear of cup via placement).
	if dens >= 0.55 and rng.randf() < lerpf(0.25, 0.65, dens):
		out.append(_haz_tree(
			HoleData.ROLE_GREENSIDE, side if rng.randf() < 0.65 else -side, 0.06,
			lerpf(24.0, 34.0, dens), rng.randi_range(0, 7), int(round(lerpf(1.0, 3.0, dens)))
		))

	# Chute: extra walls of trees both sides mid-hole.
	if layout == HoleData.LayoutStyle.CHUTE and dens >= 0.8:
		out.append(_haz_tree(HoleData.ROLE_EDGE, -1, 0.45, 30.0, rng.randi_range(0, 7), 4))
		out.append(_haz_tree(HoleData.ROLE_EDGE, 1, 0.5, 30.0, rng.randi_range(0, 7), 4))

	return out


static func _cull_hazards(items: Array, max_n: int) -> Array:
	## Drop extras that share nearly the same along+side (generator-side separation).
	var kept: Array = []
	for h in items:
		var ok := true
		for k in kept:
			if str(h.get("role", "")) == HoleData.ROLE_ISLAND_RING:
				break
			if str(k.get("role", "")) == HoleData.ROLE_ISLAND_RING:
				continue
			var da: float = absf(float(h.get("along", 0.0)) - float(k.get("along", 0.0)))
			var same_side: bool = int(h.get("side", 0)) == int(k.get("side", 0))
			if da < 0.12 and same_side and str(h.get("kind", "")) == str(k.get("kind", "")):
				ok = false
				break
		if ok:
			kept.append(h)
		if kept.size() >= max_n:
			break
	return kept


static func _pick_pin(
	radii: Vector2,
	contour: HoleData.ContourProfile,
	slope: Vector2,
	hazards: Array,
	shape: HoleData.GreenShape,
	rng: RandomNumberGenerator
) -> Vector2:
	## USGA-inspired: inset from edge, clear of greenside trouble, calm cup shelf, roam zones.
	var margin := BallPhysics.yards_to_pixels(PIN_EDGE_MARGIN_YD)
	var shelf := BallPhysics.yards_to_pixels(PIN_SHELF_YD)
	var ix := maxf(radii.x - margin, radii.x * 0.35)
	var iy := maxf(radii.y - margin, radii.y * 0.35)
	var trouble := _greenside_trouble_locals(radii, hazards)

	var probe := HoleData.new()
	probe.green_radius_x = radii.x
	probe.green_radius_y = radii.y
	probe.green_slope = slope
	probe.contour_profile = contour

	var best := Vector2(0.0, -iy * 0.45)
	var best_score := INF
	var accepted: Array[Vector2] = []

	for by in [-1, 0, 1]:
		if _pin_zone_forbidden(contour, shape, by):
			continue
		for bx in [-1, 0, 1]:
			for _k in 3:
				var cand := _sample_pin_zone(bx, by, ix, iy, rng)
				if not _inside_ellipse(cand, ix, iy):
					continue
				if not _pin_clears_trouble(cand, trouble, margin):
					continue
				if contour == HoleData.ContourProfile.RIDGE and absf(cand.x) < ix * 0.18:
					continue
				var score := _pin_shelf_score(probe, cand, shelf)
				if score < best_score:
					best_score = score
					best = cand
				if score <= PIN_MAX_LOCAL_SLOPE:
					accepted.append(cand)

	if accepted.size() > 0:
		return accepted[rng.randi_range(0, accepted.size() - 1)]
	return best


static func _pin_zone_forbidden(
	contour: HoleData.ContourProfile, shape: HoleData.GreenShape, by: int
) -> bool:
	## by: -1 back, 0 mid, +1 front (tee / +Y).
	var back_only := (
		contour == HoleData.ContourProfile.FALSE_FRONT
		or contour == HoleData.ContourProfile.BI_TIER
		or shape == HoleData.GreenShape.TIERED
		or shape == HoleData.GreenShape.COMPLEX
	)
	if back_only and by > 0:
		return true
	if contour == HoleData.ContourProfile.FALSE_FRONT and by >= 0:
		return true
	return false


static func _sample_pin_zone(
	bx: int, by: int, ix: float, iy: float, rng: RandomNumberGenerator
) -> Vector2:
	var xr := _bucket_range(bx, ix)
	var yr := _bucket_range(by, iy)
	return Vector2(rng.randf_range(xr.x, xr.y), rng.randf_range(yr.x, yr.y))


static func _bucket_range(b: int, lim: float) -> Vector2:
	var third := lim / 3.0
	if b < 0:
		return Vector2(-lim, -third)
	if b > 0:
		return Vector2(third, lim)
	return Vector2(-third, third)


static func _inside_ellipse(p: Vector2, rx: float, ry: float) -> bool:
	var nx := p.x / maxf(rx, 1.0)
	var ny := p.y / maxf(ry, 1.0)
	return nx * nx + ny * ny <= 1.0


static func _greenside_trouble_locals(radii: Vector2, hazards: Array) -> Array:
	## Estimate greenside sand centers in green-local space (mirrors controller ring).
	var out: Array = []
	var rx := radii.x + 14.0
	var ry := radii.y + 14.0
	for h in hazards:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var role := str(h.get("role", ""))
		if role != HoleData.ROLE_GREENSIDE:
			continue
		if str(h.get("kind", "")) != "sand":
			continue
		var side := int(h.get("side", 1))
		var size := float(h.get("size", 36.0))
		var dist := maxf(rx, ry) + 10.0 + size
		var ang := -PI * 0.5 if side < 0 else PI * 0.5
		out.append({"c": Vector2(cos(ang), sin(ang)) * dist, "r": size})
	return out


static func _pin_clears_trouble(pin: Vector2, trouble: Array, margin: float) -> bool:
	for t in trouble:
		var c: Vector2 = t["c"]
		var r: float = float(t["r"])
		if pin.distance_to(c) < margin + r * 0.35:
			return false
	return true


static func _pin_shelf_score(probe: HoleData, pin: Vector2, shelf: float) -> float:
	## Lower is better. Soft-reject steep / non-uniform shelves via high score.
	probe.pin_offset = pin
	var s0 := probe.green_slope_at(pin).length()
	var mx := s0
	var mn := s0
	for i in 4:
		var a := TAU * 0.25 * float(i)
		var s := probe.green_slope_at(pin + Vector2(cos(a), sin(a)) * shelf).length()
		mx = maxf(mx, s)
		mn = minf(mn, s)
	var score := mx
	if mx > PIN_MAX_LOCAL_SLOPE:
		score += (mx - PIN_MAX_LOCAL_SLOPE) * 4.0
	if mx - mn > 0.12:
		score += (mx - mn) * 2.0
	return score


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


# Playtest: suggested shape must track real hole geometry (dogleg bend /
# corridor curve). Hazard side is independent of layout — never invent DRAW/FADE
# on a straight corridor just because bunkers sit left or right.
# Non-dogleg layouts: no fairway curvature to play around. A hazard existing
# somewhere on the hole is not, by itself, a reason to shape a shot — real golf
# only suggests shaping around a hazard that's actually in the shot's direct
# line, which this generator does not currently model. PLAYTEST TARGET: if hazard
# placement is later made line-aware, this can key off that instead of returning
# STRAIGHT unconditionally.
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
			return HoleData.SuggestedShape.STRAIGHT


static func _name_for_hole(
	hole_number: int,
	total_holes: int,
	layout: HoleData.LayoutStyle,
	shape: HoleData.GreenShape,
	archetype_label: String = ""
) -> String:
	if hole_number <= 3:
		var warm := ["Warm-up", "Opening", "Easy Does It", "Get Settled"]
		return warm[(hole_number - 1) % warm.size()]
	if hole_number >= total_holes - 2:
		var close := ["Closer", "Par or Better", "Final Stretch", "Last Call"]
		return close[(total_holes - hole_number) % close.size()]
	if archetype_label != "":
		return archetype_label
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

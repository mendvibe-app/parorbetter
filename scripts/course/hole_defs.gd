class_name HoleDefs
extends RefCounted

## Six progressive, visually distinct holes.


static func all_holes() -> Array[HoleData]:
	var holes: Array[HoleData] = []
	# 1 Warm-up — wide straight, round green, pin center
	holes.append(_h(1, "Warm-up", 4, 340.0, 160.0, 56.0, 56.0, 52.0, Vector2.ZERO, 0.0, 0.0,
		HoleData.LayoutStyle.STANDARD, Vector2(8, -4), Vector2(0.05, 0.0), 1.15,
		HoleData.HazardBias.NONE, HoleData.SuggestedShape.STRAIGHT))
	# 2 Breezy — dogleg right, oval green, pin right
	holes.append(_h(2, "Breezy", 4, 380.0, 130.0, 50.0, 62.0, 40.0, Vector2(28, -8), 20.0, 90.0,
		HoleData.LayoutStyle.DOGLEG_RIGHT, Vector2(-18, -10), Vector2(0.2, -0.05), 1.0,
		HoleData.HazardBias.RIGHT, HoleData.SuggestedShape.FADE))
	# 3 Squeeze — short chute, tiny green, pin back
	holes.append(_h(3, "Squeeze", 3, 175.0, 85.0, 36.0, 34.0, 42.0, Vector2(0, -16), 0.0, 0.0,
		HoleData.LayoutStyle.CHUTE, Vector2(22, 6), Vector2(-0.15, 0.28), 0.9,
		HoleData.HazardBias.NONE, HoleData.SuggestedShape.DRAW))
	# 4 Crosswind — long dogleg left, wide shallow green
	holes.append(_h(4, "Crosswind", 5, 480.0, 100.0, 44.0, 70.0, 36.0, Vector2(-30, 10), -30.0, -110.0,
		HoleData.LayoutStyle.DOGLEG_LEFT, Vector2(36, -12), Vector2(0.3, -0.12), 0.78,
		HoleData.HazardBias.RIGHT, HoleData.SuggestedShape.FADE))
	# 5 Island — water ring feel, small round green, pin left
	holes.append(_h(5, "Island Feel", 4, 400.0, 78.0, 34.0, 38.0, 38.0, Vector2(-18, 0), 0.0, 20.0,
		HoleData.LayoutStyle.ISLAND, Vector2(-40, 8), Vector2(-0.35, 0.18), 0.68,
		HoleData.HazardBias.LEFT, HoleData.SuggestedShape.DRAW))
	# 6 Finale — bi-tier slope, pin back-right, narrow
	holes.append(_h(6, "Par or Better", 4, 420.0, 70.0, 30.0, 48.0, 28.0, Vector2(22, -20), 10.0, 40.0,
		HoleData.LayoutStyle.BI_TIER, Vector2(48, -16), Vector2(0.4, 0.32), 0.55,
		HoleData.HazardBias.RIGHT, HoleData.SuggestedShape.STRAIGHT))
	return holes


static func get_hole(index_1based: int) -> HoleData:
	var holes := all_holes()
	var i := clampi(index_1based - 1, 0, holes.size() - 1)
	return holes[i]


static func _h(
	num: int,
	label: String,
	par: int,
	yards: float,
	fairway: float,
	green_avg: float,
	green_x: float,
	green_y: float,
	pin_off: Vector2,
	tee_x: float,
	bend: float,
	layout: HoleData.LayoutStyle,
	wind: Vector2,
	slope: Vector2,
	timing: float,
	bias: HoleData.HazardBias,
	shape: HoleData.SuggestedShape
) -> HoleData:
	var d := HoleData.new()
	d.hole_number = num
	d.name_label = label
	d.par = par
	d.distance_yards = yards
	d.fairway_width = fairway
	d.green_radius = green_avg
	d.green_radius_x = green_x
	d.green_radius_y = green_y
	d.pin_offset = pin_off
	d.tee_offset_x = tee_x
	d.fairway_bend = bend
	d.layout = layout
	d.wind_vector = wind
	d.green_slope = slope
	d.timing_window_scale = timing
	d.hazard_bias = bias
	d.suggested_shape = shape
	return d

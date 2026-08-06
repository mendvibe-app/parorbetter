class_name HoleData
extends Resource

## Per-hole layout + difficulty. Comments note how the course builder uses each field.

enum HazardBias { NONE, LEFT, RIGHT }
enum SuggestedShape { STRAIGHT, DRAW, FADE }
enum LayoutStyle { STANDARD, DOGLEG_LEFT, DOGLEG_RIGHT, ISLAND, CHUTE, BI_TIER }
enum GreenShape { OVAL, KIDNEY, TIERED, L_SHAPED, PENINSULA, COMPLEX }
enum CourseTheme { PARKLAND, LINKS, DESERT }
enum ContourProfile { FLAT, SIDE_SLOPE, BOWL, RIDGE, FALSE_FRONT, BI_TIER }
## Teeing grounds — Blue back (long), White middle, Red forward (short).
enum TeeSet { RED, WHITE, BLUE }

## Hazard role strings used in `hazards` specs.
const ROLE_GREENSIDE := "greenside"
const ROLE_LANDING := "landing"
const ROLE_CARRY := "carry"
const ROLE_EDGE := "edge"
const ROLE_ISLAND_RING := "island_ring"
const ROLE_DIAGONAL := "diagonal"  ## Leven: angled band across landing
const ROLE_SHORELINE := "shoreline"  ## Cape: elbow-hugging water panels

@export var hole_number: int = 1
@export var par: int = 4
@export var yardage: float = 400.0  ## White (middle) tee→green yards (layout length)
@export var fairway_width: float = 140.0
@export var green_radius_x: float = 36.0
@export var green_radius_y: float = 36.0
@export var pin_offset: Vector2 = Vector2.ZERO  ## from green center
@export var tee_offset_x: float = 0.0
## Yards from White: + toward tee (longer), − toward green (shorter).
@export var tee_blue_offset_yd: float = 20.0
@export var tee_red_offset_yd: float = -18.0
@export var fairway_bend: float = 0.0  ## lateral dogleg at mid fairway (px)
## Sharpened Dogleg Corners epic. Only consumed when GameState.sharp_dogleg_enabled
## is on and layout is DOGLEG_LEFT/DOGLEG_RIGHT (see HoleController._use_sharp_dogleg()).
## 0.0 = corner sits at the green, 1.0 = corner sits at the tee (same "along"
## convention as _fairway_center_at / hazard "along" specs).
@export var corner_position: float = 0.45
## 0.0 = current smooth 3-point curve, 1.0 = hard two-segment elbow at corner_position.
@export var corner_tightness: float = 0.0
@export var layout: LayoutStyle = LayoutStyle.STANDARD
@export var wind_vector: Vector2 = Vector2.ZERO
@export var green_slope: Vector2 = Vector2.ZERO
@export var timing_window_scale: float = 1.0
@export var hazard_bias: HazardBias = HazardBias.NONE
@export var suggested_shape: SuggestedShape = SuggestedShape.STRAIGHT
@export var name_label: String = "Hole"

## Generator / course-design fields
@export var green_shape: GreenShape = GreenShape.OVAL
@export var green_size: float = 0.7  ## 0 = tiny target, 1 = generous
@export var contour_profile: ContourProfile = ContourProfile.SIDE_SLOPE
## Specs: {kind, role, side, along, size, art, count?}.
## kind=sand|water|tree; role=greenside|landing|carry|edge|island_ring
## tree count = how many canopies to stamp around that role site (default 1).
@export var hazards: Array = []
@export var complexity: float = 0.0  ## 0–1 difficulty composite
@export var archetype: String = ""  ## generator identity (e.g. short_sharp)


func has_bunker() -> bool:
	for h in hazards:
		if str(h.get("kind", "")) == "sand":
			return true
	return false


func has_water() -> bool:
	for h in hazards:
		if str(h.get("kind", "")) == "water":
			return true
	return false


func has_trees() -> bool:
	for h in hazards:
		if str(h.get("kind", "")) == "tree":
			return true
	return false


func tee_yards(set: TeeSet) -> float:
	## Effective tee→green yards for a color set (White = yardage).
	match set:
		TeeSet.BLUE:
			return maxf(yardage + tee_blue_offset_yd, 60.0)
		TeeSet.RED:
			return maxf(yardage + tee_red_offset_yd, 50.0)
		_:
			return maxf(yardage, 50.0)


static func tee_set_label(set: TeeSet) -> String:
	match set:
		TeeSet.BLUE:
			return "Blue"
		TeeSet.RED:
			return "Red"
		_:
			return "White"


## Elevation at local pos (world − green_center). Book heat samples this.
func green_height_at(local: Vector2) -> float:
	var h := -green_slope.dot(local)
	for inf in _green_slope_influences():
		var d: Vector2 = local - inf["pos"]
		var s2: float = inf["sigma"] * inf["sigma"]
		h += float(inf["amp"]) * exp(-d.length_squared() / (2.0 * s2))
	return h


## Downhill pull at local pos (same units as green_slope). Physics samples this live.
func green_slope_at(local: Vector2) -> Vector2:
	var s := green_slope
	for inf in _green_slope_influences():
		var d: Vector2 = local - inf["pos"]
		var s2: float = inf["sigma"] * inf["sigma"]
		var fall := exp(-d.length_squared() / (2.0 * s2))
		# −∇(amp·gaussian) → ball pushed off highs / into lows
		s += d * (float(inf["amp"]) / s2) * fall
	return s


# ponytail: profiled Gaussian bumps; authored mesh if greens get a designer
func _green_slope_influences() -> Array:
	var base_len := green_slope.length()
	if contour_profile == ContourProfile.FLAT or base_len < 0.02:
		return []
	var rx := maxf(green_radius_x, 20.0)
	var ry := maxf(green_radius_y, 20.0)
	var rmin := minf(rx, ry)
	var down := green_slope / base_len
	var across := Vector2(-down.y, down.x)
	match contour_profile:
		ContourProfile.BOWL:
			return _influences_bowl(base_len, rmin)
		ContourProfile.RIDGE:
			return _influences_ridge(base_len, rmin, across)
		ContourProfile.FALSE_FRONT:
			return _influences_false_front(base_len, rx, ry, down, across)
		ContourProfile.BI_TIER:
			return _influences_bi_tier(base_len, rx, ry, down, across)
		_:
			return _influences_side_slope(base_len, rx, ry, down, across)


func _influences_side_slope(base_len: float, rx: float, ry: float, down: Vector2, across: Vector2) -> Array:
	var rmin := minf(rx, ry)
	var out: Array = []
	var sigma_crown := rmin * 0.48
	out.append({
		"pos": -down * ry * 0.32 + across * clampf(pin_offset.dot(across), -rx * 0.4, rx * 0.4) * 0.2,
		"amp": base_len * sigma_crown * 0.7,
		"sigma": sigma_crown,
	})
	var sigma_pin := rmin * 0.36
	out.append({
		"pos": pin_offset * 0.85,
		"amp": -base_len * sigma_pin * 0.55,
		"sigma": sigma_pin,
	})
	var side := across * clampf(pin_offset.dot(across), -rx * 0.55, rx * 0.55)
	if side.length() > 6.0:
		var sigma_side := rmin * 0.42
		out.append({
			"pos": side * 0.75 - down * ry * 0.08,
			"amp": base_len * sigma_side * 0.45,
			"sigma": sigma_side,
		})
	return out


func _influences_bowl(base_len: float, rmin: float) -> Array:
	return [{
		"pos": pin_offset * 0.35,
		"amp": -base_len * rmin * 0.85,
		"sigma": rmin * 0.55,
	}]


func _influences_ridge(base_len: float, rmin: float, across: Vector2) -> Array:
	return [{
		"pos": across * (rmin * 0.15) + pin_offset * 0.2,
		"amp": base_len * rmin * 0.75,
		"sigma": rmin * 0.4,
	}]


func _influences_false_front(
	base_len: float, rx: float, ry: float, _down: Vector2, across: Vector2
) -> Array:
	var rmin := minf(rx, ry)
	var out: Array = []
	# High face short of the hole (toward tee = +Y local).
	out.append({
		"pos": Vector2(0.0, ry * 0.42) + across * clampf(pin_offset.x, -rx * 0.3, rx * 0.3) * 0.3,
		"amp": base_len * rmin * 0.8,
		"sigma": rmin * 0.38,
	})
	out.append({
		"pos": pin_offset * 0.9 - Vector2(0.0, ry * 0.08),
		"amp": -base_len * rmin * 0.4,
		"sigma": rmin * 0.32,
	})
	return out


func _influences_bi_tier(
	base_len: float, rx: float, ry: float, _down: Vector2, across: Vector2
) -> Array:
	var rmin := minf(rx, ry)
	var out: Array = []
	# Back tier high, front tier low — ridge across mid-green.
	out.append({
		"pos": Vector2(0.0, -ry * 0.35) + across * clampf(pin_offset.x, -rx * 0.25, rx * 0.25) * 0.2,
		"amp": base_len * rmin * 0.65,
		"sigma": rmin * 0.42,
	})
	out.append({
		"pos": Vector2(0.0, ry * 0.3),
		"amp": -base_len * rmin * 0.35,
		"sigma": rmin * 0.4,
	})
	out.append({
		"pos": pin_offset * 0.8,
		"amp": -base_len * rmin * 0.25,
		"sigma": rmin * 0.28,
	})
	return out

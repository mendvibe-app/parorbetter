class_name HoleData
extends Resource

## Per-hole layout + difficulty. Comments note how the course builder uses each field.

enum HazardBias { NONE, LEFT, RIGHT }
enum SuggestedShape { STRAIGHT, DRAW, FADE }
enum LayoutStyle { STANDARD, DOGLEG_LEFT, DOGLEG_RIGHT, ISLAND, CHUTE, BI_TIER }
enum GreenShape { OVAL, KIDNEY, TIERED, L_SHAPED, PENINSULA, COMPLEX }
enum CourseTheme { PARKLAND, LINKS, DESERT }

@export var hole_number: int = 1
@export var par: int = 4
@export var yardage: float = 400.0  ## tee→green yards (drives layout length)
@export var fairway_width: float = 140.0
@export var green_radius_x: float = 60.0
@export var green_radius_y: float = 60.0
@export var pin_offset: Vector2 = Vector2.ZERO  ## from green center
@export var tee_offset_x: float = 0.0
@export var fairway_bend: float = 0.0  ## lateral dogleg at mid fairway (px)
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
@export var has_bunker: bool = false
@export var has_water: bool = false
@export var complexity: float = 0.0  ## 0–1 difficulty composite
@export var archetype: String = ""  ## generator identity (e.g. short_sharp)


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


# ponytail: 2–4 procedural bumps from pin/radii; authored mesh if greens get a designer
func _green_slope_influences() -> Array:
	var base_len := green_slope.length()
	if base_len < 0.02:
		return []
	var rx := maxf(green_radius_x, 20.0)
	var ry := maxf(green_radius_y, 20.0)
	var rmin := minf(rx, ry)
	var down := green_slope / base_len
	var across := Vector2(-down.y, down.x)
	var out: Array = []
	# Uphill crown — break softens above the hole, steepens below
	var sigma_crown := rmin * 0.48
	out.append({
		"pos": -down * ry * 0.32 + across * clampf(pin_offset.dot(across), -rx * 0.4, rx * 0.4) * 0.2,
		"amp": base_len * sigma_crown * 0.7,
		"sigma": sigma_crown,
	})
	# Pin-side fall — local break near the cup
	var sigma_pin := rmin * 0.36
	out.append({
		"pos": pin_offset * 0.85,
		"amp": -base_len * sigma_pin * 0.55,
		"sigma": sigma_pin,
	})
	# Side shelf when pin is offline
	var side := across * clampf(pin_offset.dot(across), -rx * 0.55, rx * 0.55)
	if side.length() > 6.0:
		var sigma_side := rmin * 0.42
		out.append({
			"pos": side * 0.75 - down * ry * 0.08,
			"amp": base_len * sigma_side * 0.45,
			"sigma": sigma_side,
		})
	return out

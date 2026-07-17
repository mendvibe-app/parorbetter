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
@export var distance_yards: float = 380.0
@export var fairway_width: float = 140.0
@export var green_radius: float = 48.0  ## legacy / average
@export var green_radius_x: float = 48.0
@export var green_radius_y: float = 48.0
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
@export var hazard_count: int = 0
@export var has_bunker: bool = false
@export var has_water: bool = false
@export var complexity: float = 0.0  ## 0–1 difficulty composite
@export var theme: CourseTheme = CourseTheme.PARKLAND


func shape_label() -> String:
	match suggested_shape:
		SuggestedShape.DRAW:
			return "Draw"
		SuggestedShape.FADE:
			return "Fade"
		_:
			return "Straight"


func bias_label() -> String:
	match hazard_bias:
		HazardBias.LEFT:
			return "Left"
		HazardBias.RIGHT:
			return "Right"
		_:
			return "None"


func green_shape_label() -> String:
	match green_shape:
		GreenShape.KIDNEY:
			return "Kidney"
		GreenShape.TIERED:
			return "Tiered"
		GreenShape.L_SHAPED:
			return "L-shaped"
		GreenShape.PENINSULA:
			return "Peninsula"
		GreenShape.COMPLEX:
			return "Complex"
		_:
			return "Oval"

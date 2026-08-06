class_name HoleController
extends Node2D

signal request_game_over
signal request_next_hole

const GREEN_Y := -80.0
const AIM_NUDGE_PX := 14.0
## Catch / draw radius. Cup ≈ 2.4× putt ball (BALL_R_PUTT 1.0) — real hole ≈ 2.5× ball.
const CUP_RADIUS := 2.4
## Course pin height in px (readable from fairway; not survey-true ~7 ft).
const PIN_FLAG_H_PX := 32.0
## Full-shot "up and in" camera — fractions of pre-shot / corridor base (not absolute).
## Aim framing got tighter (corridor); absolute 0.55 launch was zooming *out* on hit.
const FLIGHT_LAUNCH_FRAC := 0.90  ## mild open from aim at launch
const FLIGHT_APEX_FRAC := 0.95
const FLIGHT_LAND_FRAC := 1.28  ## ends tighter than aim ("up and in")
const FLIGHT_ZOOM_IN_START := 0.55  ## air_progress when the tight zoom begins
const FLIGHT_LOOK_LEAD_WIDE := 120.0
const FLIGHT_LOOK_LEAD_TIGHT := 45.0
## Putt roll camera: hold stroke-start frame so the ball rolls through a stable shot
## (no live zoom-in / tight chase as it nears the cup — that felt jarring on short putts).
const PUTT_ROLL_LOOK_LERP := 0.07
const PUTT_ROLL_BALL_WEIGHT := 0.15  ## soft drift toward ball from locked mid-frame
const PUTT_ROLL_ZOOM_LERP := 0.10

## Pinch-to-zoom (aim/green-book only) — multiplies _desired_camera_zoom(), then
## the result is safety-clamped so a pinch can't push the camera past a readable range.
const PINCH_MULT_MIN := 0.6
const PINCH_MULT_MAX := 1.5
const PINCH_ABS_ZOOM_MIN := 0.5
const PINCH_ABS_ZOOM_MAX := 8.0
const PINCH_MIN_SPAN_PX := 40.0  ## floor on finger-span distance to avoid divide-by-near-zero spikes
const MAGNIFY_IDLE_RELEASE_MS := 400  ## trackpad magnify gesture has no discrete release; time it out

const TEX_ROUGH := preload("res://assets/terrain/rough_tile_a.png")
const TEX_ROUGH_DARK := preload("res://assets/terrain/rough_tile_b.png")
const TEX_FAIRWAY := preload("res://assets/terrain/fairway_tile_a.png")
const TEX_TEE := preload("res://assets/terrain/tee_tile.png")
const TEX_WATER := preload("res://assets/terrain/water_tile.png")
const TEX_WATER_CREEK := preload("res://assets/hazards/water_creek.png")
const TEX_WATER_POND := preload("res://assets/hazards/water_pond.png")
const TEX_CUP := preload("res://assets/greens/cup.png")
const TEX_FOG := preload("res://assets/background/fog_overlay.png")
## Preload so global class_name cache isn't required before first import.
const CoursePinFlagScr := preload("res://scripts/course/course_pin_flag.gd")
const GREEN_SHAPE_TEXTURES := {
	HoleData.GreenShape.OVAL: preload("res://assets/greens/green_oval.png"),
	HoleData.GreenShape.KIDNEY: preload("res://assets/greens/green_kidney.png"),
	HoleData.GreenShape.TIERED: preload("res://assets/greens/green_tiered.png"),
	HoleData.GreenShape.L_SHAPED: preload("res://assets/greens/green_long.png"),
	HoleData.GreenShape.PENINSULA: preload("res://assets/greens/green_island.png"),
	HoleData.GreenShape.COMPLEX: preload("res://assets/greens/green_tiered.png"),
}
const GREEN_DEFAULT := preload("res://assets/greens/green_oval.png")
const BUNKER_TEXTURES := [
	preload("res://assets/hazards/bunker_blob.png"),
	preload("res://assets/hazards/bunker_crescent.png"),
	preload("res://assets/hazards/bunker_cluster.png"),
]
const TREE_TEXTURES := [
	preload("res://assets/background/tree_round.png"),
	preload("res://assets/background/tree_pine.png"),
	preload("res://assets/background/tree_cluster.png"),
	preload("res://assets/background/tree_oak.png"),
	preload("res://assets/background/tree_airy.png"),
	preload("res://assets/background/tree_dark.png"),
	preload("res://assets/background/tree_broad.png"),
	preload("res://assets/background/tree_tall.png"),
]
## Clear height (same units as ball._height peak). Ball carries if _height >= this in flight.
## Index matches TREE_TEXTURES: round, pine, cluster, oak, airy, dark, broad, tall.
## Short ~22–28 (mid-iron/wedge); pine rare full-wedge; tall ~42 hard wall.
const TREE_CANOPY_H: Array[float] = [24.0, 38.0, 28.0, 32.0, 22.0, 30.0, 26.0, 42.0]
## Portrait course framing: dark rough belt just outside fairway + tree line on it.
## Camera aims to keep this corridor ~half of screen width (not oceans of mid-rough).
const SIDE_BELT_W := 58.0
const CORRIDOR_SCREEN_FRAC := 0.50  ## fairway + belts ≈ this fraction of viewport width
var hole: HoleData
var strokes: int = 0
var ball_in_flight: bool = false
var hole_complete: bool = false
var _cup_pos: Vector2 = Vector2.ZERO
var _green_center: Vector2 = Vector2.ZERO
var _tee_pos: Vector2 = Vector2(540, 860.0)  ## active teeing ground (ball start)
var _tee_back_pos: Vector2 = Vector2(540, 860.0)  ## Blue (longest) — fairway end
var _tee_pads: Array = []  ## {set, pos, rect} for all three colors
var _active_tee: HoleData.TeeSet = HoleData.TeeSet.WHITE
var _practice_green_pos: Vector2 = Vector2.ZERO
var _fairway_half: float = 70.0
var _flight_zoom_base: float = 1.2  ## captured at full-shot start; flight fracs scale from this
var _bunkers: Array = []  ## {c, r, sprite, img} — settle lie via paint alpha
var _trees: Array = []  ## {c: Vector2, r: float} — collision + Trees lie
var _green_book: Node2D  ## aim-only yardage-book overlay (height heat)
var _pin_flag: Node2D  ## CoursePinFlag — hidden while putting (pin out)
var _green_sprite: Sprite2D
var _green_img: Image  ## cached for shape-aware Green lie (silhouette alpha)

var _aiming: bool = false
var _selecting_club: bool = false
var _power_previewing: bool = false
var _aim_dragging: bool = false
var _active_touches: Dictionary = {}  ## touch index -> last screen position, aim phase only
var _pinch_idx_a: int = -1
var _pinch_idx_b: int = -1
var _pinch_start_dist: float = 0.0
var _pinch_start_mult: float = 1.0
var _user_zoom_mult: float = 1.0  ## manual pinch override on top of the auto-framed zoom
var _magnify_last_ms: int = -1  ## last InputEventMagnifyGesture time; drives idle-release
var _change_club_btn: BaseButton
var _punch_btn: Button
## Trees only — low flight under canopy (apex carry + more roll).
var _punch_mode: bool = false
## Practice reps left before the real swing (set on Confirm Aim from GameState).
var _practice_reps_left: int = 0
## True when opening club select from aim — keep bearing, refit distance for new club.
var _preserve_aim_line: bool = false
var _aim_target: Vector2 = Vector2.ZERO
var _aim_radius_yd: float = 22.0
var _aim_radius_base_yd: float = 22.0
var _aim_lock_yards: float = 160.0
var _chosen_club: Dictionary = {}
var _aim_cone: Polygon2D
var _aim_cone_edge: Line2D
var _aim_cone_edge_r: Line2D
var _pin_ref_line: Line2D
var _aim_circle: Line2D
var _wind_bias: Line2D
var _wind_flag: WindFlag
var _last_report: ShotReport
var _last_result: ShotResult
var _club_select: ClubSelect
var scorecard: ScoreCard
## Locked putt framing for the roll (set at stroke start, cleared on settle).
var _putt_cam_active: bool = false
var _putt_cam_zoom: Vector2 = Vector2.ONE
var _putt_cam_look: Vector2 = Vector2.ZERO

@onready var course_root: Node2D = $Course
@onready var ball: GolfBall = $Ball
@onready var camera: Camera2D = $Camera2D
@onready var flash_rect: ColorRect = $UILayer/Flash
@onready var birdie_label: Label = $UILayer/BirdieBanner
@onready var shot_routine: ShotRoutine = $UILayer/ShotPanel
@onready var hud: Control = $UILayer/HUD
@onready var feedback: Label = $UILayer/Feedback
@onready var shot_result_panel: Control = $UILayer/ShotResultPanel
@onready var confirm_aim_btn: BaseButton = $UILayer/ConfirmAimButton
@onready var wind_banner: Label = $UILayer/WindBanner
@onready var ui_layer: CanvasLayer = $UILayer
const _HOLE_MAP_SCR := preload("res://scripts/ui/hole_map.gd")
const TEX_CLUB_BAG: Texture2D = preload("res://assets/ui/ui_club_bag.png")
const CHANGE_CLUB_ICON := 88.0
var _hole_map: Control  ## HoleMap instance


func _ready() -> void:
	ball.settled.connect(_on_ball_settled)
	ball.entered_hazard.connect(_on_hazard)
	ball.holed_out.connect(_on_holed_out)
	ball.perfect_flash.connect(_on_perfect_flash)
	ball.ground_lie_at = func(p: Vector2) -> String: return _classify_lie(p)
	shot_routine.shot_ready.connect(_on_shot_ready)
	if shot_routine.has_signal("pure_strike"):
		shot_routine.pure_strike.connect(_on_pure_strike)
	birdie_label.visible = false
	flash_rect.modulate.a = 0.0
	GameState.run_ended.connect(_on_run_ended)
	_setup_aim_visuals()
	_setup_club_select()
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
		confirm_aim_btn.pressed.connect(_confirm_aim)
	shot_routine.back_requested.connect(_on_back_requested)
	_setup_change_club_btn()
	_setup_punch_btn()
	_setup_scorecard()
	_setup_hole_map()
	# Bag icon above map in tree (map was covering it); club select stays topmost modal.
	if _change_club_btn:
		ui_layer.move_child(_change_club_btn, -1)
	if _punch_btn:
		ui_layer.move_child(_punch_btn, -1)
	if scorecard:
		ui_layer.move_child(scorecard, -1)
	ui_layer.move_child(_club_select, -1)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _setup_hole_map() -> void:
	## Cart-GPS overview under Debug — whole hole + ball.
	_hole_map = _HOLE_MAP_SCR.new()
	_hole_map.name = "HoleMap"
	ui_layer.add_child(_hole_map)
	_hole_map.park_under_debug(get_viewport())


func _apply_safe_area() -> void:
	UiScale.apply_hole_safe_area(
		hud, feedback, _wind_flag, shot_routine, confirm_aim_btn, shot_result_panel
	)
	# ShotRoutine may compact pad chrome (meter hidden on scored shots) after safe-area defaults.
	if shot_routine and shot_routine.visible and shot_routine.has_method("layout_shot_chrome"):
		shot_routine.layout_shot_chrome()
	_park_change_club_btn()
	if wind_banner:
		wind_banner.visible = false
	if _hole_map:
		_hole_map.park_under_debug(get_viewport())


func _setup_club_select() -> void:
	_club_select = ClubSelect.new()
	_club_select.name = "ClubSelect"
	ui_layer.add_child(_club_select)
	# Modal: last child = on top of ShotPanel / aim chrome so drags aren't stolen.
	_club_select.club_chosen.connect(_on_club_chosen)


func _setup_aim_visuals() -> void:
	_pin_ref_line = Line2D.new()
	_pin_ref_line.width = 2.0
	_pin_ref_line.default_color = Color(1.0, 1.0, 1.0, 0.55)
	_pin_ref_line.z_index = 4
	_pin_ref_line.visible = false
	# Putt reuses this as a fading aim line; full shots use solid cup-ref.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.55),
		Color(1.0, 1.0, 1.0, 0.22),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_pin_ref_line.gradient = fade
	add_child(_pin_ref_line)

	# Directional wedge (not a laser to an exact landing XY).
	_aim_cone = Polygon2D.new()
	_aim_cone.z_index = 5
	_aim_cone.visible = false
	add_child(_aim_cone)

	_aim_cone_edge = Line2D.new()
	_aim_cone_edge.width = 2.0
	_aim_cone_edge.default_color = Color(1.0, 0.92, 0.4, 0.35)
	_aim_cone_edge.z_index = 5
	_aim_cone_edge.visible = false
	add_child(_aim_cone_edge)

	# Right flank drawn separately from the left (_aim_cone_edge) — the two flanks
	# each end tangent to the landing circle, and must stay unconnected to each
	# other so no straight line is ever drawn across the circle's face.
	_aim_cone_edge_r = Line2D.new()
	_aim_cone_edge_r.width = 2.0
	_aim_cone_edge_r.default_color = Color(1.0, 0.92, 0.4, 0.35)
	_aim_cone_edge_r.z_index = 5
	_aim_cone_edge_r.visible = false
	add_child(_aim_cone_edge_r)

	_aim_circle = Line2D.new()
	_aim_circle.width = 3.0
	_aim_circle.default_color = Color(1.0, 0.92, 0.35, 0.85)
	_aim_circle.z_index = 5
	_aim_circle.visible = false
	add_child(_aim_circle)

	_wind_bias = Line2D.new()
	_wind_bias.width = 4.0
	_wind_bias.default_color = Color(0.55, 0.85, 1.0, 0.9)
	_wind_bias.z_index = 6
	_wind_bias.visible = false
	add_child(_wind_bias)

	_wind_flag = WindFlag.new()
	_wind_flag.name = "WindFlag"
	_wind_flag.visible = false
	_wind_flag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wind_flag.anchor_left = 0.5
	_wind_flag.anchor_right = 0.5
	_wind_flag.offset_left = -48.0
	_wind_flag.offset_right = 48.0
	_wind_flag.offset_top = UiScale.WIND_TOP
	_wind_flag.offset_bottom = UiScale.WIND_TOP + 128.0
	ui_layer.add_child(_wind_flag)
	if wind_banner:
		wind_banner.visible = false
		wind_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE


func load_hole(hole_index: int) -> void:
	if scorecard:
		if GameState.is_stroke_play():
			if hole_index <= 1:
				scorecard.show_for_stroke_play()
			else:
				scorecard.visible = true
				if scorecard._tab_btn:
					scorecard._tab_btn.visible = true
		else:
			scorecard.hide_card()
	GameState.exit_range_mode()
	GameState.exit_green_mode()
	_end_aim_phase()
	hole = GameState.get_hole(hole_index)
	GameState.begin_hole(hole_index)
	strokes = 0
	GameState.strokes_this_hole = 0
	hole_complete = false
	ball_in_flight = false
	_clear_putt_camera_lock()
	_build_course()
	ball.reset_at(_tee_pos, "Tee")
	camera.global_position = Vector2(_tee_pos.x, _tee_pos.y - 120)
	if not camera.is_current():
		camera.make_current()
	_update_hud()
	_start_shot_ui()


func load_range() -> void:
	## Flat fairway tee — swing practice, no aim phase, infinite reset.
	if scorecard:
		scorecard.hide_card()
	_end_aim_phase()
	GameState.enter_range_mode()
	hole = _make_range_hole()
	strokes = 0
	hole_complete = false
	ball_in_flight = false
	_clear_putt_camera_lock()
	_chosen_club.clear()
	_build_course()
	ball.reset_at(_tee_pos, "Tee")
	camera.global_position = Vector2(_tee_pos.x, _tee_pos.y - 120)
	if not camera.is_current():
		camera.make_current()
	_update_hud()
	feedback.text = "RANGE — pick a club, swing. Ball resets to tee."
	feedback.modulate = Color(0.85, 0.95, 0.75)
	_start_shot_ui()


func load_practice_green() -> void:
	## Putting green — aim + putt loop, infinite reset to practice spot.
	if scorecard:
		scorecard.hide_card()
	_end_aim_phase()
	GameState.enter_green_mode()
	hole = _make_practice_green_hole()
	strokes = 0
	hole_complete = false
	ball_in_flight = false
	_clear_putt_camera_lock()
	_chosen_club.clear()
	_build_course()
	_practice_green_pos = _cup_pos + Vector2(0.0, BallPhysics.yards_to_pixels(12.0))
	ball.reset_at(_practice_green_pos, "Green")
	camera.global_position = Vector2(_practice_green_pos.x, _practice_green_pos.y - 40)
	camera.zoom = Vector2(2.8, 2.8)
	if not camera.is_current():
		camera.make_current()
	_update_hud()
	feedback.text = "GREEN — aim & putt. Ball resets after each."
	feedback.modulate = Color(0.85, 0.95, 0.75)
	_start_shot_ui()


func _make_range_hole() -> HoleData:
	var d := HoleData.new()
	d.hole_number = 0
	d.par = 4
	d.fairway_width = 240.0
	d.green_radius_x = 38.0
	d.green_radius_y = 38.0
	d.pin_offset = Vector2.ZERO
	d.tee_offset_x = 0.0
	d.fairway_bend = 0.0
	d.wind_vector = Vector2.ZERO
	d.green_slope = Vector2.ZERO
	d.timing_window_scale = 1.0
	d.hazards = []
	d.hazard_bias = HoleData.HazardBias.NONE
	d.suggested_shape = HoleData.SuggestedShape.STRAIGHT
	d.name_label = "RANGE"
	d.archetype = "range"
	d.contour_profile = HoleData.ContourProfile.FLAT
	d.yardage = 420.0
	return d


func _make_practice_green_hole() -> HoleData:
	var d := HoleData.new()
	d.hole_number = 0
	d.par = 3
	d.fairway_width = 160.0
	d.green_radius_x = 38.0
	d.green_radius_y = 38.0
	d.pin_offset = Vector2.ZERO
	d.tee_offset_x = 0.0
	d.fairway_bend = 0.0
	d.wind_vector = Vector2.ZERO
	d.green_slope = Vector2(0.28, 0.0)
	d.timing_window_scale = 1.0
	d.hazards = []
	d.hazard_bias = HoleData.HazardBias.NONE
	d.suggested_shape = HoleData.SuggestedShape.STRAIGHT
	d.name_label = "GREEN"
	d.archetype = "practice_green"
	d.contour_profile = HoleData.ContourProfile.SIDE_SLOPE
	d.yardage = 100.0
	return d


func _build_course() -> void:
	for c in course_root.get_children():
		c.queue_free()
	_pin_flag = null
	_green_sprite = null
	_green_img = null
	if _green_book:
		_green_book.queue_free()
		_green_book = null
	_bunkers.clear()
	_trees.clear()
	_tee_pads.clear()

	var fairway_w: float = hole.fairway_width
	if GameState.debug_fairway_scale != null:
		fairway_w *= float(GameState.debug_fairway_scale)
	_fairway_half = fairway_w * 0.5

	var adapt_bias := GameState.effective_hazard_bias(hole)
	var wind := hole.wind_vector
	if GameState.debug_wind_scale != null:
		wind *= float(GameState.debug_wind_scale)
	wind += GameState.wind_adaptation_nudge()

	course_root.set_meta("wind", wind)
	course_root.set_meta("slope", hole.green_slope)

	_green_center = Vector2(540.0, GREEN_Y)
	_cup_pos = _green_center + hole.pin_offset
	_setup_tee_positions()
	var course_len := (_tee_back_pos.y - GREEN_Y) + 180.0

	# Rough apron (mid rough — camera + side belts keep this from dominating the frame)
	_add_rect(course_root, Rect2(0, GREEN_Y - 140, 1080, course_len + 220), Color(0.92, 0.98, 0.92), "", TEX_ROUGH, 340.0)

	# Bent / shaped fairway
	_add_bent_fairway(fairway_w)

	# Deep-rough belts just outside fairway (follow bend) — hole edge, not empty field
	_add_side_belts()

	# Green sprite (variant per layout) + detection area
	_add_green(hole.green_radius_x + 14.0, hole.green_radius_y + 14.0)

	_add_circle(course_root, _cup_pos, CUP_RADIUS, Color(0, 0, 0, 0), "cup")
	var cup_spr := Sprite2D.new()
	cup_spr.texture = TEX_CUP
	cup_spr.position = _cup_pos
	cup_spr.scale = Vector2.ONE * ((CUP_RADIUS * 2.0) / float(TEX_CUP.get_width()))
	cup_spr.z_index = 2
	course_root.add_child(cup_spr)

	# Same cloth language as HUD WindFlag; foot planted on the cup.
	var flag_node: Node2D = CoursePinFlagScr.new()
	flag_node.name = "CoursePinFlag"
	flag_node.position = _cup_pos
	flag_node.set("height_px", PIN_FLAG_H_PX)
	course_root.add_child(flag_node)
	_pin_flag = flag_node
	_sync_pin_flag_visible()
	_update_pin_flag_wind()

	_place_hazards(adapt_bias)

	_add_rect(course_root, Rect2(-80, GREEN_Y - 140, 70, course_len + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_add_rect(course_root, Rect2(1090, GREEN_Y - 140, 70, course_len + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_add_tee_boxes()
	_add_fog_band()

	_build_green_book()
	_refresh_hole_map()


func _setup_tee_positions() -> void:
	## Three tees: White = hole.yardage; Blue longer; Red shorter. Slight x stagger for read.
	var cx := 540.0 + hole.tee_offset_x
	var y_blue := GREEN_Y + BallPhysics.yards_to_pixels(hole.tee_yards(HoleData.TeeSet.BLUE))
	var y_white := GREEN_Y + BallPhysics.yards_to_pixels(hole.tee_yards(HoleData.TeeSet.WHITE))
	var y_red := GREEN_Y + BallPhysics.yards_to_pixels(hole.tee_yards(HoleData.TeeSet.RED))
	# Ensure order Blue (back) > White > Red (forward) even if offsets inverted
	y_blue = maxf(y_blue, y_white + BallPhysics.yards_to_pixels(6.0))
	y_red = minf(y_red, y_white - BallPhysics.yards_to_pixels(6.0))
	_tee_back_pos = Vector2(cx, y_blue)
	var pads := [
		{"set": HoleData.TeeSet.BLUE, "pos": Vector2(cx - 16.0, y_blue)},
		{"set": HoleData.TeeSet.WHITE, "pos": Vector2(cx, y_white)},
		{"set": HoleData.TeeSet.RED, "pos": Vector2(cx + 16.0, y_red)},
	]
	_active_tee = GameState.active_tee_set_for_hole(hole.hole_number)
	for p in pads:
		_tee_pads.append(p)
		if p["set"] == _active_tee:
			_tee_pos = p["pos"]


func _add_bent_fairway(width: float) -> void:
	## Trapezoid / dogleg strip from tee to green.
	## Stop at the green apron — old top (GREEN_Y - 20) ran fairway texture
	## through the putting surface as a rectangular mismatched patch.
	## Fairway reaches Blue (back) tee so all three pads sit on the corridor.
	var half := width * 0.5
	var tee_y := _tee_back_pos.y
	var top_y := GREEN_Y + maxf(hole.green_radius_y, 36.0) + 6.0
	# Corner vertex: smooth-curve midpoint by default (matches the old fixed
	# 0.45/0.55 y-weight + full-bend x exactly). Sharpened Dogleg Corners epic
	# moves this to hole.corner_position when active — see _use_sharp_dogleg().
	var corner_along := 0.5
	var mid_y := tee_y * 0.45 + GREEN_Y * 0.55
	if _use_sharp_dogleg():
		corner_along = clampf(hole.corner_position, 0.05, 0.95)
		mid_y = _y_at(corner_along)
	var top := Vector2(_fairway_center_x(0.0), top_y)
	var mid := Vector2(_fairway_center_x(corner_along), mid_y)
	var bot := Vector2(_tee_back_pos.x, tee_y - 20.0)
	var poly := Polygon2D.new()
	poly.color = Color(1, 1, 1)
	poly.texture = TEX_FAIRWAY
	poly.texture_scale = Vector2.ONE * (float(TEX_FAIRWAY.get_width()) / 300.0)
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var pts := PackedVector2Array()
	pts.append(bot + Vector2(-half, 0))
	pts.append(mid + Vector2(-half * 0.85, 0))
	# Phase 1 fairway collar (Fairway True Collar epic): OVAL/KIDNEY greens taper
	# the last stretch into the green's actual silhouette instead of a flat
	# cutoff line. TIERED / L_SHAPED / COMPLEX intentionally keep the old flat
	# cutoff for now — Phase 2 extends collar coverage once this is validated in
	# playtesting. PENINSULA is permanently excluded: its "fairway" edge is
	# water, not rough, so collaring it isn't meaningful.
	if hole.green_shape == HoleData.GreenShape.OVAL or hole.green_shape == HoleData.GreenShape.KIDNEY:
		pts.append_array(_collar_arc_points(half * 0.7))
	else:
		pts.append(top + Vector2(-half * 0.7, 0))
		pts.append(top + Vector2(half * 0.7, 0))
	pts.append(mid + Vector2(half * 0.85, 0))
	pts.append(bot + Vector2(half, 0))
	poly.polygon = pts
	course_root.add_child(poly)
	var area := Area2D.new()
	area.collision_layer = 2
	var cs := CollisionPolygon2D.new()
	cs.polygon = poly.polygon
	area.add_child(cs)
	area.add_to_group("fairway")
	area.monitoring = false
	area.monitorable = true
	course_root.add_child(area)


func _collar_arc_points(edge_half_width: float) -> PackedVector2Array:
	## Traces the green's south-facing (fairway-approach) silhouette from the left
	## flank to the right, replacing the flat top edge for OVAL/KIDNEY greens.
	## Sampled around the true green center (not the bent fairway "top" point) so
	## it matches the rendered green sprite regardless of dogleg bend/corner.
	var theta_edge := _theta_for_collar_x(edge_half_width)
	var n := 9
	var out := PackedVector2Array()
	for i in n:
		var t := float(i) / float(n - 1)
		var theta := lerpf(PI - theta_edge, theta_edge, t)
		var r := _green_boundary_radius(theta)
		out.append(_green_center + Vector2(cos(theta), sin(theta)) * r)
	return out


func _theta_for_collar_x(target_x: float) -> float:
	## Bisects the polar angle (front-right quadrant, 0..PI/2) whose green-boundary
	## point has this local x offset from the green center. Monotonic in that
	## quadrant for both OVAL and KIDNEY — the kidney indent sits on the back side
	## (see _green_boundary_radius) so it never affects this search.
	var rx := (hole.green_radius_x + 14.0) / 0.85
	var clamped_x := minf(target_x, rx * 0.96)
	var lo := 0.0
	var hi := PI * 0.5
	for _i in 24:
		var mid_theta := (lo + hi) * 0.5
		var x := _green_boundary_radius(mid_theta) * cos(mid_theta)
		if x > clamped_x:
			lo = mid_theta
		else:
			hi = mid_theta
	return (lo + hi) * 0.5


func _green_boundary_radius(angle: float) -> float:
	## Distance from the green center to the green's rendered silhouette edge at
	## `angle` (standard math radians; angle = PI/2 faces south / the fairway
	## approach, since screen +y is south). Effective radii include the sprite's
	## fringe padding (see _add_green's surface_frac) so the collar traces the
	## actual drawn edge, not just the smaller putting-surface detection radius.
	## OVAL is an exact ellipse. KIDNEY approximates the same ellipse with a
	## shallow indent on the back (non-approach) side — the current kidney art is
	## a placeholder oval with no real concave edge, so keeping the indent off the
	## collared front arc avoids the fairway polygon undershooting the rendered
	## edge and leaving a seam; revisit once kidney art gets a true indented
	## silhouette. Phase 1 only — see _add_bent_fairway for shapes still flat-cut.
	var rx := (hole.green_radius_x + 14.0) / 0.85
	var ry := (hole.green_radius_y + 14.0) / 0.85
	var base := (rx * ry) / sqrt(pow(ry * cos(angle), 2.0) + pow(rx * sin(angle), 2.0))
	if hole.green_shape != HoleData.GreenShape.KIDNEY:
		return base
	var notch_d := absf(angle_difference(angle, -PI * 0.5))
	var notch := 1.0 - 0.18 * clampf(1.0 - notch_d / (PI * 0.4), 0.0, 1.0)
	return base * notch


func _add_green(rx: float, ry: float) -> void:
	var tex: Texture2D = _green_texture_for_hole()
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = _green_center
	# Scale so the putting surface (inside fringe / island shoreline) matches the
	# detection ellipse. Island art spends ~38% of its span on beach + water ring.
	var is_island := (
		hole.green_shape == HoleData.GreenShape.PENINSULA
		or hole.layout == HoleData.LayoutStyle.ISLAND
	)
	var surface_frac := 0.62 if is_island else 0.85
	spr.scale = Vector2(
		rx * 2.0 / surface_frac / float(tex.get_width()),
		ry * 2.0 / surface_frac / float(tex.get_height())
	)
	spr.z_index = 1
	course_root.add_child(spr)
	_green_sprite = spr
	_green_img = tex.get_image()
	var area := Area2D.new()
	area.position = _green_center
	area.collision_layer = 2
	var cs := CollisionShape2D.new()
	# Approximate green with circle of average radius for detection
	var circ := CircleShape2D.new()
	circ.radius = (rx + ry) * 0.5
	cs.shape = circ
	area.add_child(cs)
	area.add_to_group("green")
	area.monitoring = false
	area.monitorable = true
	course_root.add_child(area)


func _green_texture_for_hole() -> Texture2D:
	return GREEN_SHAPE_TEXTURES.get(hole.green_shape, GREEN_DEFAULT)


func _y_at(frac: float) -> float:
	## 0 = green, 1 = back (Blue) tee — full corridor length.
	return lerpf(GREEN_Y, _tee_back_pos.y, frac)


func _fairway_center_at(along: float) -> Vector2:
	## along 0 = green end, 1 = tee. Smooth 3-point curve normally; two-segment
	## elbow blended by corner_tightness in sharp-dogleg mode — see
	## _use_sharp_dogleg() / _fairway_center_x(). All fairway-relative placement
	## (hazards, carries, lie classification) should read through this function
	## rather than re-deriving fairway x, so it stays correct for both modes.
	return Vector2(_fairway_center_x(along), _y_at(along))


func _use_sharp_dogleg() -> bool:
	## Sharpened dogleg corners — live for dogleg layouts.
	return GameState.sharp_dogleg_enabled and (
		hole.layout == HoleData.LayoutStyle.DOGLEG_LEFT
		or hole.layout == HoleData.LayoutStyle.DOGLEG_RIGHT
	)


func _fairway_center_x(along: float) -> float:
	var smooth_x := _smooth_fairway_x(along)
	if not _use_sharp_dogleg():
		return smooth_x
	var tightness := clampf(hole.corner_tightness, 0.0, 1.0)
	return lerpf(smooth_x, _elbow_fairway_x(along), tightness)


func _smooth_fairway_x(along: float) -> float:
	## Original 3-point (top/mid/bot) smooth-bend curve. Still the STANDARD /
	## non-dogleg path, and the corner_tightness=0 end of the sharp-dogleg blend.
	var top_x := 540.0 + hole.fairway_bend * 0.35
	var mid_x := 540.0 + hole.fairway_bend
	var bot_x := _tee_back_pos.x
	if along < 0.5:
		return lerpf(top_x, mid_x, along * 2.0)
	return lerpf(mid_x, bot_x, (along - 0.5) * 2.0)


func _elbow_fairway_x(along: float) -> float:
	## Two straight segments meeting at corner_position — the corner_tightness=1
	## end of the sharp-dogleg blend (Sharpened Dogleg Corners epic).
	var top_x := 540.0 + hole.fairway_bend * 0.35
	var corner_x := 540.0 + hole.fairway_bend
	var bot_x := _tee_back_pos.x
	var cp := clampf(hole.corner_position, 0.05, 0.95)
	if along < cp:
		return lerpf(top_x, corner_x, along / cp)
	return lerpf(corner_x, bot_x, (along - cp) / (1.0 - cp))


## Pad outside green silhouette before hazard radius is applied (must match _clears_green).
const GREEN_HAZARD_PAD := 14.0
const GREEN_HAZARD_CLEAR_EXTRA := 8.0


func _clears_green(center: Vector2, radius: float) -> bool:
	var rx := hole.green_radius_x + GREEN_HAZARD_PAD + radius + GREEN_HAZARD_CLEAR_EXTRA
	var ry := hole.green_radius_y + GREEN_HAZARD_PAD + radius + GREEN_HAZARD_CLEAR_EXTRA
	var dx := (center.x - _green_center.x) / maxf(rx, 1.0)
	var dy := (center.y - _green_center.y) / maxf(ry, 1.0)
	return dx * dx + dy * dy > 1.0


## Trees must not sit in bunkers (pad keeps canopy edge off sand lip).
const BUNKER_TREE_PAD := 6.0
## Sand Area2D tighter than visual bbox; paint alpha is the true Sand gate.
const SAND_COLLISION_FRAC := 0.6


func _clears_bunkers(center: Vector2, radius: float) -> bool:
	for b in _bunkers:
		var need := float(b["r"]) + radius + BUNKER_TREE_PAD
		if center.distance_to(b["c"]) < need:
			return false
	return true


func _place_hazards(adapt_bias: HoleData.HazardBias) -> void:
	for spec in hole.hazards:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var role := str(spec.get("role", ""))
		var kind := str(spec.get("kind", ""))
		var side := int(spec.get("side", 0))
		if side != 0:
			if adapt_bias == HoleData.HazardBias.LEFT:
				side = -1
			elif adapt_bias == HoleData.HazardBias.RIGHT:
				side = 1
		var along := float(spec.get("along", 0.5))
		var size := float(spec.get("size", 40.0))
		var art := int(spec.get("art", 0))
		match role:
			HoleData.ROLE_ISLAND_RING:
				_place_island_ring()
			HoleData.ROLE_GREENSIDE:
				if kind == "tree":
					_place_tree_group(role, side if side != 0 else 1, along, size, art, int(spec.get("count", 1)))
				elif kind == "sand":
					# Never silent-drop: push outward until clear, then place.
					var c := _greenside_center(side if side != 0 else 1, size)
					_add_bunker(c, size, art if art > 0 else 1)
			HoleData.ROLE_LANDING:
				if kind == "tree":
					_place_tree_group(role, side if side != 0 else 1, along, size, art, int(spec.get("count", 1)))
				else:
					var fc := _fairway_center_at(along)
					var c2 := Vector2(fc.x + float(side if side != 0 else 1) * (_fairway_half + size * 0.35), fc.y)
					if kind == "sand" and _clears_green(c2, size):
						_add_bunker(c2, size, art)
			HoleData.ROLE_CARRY:
				if kind == "water":
					_place_carry_creek(along, size)
			HoleData.ROLE_DIAGONAL:
				if kind == "water":
					_place_diagonal_creek(along, size, side if side != 0 else 1)
			HoleData.ROLE_SHORELINE:
				if kind == "water":
					_place_shoreline(side if side != 0 else 1)
			HoleData.ROLE_EDGE:
				if kind == "tree":
					_place_tree_group(role, side if side != 0 else 1, along, size, art, int(spec.get("count", 1)))
				else:
					var fc2 := _fairway_center_at(along)
					var edge_c := Vector2(
						fc2.x + float(side if side != 0 else 1) * (_fairway_half + size * 0.55),
						fc2.y
					)
					if kind == "water":
						_place_edge_pond(edge_c, size)
					elif kind == "sand" and _clears_green(edge_c, size):
						_add_bunker(edge_c, size, art)


func _greenside_center(side: int, size: float) -> Vector2:
	## Place outside the same expanded ellipse _clears_green uses (was +10 vs +22 → silent drop).
	var rx := hole.green_radius_x + GREEN_HAZARD_PAD
	var ry := hole.green_radius_y + GREEN_HAZARD_PAD
	var dist := maxf(rx, ry) + GREEN_HAZARD_CLEAR_EXTRA + size + 4.0
	var ang: float
	if hole.pin_offset.length() > 4.0:
		ang = hole.pin_offset.angle()
	else:
		ang = -PI * 0.5 if side < 0 else PI * 0.5
	if side != 0:
		ang = lerpf(ang, float(side) * PI * 0.5, 0.45)
	# Tee entry is +Y (PI/2) — keep bunkers out of the approach wedge.
	var entry := PI * 0.5
	var step := float(side if side != 0 else 1) * deg_to_rad(35.0)
	for _i in 8:
		if absf(angle_difference(ang, entry)) > deg_to_rad(40.0):
			break
		ang += step
	# USGA: keep sand clear of the cup (~15 ft / 5 yd).
	var pin_clear := BallPhysics.yards_to_pixels(HoleGenerator.PIN_EDGE_MARGIN_YD) + size * 0.5
	var best := _green_center + Vector2(cos(ang), sin(ang)) * dist
	for _j in 12:
		var c := _green_center + Vector2(cos(ang), sin(ang)) * dist
		var pin_ok := c.distance_to(_cup_pos) >= pin_clear
		var green_ok := _clears_green(c, size)
		if pin_ok and green_ok:
			return c
		if pin_ok:
			best = c
		# Push out until outside green ellipse; rotate if still in approach wedge / pin.
		if not green_ok:
			dist += 6.0
		else:
			ang += step
	# Fallback: never silent-drop — place best candidate even if slightly tight.
	return best


func _place_island_ring() -> void:
	var water_tint := Color(1, 1, 1, 0.92)
	var clear := maxf(hole.green_radius_x, hole.green_radius_y) + 14.0 + 12.0
	var side_w := 90.0
	var side_h := 160.0
	var side_y := GREEN_Y - 30.0
	_add_rect(course_root, Rect2(540.0 - clear - side_w, side_y, side_w, side_h), water_tint, "water", TEX_WATER, 260.0)
	_add_rect(course_root, Rect2(540.0 + clear, side_y, side_w, side_h), water_tint, "water", TEX_WATER, 260.0)
	_add_rect(course_root, Rect2(540.0 - 100.0, GREEN_Y + clear, 200.0, 70.0), water_tint, "water", TEX_WATER, 260.0)


func _place_carry_creek(along: float, half_h: float) -> void:
	var fc := _fairway_center_at(along)
	var w := _fairway_half * 2.0 + 80.0
	var h := maxf(half_h, 18.0)
	var rect := Rect2(fc.x - w * 0.5, fc.y - h * 0.5, w, h)
	# Soft reject if creek would cover cup — push toward tee.
	var creek_c := rect.get_center()
	if not _clears_green(creek_c, maxf(w, h) * 0.35):
		along = minf(along + 0.12, 0.7)
		fc = _fairway_center_at(along)
		rect = Rect2(fc.x - w * 0.5, fc.y - h * 0.5, w, h)
	_add_water_sprite(rect.get_center(), Vector2(w, h), TEX_WATER_CREEK)


## Leven: diagonal band across landing (Cape + Leven water hazards epic).
const DIAGONAL_ANGLE_DEG := 30.0
const DIAGONAL_SIDE_BIAS := 18.0  ## px toward inside cut so risk/reward reads


func _place_diagonal_creek(along: float, half_h: float, side: int) -> void:
	var s := float(side if side != 0 else 1)
	var w := _fairway_half * 2.0 + 24.0  ## narrower than carry so the angle is legible
	var h := maxf(half_h, 18.0)
	var fc := _fairway_center_at(along)
	var center := Vector2(fc.x + s * DIAGONAL_SIDE_BIAS, fc.y)
	if not _clears_green(center, maxf(w, h) * 0.35):
		along = minf(along + 0.12, 0.7)
		fc = _fairway_center_at(along)
		center = Vector2(fc.x + s * DIAGONAL_SIDE_BIAS, fc.y)
	# Sign of angle follows side so left/right doglegs both cut across the fairway.
	var rot := DIAGONAL_ANGLE_DEG * s
	_add_water_sprite(center, Vector2(w, h), TEX_WATER_CREEK, rot)


## Cape: two panels along sharp-dogleg elbow (reads as one shoreline).
const SHORE_MARGIN := 8.0  ## px outside fairway edge
const SHORE_WIDTH := 52.0
const SHORE_PINCH := 0.3  ## 0=tight at green, 1=tight at tee


func _place_shoreline(side: int) -> void:
	if not _use_sharp_dogleg():
		return
	var s := float(side if side != 0 else 1)
	var cp := clampf(hole.corner_position, 0.05, 0.95)
	var p_green := _fairway_center_at(0.0)
	var p_corner := _fairway_center_at(cp)
	var p_tee := _fairway_center_at(1.0)
	# Green-end panel (tighter via pinch).
	_place_shore_segment(p_green, p_corner, s, lerpf(SHORE_MARGIN * 0.55, SHORE_MARGIN * 1.15, SHORE_PINCH))
	# Tee-end panel (looser).
	_place_shore_segment(p_corner, p_tee, s, lerpf(SHORE_MARGIN * 1.15, SHORE_MARGIN * 0.55, SHORE_PINCH))


func _place_shore_segment(a: Vector2, b: Vector2, side: float, margin: float) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 12.0:
		return
	var bearing := delta.angle()
	# Outward normal in 2D (perp of direction); side ±1 chooses shore bank.
	var normal := Vector2(-sin(bearing), cos(bearing)) * side
	var mid := (a + b) * 0.5
	var center := mid + normal * (_fairway_half + margin + SHORE_WIDTH * 0.5)
	var span := Vector2(length * 1.05, SHORE_WIDTH)
	if not _clears_green(center, maxf(span.x, span.y) * 0.28):
		return
	_add_water_sprite(center, span, TEX_WATER, rad_to_deg(bearing))


func _place_edge_pond(center: Vector2, size: float) -> void:
	if not _clears_green(center, size):
		return
	_add_water_sprite(center, Vector2(size * 1.6, size * 1.2), TEX_WATER_POND)


func _add_water_sprite(center: Vector2, span: Vector2, tex: Texture2D, rotation_deg: float = 0.0) -> void:
	var rot := deg_to_rad(rotation_deg)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = center
	spr.rotation = rot
	spr.scale = Vector2(
		span.x / float(tex.get_width()),
		span.y / float(tex.get_height())
	)
	spr.z_index = 1
	course_root.add_child(spr)
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.position = center
	area.rotation = rot
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = span
	cs.shape = shape
	area.add_child(cs)
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("water")
	course_root.add_child(area)


func _add_tee_boxes() -> void:
	## Blue / White / Red pads — all visible; active set is larger + bright marker.
	const MARK := {
		HoleData.TeeSet.BLUE: Color(0.23, 0.43, 0.65, 1.0),
		HoleData.TeeSet.WHITE: Color(0.91, 0.94, 0.91, 1.0),
		HoleData.TeeSet.RED: Color(0.77, 0.23, 0.23, 1.0),
	}
	for p in _tee_pads:
		var set: HoleData.TeeSet = p["set"]
		var pos: Vector2 = p["pos"]
		var active: bool = set == _active_tee
		var w := 56.0 if active else 44.0
		var h := 62.0 if active else 50.0
		var rect := Rect2(pos.x - w * 0.5, pos.y - h * 0.4, w, h)
		p["rect"] = rect
		var fill := Color(0.96, 1.0, 0.9) if active else Color(0.88, 0.92, 0.84)
		_add_rect(course_root, rect, fill, "tee", TEX_TEE, 180.0)
		var mark_r := 4.5 if active else 3.2
		_add_circle(course_root, pos, mark_r, MARK[set], "")


func _add_bunker(center: Vector2, radius: float, variant: int) -> void:
	var tex: Texture2D = BUNKER_TEXTURES[variant % BUNKER_TEXTURES.size()]
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = center
	var max_dim := maxf(float(tex.get_width()), float(tex.get_height()))
	spr.scale = Vector2.ONE * (radius * 2.3 / max_dim)
	course_root.add_child(spr)
	var img: Image = tex.get_image()
	_bunkers.append({"c": center, "r": radius, "sprite": spr, "img": img})
	# Broad enter-hint only; Sand lie / friction use paint via ground_lie_at + settle.
	_add_circle(course_root, center, radius * SAND_COLLISION_FRAC, Color(0, 0, 0, 0), "sand")


func _along_from_y(y: float) -> float:
	## Match _y_at: 0 = green, 1 = Blue tee.
	return clampf((y - GREEN_Y) / maxf(_tee_back_pos.y - GREEN_Y, 1.0), 0.0, 1.0)


func _play_corridor_width() -> float:
	## Fairway + deep-rough belts on both sides — the visual "hole channel".
	return maxf(_fairway_half * 2.0 + SIDE_BELT_W * 2.0, 140.0)


func _corridor_zoom_level() -> float:
	var view := get_viewport().get_visible_rect().size
	return clampf(view.x * CORRIDOR_SCREEN_FRAC / _play_corridor_width(), 1.05, 1.95)


func _flight_z_launch() -> float:
	return _flight_zoom_base * FLIGHT_LAUNCH_FRAC


func _flight_z_apex() -> float:
	return _flight_zoom_base * FLIGHT_APEX_FRAC


func _flight_z_land() -> float:
	return _flight_zoom_base * FLIGHT_LAND_FRAC


func _add_side_belts() -> void:
	## Dark rough strips hugging the fairway edge (follow bend). Not gameplay OOB.
	var step := 36.0
	var y := GREEN_Y - 50.0
	var y_end := _tee_back_pos.y + 70.0
	while y < y_end:
		var h := minf(step, y_end - y)
		var along := _along_from_y(y + h * 0.5)
		var cx := _fairway_center_x(along)
		var half := _fairway_half
		# Left / right deep rough just outside fairway
		_add_rect(
			course_root,
			Rect2(cx - half - SIDE_BELT_W, y, SIDE_BELT_W, h),
			Color(0.85, 0.9, 0.85),
			"",
			TEX_ROUGH_DARK,
			280.0
		)
		_add_rect(
			course_root,
			Rect2(cx + half, y, SIDE_BELT_W, h),
			Color(0.85, 0.9, 0.85),
			"",
			TEX_ROUGH_DARK,
			280.0
		)
		y += step


func _place_tree_group(
	role: String, side: int, along: float, size: float, art: int, count: int
) -> void:
	## Stamp 1..n canopies for a designed tree feature (edge line, landing clump, greenside).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tree_%s_%d_%d" % [role, hole.hole_number, int(along * 100.0)])
	var n := maxi(count, 1)
	var s := float(side if side != 0 else 1)
	for i in n:
		var a: float = along
		if role == HoleData.ROLE_EDGE:
			# Stretch along the corridor — gaps between individuals, not a hedge
			a = clampf(along + (float(i) - float(n - 1) * 0.5) * 0.055, 0.08, 0.92)
		elif n > 1:
			a = clampf(along + rng.randf_range(-0.03, 0.03), 0.05, 0.95)
		var c: Vector2
		if role == HoleData.ROLE_GREENSIDE:
			c = _greenside_center(int(s), size)
			c += Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-12.0, 12.0))
			c.x += s * float(i) * 14.0
		else:
			var fc := _fairway_center_at(a)
			var lat := _fairway_half + size * rng.randf_range(0.25, 0.55) + SIDE_BELT_W * 0.35
			if role == HoleData.ROLE_LANDING and n > 1:
				lat += float(i) * 8.0
			c = Vector2(fc.x + s * lat + rng.randf_range(-10.0, 10.0), fc.y + rng.randf_range(-14.0, 14.0))
		var r := size * rng.randf_range(0.72, 1.05)
		# Push off bunkers once or twice, then skip (no trees in sand).
		var placed := false
		for attempt in 3:
			var try_c := c + Vector2(s * float(attempt) * 22.0, 0.0)
			if not _clears_green(try_c, size * 0.55):
				continue
			if not _clears_bunkers(try_c, r * 0.72):
				continue
			c = try_c
			placed = true
			break
		if not placed:
			continue
		var art_i := art if art >= 0 else rng.randi_range(0, TREE_TEXTURES.size() - 1)
		if n > 1:
			art_i = (art_i + i * 2 + rng.randi_range(0, 2)) % TREE_TEXTURES.size()
		_add_tree(c, r, art_i)


func _add_tree(center: Vector2, radius: float, variant: int) -> void:
	var vi := variant % TREE_TEXTURES.size()
	var tex: Texture2D = TREE_TEXTURES[vi]
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = center
	var max_dim := maxf(float(tex.get_width()), float(tex.get_height()))
	spr.scale = Vector2.ONE * (radius * 2.15 / max_dim)
	spr.rotation = randf_range(-0.12, 0.12)
	spr.z_index = 1
	course_root.add_child(spr)
	var canopy := TREE_CANOPY_H[vi] if vi < TREE_CANOPY_H.size() else 30.0
	_trees.append({"c": center, "r": radius * 0.72, "canopy_h": canopy})
	var tree_area := _add_circle(course_root, center, radius * 0.72, Color(0, 0, 0, 0), "tree")
	tree_area.set_meta("canopy_h", canopy)


func _add_fog_band() -> void:
	## Soft haze past the green for depth.
	var spr := Sprite2D.new()
	spr.texture = TEX_FOG
	spr.position = Vector2(540, GREEN_Y - 280.0)
	spr.scale = Vector2(1240.0 / float(TEX_FOG.get_width()), 0.4)
	spr.modulate.a = 0.5
	spr.z_index = 4
	course_root.add_child(spr)


func _build_green_book() -> void:
	## Yardage-book from the same height field the ball samples. Aim-only.
	_green_book = Node2D.new()
	_green_book.name = "GreenBook"
	_green_book.z_index = 3
	_green_book.visible = false
	add_child(_green_book)

	var rx := hole.green_radius_x + 14.0
	var ry := hole.green_radius_y + 14.0
	var n := 16
	var h_min := INF
	var h_max := -INF
	var grid: PackedFloat32Array = PackedFloat32Array()
	grid.resize(n * n)
	for iy in n:
		for ix in n:
			var local := Vector2(
				(float(ix) / float(n - 1) - 0.5) * 2.0 * rx,
				(float(iy) / float(n - 1) - 0.5) * 2.0 * ry
			)
			var inside := (local.x * local.x) / (rx * rx) + (local.y * local.y) / (ry * ry) <= 1.05
			var h := hole.green_height_at(local) if inside else 0.0
			grid[iy * n + ix] = h
			if inside:
				h_min = minf(h_min, h)
				h_max = maxf(h_max, h)
	if h_max - h_min < 0.001:
		h_min = -1.0
		h_max = 1.0

	var drawer := _GreenBookDraw.new()
	drawer.position = _green_center
	_green_book.add_child(drawer)

	var heat_lut := [
		Color(0.25, 0.55, 0.95, 0.42),
		Color(0.35, 0.75, 0.85, 0.38),
		Color(0.55, 0.85, 0.45, 0.34),
		Color(0.95, 0.75, 0.3, 0.4),
		Color(0.95, 0.4, 0.25, 0.45),
	]
	var cell := Vector2(2.0 * rx / float(n - 1), 2.0 * ry / float(n - 1))
	for iy in n - 1:
		for ix in n - 1:
			var local := Vector2(
				(float(ix) / float(n - 1) - 0.5) * 2.0 * rx + cell.x * 0.5,
				(float(iy) / float(n - 1) - 0.5) * 2.0 * ry + cell.y * 0.5
			)
			if (local.x * local.x) / (rx * rx) + (local.y * local.y) / (ry * ry) > 1.0:
				continue
			var h := (
				grid[iy * n + ix] + grid[iy * n + ix + 1]
				+ grid[(iy + 1) * n + ix] + grid[(iy + 1) * n + ix + 1]
			) * 0.25
			var t := clampf((h - h_min) / (h_max - h_min), 0.0, 1.0)
			var ci := mini(int(t * float(heat_lut.size() - 1) + 0.001), heat_lut.size() - 1)
			var hx := cell.x * 0.52
			var hy := cell.y * 0.52
			drawer.heat.append({
				"pts": PackedVector2Array([
					local + Vector2(-hx, -hy),
					local + Vector2(hx, -hy),
					local + Vector2(hx, hy),
					local + Vector2(-hx, hy),
				]),
				"color": heat_lut[ci],
			})
	drawer.queue_redraw()


class _GreenBookDraw extends Node2D:
	var heat: Array = []

	func _draw() -> void:
		for h in heat:
			draw_colored_polygon(h["pts"], h["color"])


func _should_show_green_book() -> bool:
	if hole == null or ball == null:
		return false
	if ball.get_lie() == "Green":
		return true
	if _pin_yards() <= 80.0:
		return true
	var apron := maxf(hole.green_radius_x, hole.green_radius_y) + 70.0
	return _aim_target.distance_to(_green_center) <= apron


func _is_putt_context() -> bool:
	return ball.get_lie() == "Green" or _pin_yards() <= 28.0


func _sync_pin_flag_visible() -> void:
	## Pin out only on the putting surface — not for chips/approaches inside 28 yd.
	if _pin_flag == null:
		return
	var on_green := ball != null and ball.get_lie() == "Green"
	_pin_flag.visible = not on_green


func _update_pin_flag_wind() -> void:
	if _pin_flag == null:
		return
	var wind: Vector2 = Vector2.ZERO
	if course_root:
		wind = course_root.get_meta("wind", hole.wind_vector if hole else Vector2.ZERO)
	elif hole:
		wind = hole.wind_vector
	if _pin_flag.has_method("set_wind"):
		_pin_flag.call("set_wind", wind)


func _set_green_book_visible(on: bool) -> void:
	if _green_book:
		_green_book.visible = on
	if on:
		_sync_screen_line_widths()


func _sync_screen_line_widths() -> void:
	## Keep Line2D stroke thickness roughly constant on screen as camera zooms.
	var z := maxf(camera.zoom.x, 0.35)
	var pin_w := 2.0 / z
	if _pin_ref_line:
		_pin_ref_line.width = pin_w
	if _aim_circle:
		_aim_circle.width = 3.2 / z
	if _wind_bias and _wind_bias.visible:
		_wind_bias.width = 3.2 / z
	if _green_book:
		for c in _green_book.get_children():
			if c is Line2D:
				var target_px := float(c.get_meta("screen_px", 2.2))
				(c as Line2D).width = target_px / z


func _add_rect(parent: Node2D, rect: Rect2, color: Color, group: String, texture: Texture2D = null, tile_px: float = 300.0) -> Area2D:
	if color.a > 0.0:
		var poly := Polygon2D.new()
		poly.color = color
		if texture:
			poly.texture = texture
			poly.texture_scale = Vector2.ONE * (float(texture.get_width()) / tile_px)
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.polygon = PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.position + rect.size,
			rect.position + Vector2(0, rect.size.y),
		])
		parent.add_child(poly)
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.position + rect.size * 0.5
	area.add_child(cs)
	area.monitoring = false
	area.monitorable = true
	if group != "":
		area.add_to_group(group)
	parent.add_child(area)
	return area


func _add_circle(parent: Node2D, center: Vector2, radius: float, color: Color, group: String) -> Area2D:
	if color.a > 0.0:
		var poly := Polygon2D.new()
		poly.color = color
		poly.position = center
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		poly.polygon = pts
		parent.add_child(poly)
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	area.position = center
	area.add_child(cs)
	area.monitoring = false
	area.monitorable = true
	if group != "":
		area.add_to_group(group)
	parent.add_child(area)
	return area


func _start_shot_ui() -> void:
	if hole_complete or not GameState.run_active:
		return
	ball.clear_trail()
	shot_routine.set_active(false)
	if shot_result_panel and shot_result_panel.has_method("hide_now"):
		shot_result_panel.hide_now()
	var lie := ball.get_lie()
	if lie == "Green":
		var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
		_chosen_club = BallPhysics.putter_for(pin_yd)
		if _is_tap_in(pin_yd):
			_begin_tap_in_stroke(pin_yd)
		else:
			_begin_aim_phase()
	elif GameState.range_mode and not _chosen_club.is_empty():
		# Range: keep last club until Change Club (don't force picker every swing).
		_begin_range_swing()
	else:
		_begin_club_select()


func _is_tap_in(pin_yd: float) -> bool:
	## Short + flat → skip read/aim ceremony; stroke still required.
	if pin_yd > GameState.tap_in_yd:
		return false
	var local := ball.global_position - _green_center
	var break_mag := hole.green_slope_at(local).length()
	return break_mag <= GameState.tap_in_break


func _begin_tap_in_stroke(pin_yd: float) -> void:
	## Auto-aim slightly past the cup; go straight to the putt stroke.
	_aiming = false
	_aim_dragging = false
	_selecting_club = false
	if _club_select:
		_club_select.dismiss()
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _change_club_btn:
		_change_club_btn.visible = false
	_set_green_book_visible(false)
	_refresh_wind_indicator(false)
	_aim_radius_base_yd = GameState.get_aim_radius_yards(true)
	_aim_radius_yd = _aim_radius_base_yd
	var from := ball.global_position
	var to_cup := _cup_pos - from
	var past := maxf(pin_yd * 0.15, 0.4)  # small past-hole pace bias
	var past_px := BallPhysics.yards_to_pixels(past)
	if to_cup.length_squared() < 1.0:
		_aim_target = _cup_pos
	else:
		_aim_target = AimControl.clamp_aim(_cup_pos + to_cup.normalized() * past_px)
	_aim_lock_yards = BallPhysics.pixels_to_yards(from.distance_to(_aim_target))
	_power_previewing = true
	_refresh_aim_visuals()
	_set_aim_visuals_visible(true)
	feedback.text = "Tap-in · stroke"
	feedback.modulate = Color(0.75, 0.9, 0.95)
	_start_power_swing(false)


func _begin_club_select() -> void:
	_preserve_aim_line = _aiming
	_aiming = false
	_aim_dragging = false
	_selecting_club = true
	_set_aim_visuals_visible(false)
	_refresh_wind_indicator(false)
	_set_green_book_visible(false)
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _change_club_btn:
		_change_club_btn.visible = false
	if _punch_btn:
		_punch_btn.visible = false
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	feedback.text = "RANGE — pick a club" if GameState.range_mode else "%d yd — pick a club" % int(pin_yd)
	feedback.modulate = Color(0.95, 0.92, 0.7)
	_show_wind_flag(wind)
	_club_select.present(lie, pin_yd, wind, ball.get_lie_severity())


func _on_club_chosen(club: Dictionary) -> void:
	_selecting_club = false
	_chosen_club = club
	AudioBus.play_club_bag()
	if GameState.range_mode:
		_preserve_aim_line = false
		_begin_range_swing()
	else:
		var keep := _preserve_aim_line
		_preserve_aim_line = false
		_begin_aim_phase(keep)


func _begin_range_swing() -> void:
	## Skip aim — fixed center line. Wedges use a short pitch target so 2:1 is
	## practiceable; stock 85% max never entered the pitch gate on range.
	_aiming = false
	_aim_dragging = false
	if _club_select:
		_club_select.dismiss()
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	_set_green_book_visible(false)
	_refresh_wind_indicator(false)
	var lie := "Tee"
	var club_max := float(_chosen_club.get("max_yards", 180.0))
	var wind: Vector2 = course_root.get_meta("wind", Vector2.ZERO)
	var target_yd := club_max * 0.85
	# PW (110) + Gap/Sand (85): short target inside pitch band, above chip.
	if club_max <= 110.0:
		var gate := minf(TempoGrade.PITCH_YD, club_max * TempoGrade.PITCH_POWER_CAP)
		if gate > TempoGrade.CHIP_YD + 2.0:
			target_yd = clampf(club_max * 0.35, TempoGrade.CHIP_YD + 2.0, gate - 1.0)
	var recommend := BallPhysics.recommended_power(target_yd, club_max, lie, wind)
	var est := BallPhysics.estimate_carry_yards(recommend, club_max, lie)
	var bearing := _cup_pos - _tee_pos
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	_aim_target = AimControl.point_along_bearing(_tee_pos, bearing, est)
	_aim_radius_base_yd = GameState.get_aim_radius_yards(false, club_max)
	_aim_radius_yd = _aim_radius_base_yd
	_aim_lock_yards = est
	_power_previewing = true
	_refresh_aim_visuals()
	_set_aim_visuals_visible(true)
	# Sticky club: Change Club still available so you can switch without re-entering range.
	if _change_club_btn:
		_change_club_btn.visible = true
	_start_power_swing(false)


func _aim_force_preview(club_max: float, lie: String, wind: Vector2, severity: String) -> float:
	## Force from uncapped true % so overclub (floored to pocket) still widens the circle.
	var aim_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	if aim_yd < 1.0:
		aim_yd = BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var solved := BallPhysics.solve_committed_power(aim_yd, club_max, lie, wind, severity)
	return BallPhysics.force_factor(float(solved["true_pct"]), club_max, lie)


func _aim_radius_for_club(lie: String, club_max: float, wind: Vector2, severity: String) -> float:
	var on_green := lie == "Green"
	var force := 0.0 if on_green else _aim_force_preview(club_max, lie, wind, severity)
	return GameState.get_aim_radius_yards(on_green, club_max, force)


func _refit_aim_along_bearing(club_max: float, wind: Vector2, severity: String) -> void:
	## Keep aim bearing; set lock distance to this club's sensible carry (clearance club-swap).
	var from := ball.global_position
	var bearing := _aim_target - from
	if bearing.length_squared() < 1.0:
		bearing = _cup_pos - from
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	var pin_yd := BallPhysics.pixels_to_yards(from.distance_to(_cup_pos))
	var lie := ball.get_lie()
	var solved := BallPhysics.solve_committed_power(pin_yd, club_max, lie, wind, severity)
	var est := BallPhysics.estimate_carry_yards(float(solved["power"]), club_max, lie, severity)
	_aim_target = AimControl.point_along_bearing(from, bearing, est)
	_aim_lock_yards = est


func _begin_aim_phase(restore_aim: bool = false) -> void:
	_aiming = true
	_aim_dragging = false
	_reset_pinch_state()
	_selecting_club = false
	if _club_select:
		_club_select.dismiss()
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	if _chosen_club.is_empty():
		_chosen_club = BallPhysics.pick_club(pin_yd, lie, ball.get_lie_severity())
	var club_max := float(_chosen_club["max_yards"])
	_power_previewing = false
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	var severity := ball.get_lie_severity()
	# restore_aim: keep bearing (club-change or back from swing). Refit lock distance for club.
	if not restore_aim:
		_aim_target = AimControl.default_aim_target(
			ball.global_position,
			_cup_pos,
			lie,
			club_max,
			wind,
			severity
		)
		_aim_target = AimControl.clamp_aim(_aim_target)
		_aim_lock_yards = BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	else:
		_refit_aim_along_bearing(club_max, wind, severity)
	_aim_radius_base_yd = _aim_radius_for_club(lie, club_max, wind, severity)
	_aim_radius_yd = _aim_radius_base_yd
	var show_book := _should_show_green_book()
	var is_putt := lie == "Green"
	_set_green_book_visible(show_book)
	if confirm_aim_btn:
		confirm_aim_btn.visible = true
	if _change_club_btn:
		_change_club_btn.visible = not is_putt
	_sync_punch_btn()
	# Putts: no wind. Flag tip carries green-book note (tap to read).
	if is_putt:
		_refresh_wind_indicator(false)
	else:
		_show_wind_flag(wind, "Green book — read the break" if show_book else "")
	_refresh_aim_visuals()
	var club_bit := String(_chosen_club.get("name", ""))
	if is_putt:
		_refresh_putt_pace_feedback()
	elif show_book:
		feedback.text = "%s · AIM + GREEN READ — drag, Confirm" % club_bit
	else:
		feedback.text = "%s · AIM — drag, Confirm" % club_bit
	feedback.modulate = Color(0.95, 0.92, 0.7)
	# Snap camera so putt/approach book is immediately readable (no smoothing lag)
	camera.position_smoothing_enabled = false
	camera.global_position = _desired_camera_look()
	camera.zoom = _desired_camera_zoom()
	_sync_screen_line_widths()


func _end_aim_phase() -> void:
	_aiming = false
	_aim_dragging = false
	_selecting_club = false
	_power_previewing = false
	if _club_select:
		_club_select.dismiss()
	_set_aim_visuals_visible(false)
	_refresh_wind_indicator(false)
	_set_green_book_visible(false)
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _change_club_btn:
		_change_club_btn.visible = false
	if shot_routine and shot_routine.back_btn:
		shot_routine.back_btn.visible = false



func _setup_change_club_btn() -> void:
	## Bag icon directly under the cart-GPS map (top-right chrome column).
	_change_club_btn = TextureButton.new()
	_change_club_btn.name = "ChangeClubButton"
	_change_club_btn.visible = false
	_change_club_btn.texture_normal = TEX_CLUB_BAG
	_change_club_btn.ignore_texture_size = true
	_change_club_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_change_club_btn.custom_minimum_size = Vector2(CHANGE_CLUB_ICON, CHANGE_CLUB_ICON)
	_change_club_btn.tooltip_text = "Change Club"
	_change_club_btn.focus_mode = Control.FOCUS_NONE
	_change_club_btn.z_index = 6  # HoleMap is z=5
	_change_club_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_layer.add_child(_change_club_btn)
	_change_club_btn.pressed.connect(_on_change_club_pressed)
	_park_change_club_btn()


func _park_change_club_btn() -> void:
	if _change_club_btn == null:
		return
	var m := UiScale.viewport_safe_margins(get_viewport())
	# HoleMap.park_under_debug band, then sit flush under the map (right-aligned).
	var map_top := UiScale.HUD_HEIGHT + m.y + 8.0 + 60.0 + 10.0
	var right := m.z + 16.0
	var s := CHANGE_CLUB_ICON
	var gap := 8.0
	var top := map_top + HoleMap.MAP_H + gap
	_change_club_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_change_club_btn.offset_right = -right
	_change_club_btn.offset_left = -right - s
	_change_club_btn.offset_top = top
	_change_club_btn.offset_bottom = top + s
	_park_punch_btn(top + s + gap, right)


func _setup_scorecard() -> void:
	scorecard = ScoreCard.new()
	scorecard.name = "ScoreCard"
	ui_layer.add_child(scorecard)
	scorecard.hide_card()


func _setup_punch_btn() -> void:
	## Trees aim only — toggle low punch under canopy.
	_punch_btn = Button.new()
	_punch_btn.name = "PunchButton"
	_punch_btn.visible = false
	_punch_btn.toggle_mode = true
	_punch_btn.text = "Punch"
	_punch_btn.tooltip_text = "Low flight under trees · more roll"
	_punch_btn.focus_mode = Control.FOCUS_NONE
	_punch_btn.z_index = 6
	_punch_btn.custom_minimum_size = Vector2(120, UiScale.TOUCH_MIN * 0.55)
	_punch_btn.add_theme_font_size_override("font_size", UiScale.CAPTION)
	ui_layer.add_child(_punch_btn)
	_punch_btn.toggled.connect(_on_punch_toggled)


func _park_punch_btn(top: float, right: float) -> void:
	if _punch_btn == null:
		return
	var w := 128.0
	var h := UiScale.TOUCH_MIN * 0.55
	_punch_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_punch_btn.offset_right = -right
	_punch_btn.offset_left = -right - w
	_punch_btn.offset_top = top
	_punch_btn.offset_bottom = top + h


func _on_punch_toggled(on: bool) -> void:
	_punch_mode = on and ball != null and ball.get_lie() == "Trees"
	_punch_btn.button_pressed = _punch_mode
	_punch_btn.text = "Punch ON" if _punch_mode else "Punch"
	AudioBus.play_ui()
	if _aiming:
		_refresh_aim_visuals()


func _sync_punch_btn() -> void:
	if _punch_btn == null:
		return
	var trees := ball != null and ball.get_lie() == "Trees"
	_punch_btn.visible = trees and _aiming and not hole_complete
	if not trees:
		_punch_mode = false
		_punch_btn.button_pressed = false
		_punch_btn.text = "Punch"
	else:
		_punch_btn.button_pressed = _punch_mode
		_punch_btn.text = "Punch ON" if _punch_mode else "Punch"


func _on_change_club_pressed() -> void:
	if hole_complete:
		return
	# Course: only during aim. Range: anytime before/after a sticky swing.
	if not GameState.range_mode and not _aiming:
		return
	AudioBus.play_ui()
	if GameState.range_mode:
		shot_routine.set_active(false)
		if shot_routine.has_method("cancel_shot"):
			shot_routine.cancel_shot()
	_begin_club_select()


func _on_back_requested() -> void:
	## Re-do window: player backed out after Confirm, before the swing gesture
	## started moving. shot_routine.cancel_shot() already dropped the aborted
	## attempt's tempo state; restore_aim=true keeps the last aim point instead
	## of resetting to the default target.
	if hole_complete or not GameState.run_active:
		return
	shot_routine.cancel_shot()
	_practice_reps_left = 0
	if shot_routine.has_method("set_rep_indicator"):
		shot_routine.set_rep_indicator(0, 0, false)
	AudioBus.play_ui()
	_begin_aim_phase(true)


func _confirm_aim() -> void:
	if not _aiming or hole_complete:
		return
	_aiming = false
	_aim_dragging = false
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _change_club_btn:
		_change_club_btn.visible = false
	if _punch_btn:
		_punch_btn.visible = false
	_set_green_book_visible(false)  # close the book before stroking
	_refresh_wind_indicator(false)
	AudioBus.play_ui()
	# Auto practice reps (0–3 per shot type), then real shot. Range never uses confirm-aim.
	# Back stays available on practice reps too (until takeaway) so club/aim can change.
	_practice_reps_left = 0 if GameState.range_mode else _practice_count_for_current_shot()
	var is_practice := _practice_reps_left > 0
	_start_power_swing(is_practice, true)


func _practice_count_for_current_shot() -> int:
	var lie := ball.get_lie()
	var aim_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	var club_max := float(_chosen_club.get("max_yards", 0.0))
	return GameState.practice_swing_count_for(TempoGrade.shot_type_for(lie, aim_yd, club_max))


func _start_power_swing(p_practice: bool = false, p_allow_back: bool = false) -> void:
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var aim_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	var timing := hole.timing_window_scale
	var shape_amt := 0.0
	if lie != "Green":
		match hole.suggested_shape:
			HoleData.SuggestedShape.DRAW:
				shape_amt = -0.35
			HoleData.SuggestedShape.FADE:
				shape_amt = 0.35
			_:
				shape_amt = 0.0
	var shape_label := AimControl.aim_offset_label(ball.global_position, _aim_target, _cup_pos)
	var club_name := String(_chosen_club.get("name", ""))
	var club_max := float(_chosen_club.get("max_yards", -1.0))
	var punch := _punch_mode and lie == "Trees"
	shot_routine.configure(
		lie,
		aim_yd,
		pin_yd,
		wind,
		shape_label,
		timing,
		shape_amt,
		_aim_radius_yd,
		club_name,
		club_max,
		ball.get_lie_severity(),
		punch
	)
	# Landing preview locked to committed carry (gesture can only subtract).
	_power_previewing = not p_practice
	_apply_committed_preview()
	shot_routine.begin_shot(p_practice, p_allow_back)
	if not shot_routine.practice_result.is_connected(_on_practice_result):
		shot_routine.practice_result.connect(_on_practice_result)
	_set_green_book_visible(false)
	var total_pr := 0 if GameState.range_mode else _practice_count_for_current_shot()
	if shot_routine.has_method("set_rep_indicator"):
		shot_routine.set_rep_indicator(_practice_reps_left, total_pr, not p_practice)
	if p_practice:
		var done := total_pr - _practice_reps_left + 1
		feedback.text = "Practice %d/%d — find your tempo" % [clampi(done, 1, maxi(total_pr, 1)), maxi(total_pr, 1)]
	elif lie == "Green":
		feedback.text = ""  # club icon/label + hint own the stroke UI
	elif punch:
		feedback.text = "Punch · low flight · more roll"
	else:
		feedback.text = "%s · nail the tempo" % club_name


func _refresh_putt_pace_feedback() -> void:
	## Spatial read only — no live pace/pin numbers (those leak the stroke answer).
	feedback.text = "Putt — set line & pace"
	feedback.modulate = Color(0.95, 0.92, 0.7)


func _apply_committed_preview() -> void:
	var lie := ball.get_lie()
	var club_max := float(_chosen_club.get("max_yards", shot_routine.club_max_yards))
	var power := shot_routine.committed_power
	var est := BallPhysics.estimate_carry_yards(power, club_max, lie, ball.get_lie_severity())
	var from := ball.global_position
	var bearing := _aim_target - from
	if bearing.length_squared() < 1.0:
		bearing = _cup_pos - from
	_aim_target = AimControl.point_along_bearing(from, bearing, est)
	_aim_radius_yd = _aim_radius_base_yd
	_refresh_aim_visuals()


func _on_practice_result(verdict: Dictionary) -> void:
	## Practice rep finished — meter shows coaching; fairway only a short badge.
	var contact: Variant = verdict.get("contact", null)
	var tag := ""
	if contact != null:
		match int(contact):
			ShotResult.ContactQuality.PERFECT:
				tag = "PERFECT"
			ShotResult.ContactQuality.GOOD:
				tag = "GOOD"
			ShotResult.ContactQuality.THIN:
				tag = "THIN"
			ShotResult.ContactQuality.FAT:
				tag = "FAT"
			ShotResult.ContactQuality.MISS:
				tag = "MISS"
	feedback.text = "Practice · %s" % tag if not tag.is_empty() else "Practice"
	feedback.modulate = Color(0.85, 0.95, 0.75)
	_power_previewing = false
	if hole_complete or not GameState.run_active:
		return
	# Hold long enough to read structured meter lines (not a fairway wall of text).
	await get_tree().create_timer(2.2).timeout
	if hole_complete or not GameState.run_active:
		return
	_practice_reps_left = maxi(_practice_reps_left - 1, 0)
	if _practice_reps_left > 0:
		_start_power_swing(true, true)
	else:
		_start_power_swing(false, true)


func _set_aim_visuals_visible(on: bool) -> void:
	var is_putt := ball != null and ball.get_lie() == "Green"
	if _aim_cone:
		_aim_cone.visible = on and not is_putt
	if _aim_cone_edge:
		_aim_cone_edge.visible = on and not is_putt
	if _aim_cone_edge_r:
		_aim_cone_edge_r.visible = on and not is_putt
	if _aim_circle:
		_aim_circle.visible = on and not is_putt
	if _pin_ref_line:
		_pin_ref_line.visible = on
	if not on and _wind_bias:
		_wind_bias.visible = false


func _show_wind_flag(wind: Vector2, extra: String = "") -> void:
	if _wind_flag == null:
		return
	_wind_flag.show_wind(wind, extra)
	_refresh_wind_bias_arrow()


func _refresh_wind_indicator(on: bool) -> void:
	if _wind_flag == null:
		return
	if not on:
		_wind_flag.hide_wind()
		if _wind_bias:
			_wind_bias.visible = false
		return
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector) if course_root else Vector2.ZERO
	if _wind_flag.visible:
		_wind_flag.set_wind_vector(wind)
	else:
		_wind_flag.show_wind(wind)
	_refresh_wind_bias_arrow()


func _refresh_wind_bias_arrow() -> void:
	## Small rim arrow on the aim circle — bias opposite wind push.
	if _wind_bias == null or _aim_circle == null or not _aim_circle.visible:
		if _wind_bias:
			_wind_bias.visible = false
		return
	if ball != null and ball.get_lie() == "Green":
		_wind_bias.visible = false
		return
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector) if course_root else Vector2.ZERO
	if wind.length() < 4.0:
		_wind_bias.visible = false
		return
	var to := _aim_target
	var radius_px := BallPhysics.yards_to_pixels(_aim_radius_yd)
	var bias := -wind.normalized()
	var tip := to + bias * radius_px
	var base := to + bias * maxf(radius_px - 36.0, radius_px * 0.55)
	var perp := Vector2(-bias.y, bias.x) * 10.0
	_wind_bias.points = PackedVector2Array([base + perp, tip, base - perp, base + perp])
	_wind_bias.width = 3.2 / maxf(camera.zoom.x, 0.35)
	_wind_bias.visible = true


func _aim_shape_bend() -> float:
	if ball.get_lie() == "Green" or hole == null:
		return 0.0
	match hole.suggested_shape:
		HoleData.SuggestedShape.DRAW:
			return -0.35
		HoleData.SuggestedShape.FADE:
			return 0.35
		_:
			return 0.0


func _aim_tree_clearance(from: Vector2, to: Vector2, club_max: float, punch: bool = false) -> String:
	## "none" | "clear" | "blocked" — clean-strike prediction for aim cone tint.
	if _trees.is_empty() or club_max <= 0.0:
		return "none"
	var lie := ball.get_lie()
	var severity := ball.get_lie_severity()
	var aim_yd := BallPhysics.pixels_to_yards(from.distance_to(to))
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector) if course_root else Vector2.ZERO
	var solved := BallPhysics.solve_committed_power(aim_yd, club_max, lie, wind, severity)
	var carry_yd := BallPhysics.estimate_carry_yards(
		float(solved["power"]), club_max, lie, severity
	)
	if carry_yd < 2.0:
		return "none"
	# Flight type for apex: punch ducks under; full/pitch for normal.
	var shot_type := "punch" if punch else TempoGrade.shot_type_for(lie, aim_yd, club_max)
	var total_px := BallPhysics.yards_to_pixels(carry_yd)
	var air_frac := BallPhysics.air_distance_fraction(club_max, shot_type)
	var peak := BallPhysics.estimate_height_peak(club_max, carry_yd, shot_type)
	# Segment ends at carry land point along aim bearing (not past club max).
	var bearing := to - from
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	var land := from + bearing.normalized() * total_px
	var any_hit := false
	var any_block := false
	for tr in _trees:
		var c: Vector2 = tr["c"]
		var r: float = float(tr["r"])
		var canopy: float = float(tr.get("canopy_h", 30.0))
		var along := BallPhysics.segment_hits_disk(from, land, c, r)
		if along < 0.0:
			continue
		any_hit = true
		var h := BallPhysics.estimate_height_at_along(along, total_px, air_frac, peak)
		if h < canopy:
			any_block = true
	if not any_hit:
		return "none"
	return "blocked" if any_block else "clear"


func _tint_cone_colors(cols: PackedColorArray, kind: String) -> PackedColorArray:
	if kind == "none" or cols.is_empty():
		return cols
	var tint := Color(1.0, 0.92, 0.4, 1.0)
	if kind == "blocked":
		tint = Color(0.95, 0.32, 0.28, 1.0)
	elif kind == "clear":
		tint = Color(0.35, 0.88, 0.42, 1.0)
	var out := PackedColorArray()
	for i in cols.size():
		var c := cols[i]
		var mixed := c.lerp(Color(tint.r, tint.g, tint.b, c.a), 0.72)
		out.append(mixed)
	return out


func _refresh_aim_visuals() -> void:
	var from := ball.global_position
	var to := _aim_target
	var is_putt := ball.get_lie() == "Green"
	var inv_z := 1.0 / maxf(camera.zoom.x, 0.35)
	if is_putt:
		## White direction line that fades out — not a cup ruler / iron wedge.
		var along := to - from
		var len_px := along.length()
		if len_px < 1.0:
			along = Vector2(0, -1)
			len_px = 8.0
		var tip := from + along.normalized() * (len_px * 0.88)
		_pin_ref_line.points = PackedVector2Array([from, tip])
		_pin_ref_line.width = 2.6 / maxf(camera.zoom.x, 0.35)
		_pin_ref_line.default_color = Color(1.0, 1.0, 1.0, 0.55)
		if _pin_ref_line.gradient == null:
			var fade := Gradient.new()
			fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			fade.colors = PackedColorArray([
				Color(1.0, 1.0, 1.0, 0.55),
				Color(1.0, 1.0, 1.0, 0.22),
				Color(1.0, 1.0, 1.0, 0.0),
			])
			_pin_ref_line.gradient = fade
		_set_aim_visuals_visible(true)
	else:
		_pin_ref_line.gradient = null
		# Cone's widest point (tip) matches the dispersion circle's own radius exactly —
		# tight takeoff read at the ball, fanning out to the real landing-area width.
		var radius_px := BallPhysics.yards_to_pixels(_aim_radius_yd)
		var cone: Dictionary = AimControl.make_aim_cone(
			from, to, _aim_shape_bend(), 10.0 * inv_z, radius_px, _power_previewing
		)
		var club_max := float(_chosen_club.get("max_yards", 0.0))
		var clearance := _aim_tree_clearance(
			from, to, club_max, _punch_mode and ball.get_lie() == "Trees"
		)
		var cols: PackedColorArray = _tint_cone_colors(cone["colors"], clearance)
		_aim_cone.polygon = cone["points"]
		_aim_cone.vertex_colors = cols
		# Each flank is stroked as its own open polyline (skip the near-ball base) —
		# the two flanks end tangent to the landing circle rather than meeting each
		# other, so they must stay unconnected or the join would draw a straight
		# line across the circle's face.
		# Point layout from AimControl.make_aim_cone: base_l, base_r, mid_r, tip_r,
		# [near-side arc samples...], tip_l, mid_l — arc length varies with geometry,
		# so the left-side pair is read from the end, not a fixed index.
		var pts: PackedVector2Array = cone["points"]
		var edge_l := PackedVector2Array()
		var edge_r := PackedVector2Array()
		if pts.size() >= 6:
			var n := pts.size()
			edge_l.append(pts[0])
			edge_l.append(pts[n - 1])
			edge_l.append(pts[n - 2])
			edge_r.append(pts[1])
			edge_r.append(pts[2])
			edge_r.append(pts[3])
		_aim_cone_edge.points = edge_l
		_aim_cone_edge.width = (2.4 if _power_previewing else 1.8) / maxf(camera.zoom.x, 0.35)
		var edge_a := 0.55 if _power_previewing else 0.28
		var edge_col := Color(1.0, 0.92, 0.4, edge_a)
		if clearance == "blocked":
			edge_col = Color(0.95, 0.35, 0.3, edge_a + 0.15)
		elif clearance == "clear":
			edge_col = Color(0.4, 0.9, 0.45, edge_a + 0.12)
		_aim_cone_edge.default_color = edge_col
		_aim_cone_edge_r.points = edge_r
		_aim_cone_edge_r.width = _aim_cone_edge.width
		_aim_cone_edge_r.default_color = edge_col
		_pin_ref_line.points = PackedVector2Array([from, _cup_pos])
		_pin_ref_line.width = 2.0 / maxf(camera.zoom.x, 0.35)
		_pin_ref_line.default_color = Color(1.0, 1.0, 1.0, 0.22)
		_aim_circle.points = AimControl.make_circle_points(to, radius_px)
		var circle_col := Color(1.0, 0.92, 0.35, 0.95 if _power_previewing else 0.85)
		if clearance == "blocked":
			circle_col = Color(0.95, 0.4, 0.32, 0.9)
		elif clearance == "clear":
			circle_col = Color(0.45, 0.92, 0.5, 0.9)
		_aim_circle.default_color = circle_col
		_set_aim_visuals_visible(true)
	if _aiming:
		_set_green_book_visible(_should_show_green_book())
		_refresh_wind_indicator(not is_putt)
	elif _wind_bias:
		_wind_bias.visible = false


func _world_mouse() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()


func _accept_mouse() -> bool:
	## On phones, Godot also emits emulated mouse for each touch — ignore those.
	return not DisplayServer.is_touchscreen_available()


func _apply_aim_world(world: Vector2) -> void:
	var from := ball.global_position
	if ball.get_lie() == "Green":
		# Putts aim a real point — distance is the pace commit.
		_aim_target = AimControl.clamp_aim(world)
		if _aiming:
			_refresh_putt_pace_feedback()
	else:
		_aim_target = AimControl.retarget_bearing(from, world, _aim_lock_yards)
	_refresh_aim_visuals()


func _nudge_aim(delta: Vector2) -> void:
	_apply_aim_world(_aim_target + delta)


func _begin_pinch(idx_a: int, idx_b: int) -> void:
	_pinch_idx_a = idx_a
	_pinch_idx_b = idx_b
	_pinch_start_dist = maxf(_active_touches[idx_a].distance_to(_active_touches[idx_b]), PINCH_MIN_SPAN_PX)
	_pinch_start_mult = _user_zoom_mult
	_aim_dragging = false  # a second finger down means this is a pinch, not an aim drag


func _update_pinch() -> void:
	if not _active_touches.has(_pinch_idx_a) or not _active_touches.has(_pinch_idx_b):
		return
	var dist: float = maxf(
		_active_touches[_pinch_idx_a].distance_to(_active_touches[_pinch_idx_b]), PINCH_MIN_SPAN_PX
	)
	_user_zoom_mult = clampf(_pinch_start_mult * (dist / _pinch_start_dist), PINCH_MULT_MIN, PINCH_MULT_MAX)


func _end_pinch() -> void:
	_pinch_idx_a = -1
	_pinch_idx_b = -1
	# Release trigger: snap back to the auto-framed zoom immediately — the existing
	# per-frame camera.zoom lerp in _process() eases the visual transition.
	_user_zoom_mult = 1.0


func _reset_pinch_state() -> void:
	_active_touches.clear()
	_pinch_idx_a = -1
	_pinch_idx_b = -1
	_user_zoom_mult = 1.0
	_magnify_last_ms = -1


func _unhandled_input(event: InputEvent) -> void:
	if not _aiming:
		if not _active_touches.is_empty() or _pinch_idx_a >= 0:
			_reset_pinch_state()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_active_touches[touch.index] = touch.position
			if _active_touches.size() == 2:
				var idxs := _active_touches.keys()
				_begin_pinch(idxs[0], idxs[1])
			elif _active_touches.size() == 1:
				_aim_dragging = true
				var screen := AimControl.touch_aim_screen(touch.position)
				var world := get_viewport().get_canvas_transform().affine_inverse() * screen
				_apply_aim_world(world)
			# 3rd+ finger: ignore, leave the active pinch/drag undisturbed.
		else:
			_active_touches.erase(touch.index)
			if touch.index == _pinch_idx_a or touch.index == _pinch_idx_b:
				_end_pinch()
			if _active_touches.is_empty():
				_aim_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _active_touches.has(drag.index):
			return
		_active_touches[drag.index] = drag.position
		if _pinch_idx_a >= 0 and (drag.index == _pinch_idx_a or drag.index == _pinch_idx_b):
			_update_pinch()
			get_viewport().set_input_as_handled()
			return
		if _aim_dragging and _pinch_idx_a < 0:
			var screen := AimControl.touch_aim_screen(drag.position)
			var world := get_viewport().get_canvas_transform().affine_inverse() * screen
			_apply_aim_world(world)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMagnifyGesture and _pinch_idx_a < 0:
		## Trackpad pinch (e.g. macOS in-editor testing) — no discrete release, so
		## the override times out via _process()/_magnify_last_ms instead.
		var mag := event as InputEventMagnifyGesture
		_user_zoom_mult = clampf(_user_zoom_mult * mag.factor, PINCH_MULT_MIN, PINCH_MULT_MAX)
		_magnify_last_ms = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _accept_mouse():
		if event.pressed:
			_aim_dragging = true
			_apply_aim_world(_world_mouse())
		else:
			_aim_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _aim_dragging and _accept_mouse():
		_apply_aim_world(_world_mouse())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var moved := false
		match event.physical_keycode:
			KEY_LEFT, KEY_A:
				_nudge_aim(Vector2(-AIM_NUDGE_PX, 0))
				moved = true
			KEY_RIGHT, KEY_D:
				_nudge_aim(Vector2(AIM_NUDGE_PX, 0))
				moved = true
			KEY_UP, KEY_W:
				_nudge_aim(Vector2(0, -AIM_NUDGE_PX))
				moved = true
			KEY_DOWN, KEY_S:
				_nudge_aim(Vector2(0, AIM_NUDGE_PX))
				moved = true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_confirm_aim()
				get_viewport().set_input_as_handled()
				return
		if moved:
			get_viewport().set_input_as_handled()


func _on_shot_ready(result: ShotResult) -> void:
	strokes += 1
	GameState.record_stroke()
	_update_hud()
	ball_in_flight = true
	_power_previewing = false
	_set_aim_visuals_visible(false)
	if _change_club_btn:
		_change_club_btn.visible = false
	_refresh_wind_indicator(false)
	var lie_at_strike := ball.get_lie()
	_set_green_book_visible(false)
	if lie_at_strike == "Green":
		AudioBus.play_putt()
	else:
		AudioBus.play_contact(result.contact_label())
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	var aim_offset := AimControl.aim_offset_label(ball.global_position, _aim_target, _cup_pos)
	var wind_note := ""
	if wind.length() >= 4.0 and lie_at_strike != "Green":
		wind_note = "Wind was active — landing may drift from aim circle"
	_last_result = result
	var sev_at_strike := ball.get_lie_severity()
	_last_report = ShotReport.from_shot(
		result,
		shot_routine.club_name,
		shot_routine.club_max_yards,
		lie_at_strike,
		_aim_radius_yd,
		aim_offset,
		wind_note,
		sev_at_strike
	)
	GameState.last_shot_metrics = {
		"power": result.power,
		"stability": result.stance_stability,
		"path_error": result.path_error,
		"contact": result.contact_label(),
		"club": shot_routine.club_name,
		"lie": lie_at_strike,
		"severity": sev_at_strike,
		"planned_yd": _last_report.planned_yards,
		"summary": _last_report.summary_line(),
		"aim_radius_yd": _aim_radius_yd,
		"aim_offset": aim_offset,
		"form": GameState.get_form(),
		"shot_type": shot_routine.flight_shot_type(),
		"punch": shot_routine.punch_mode,
	}
	# Full-shot flight owns the screen (up-and-in + tracer); glance waits for settle.
	# Putts stay short — keep the live glance.
	if _is_putt_context() and shot_result_panel and shot_result_panel.has_method("show_launch"):
		shot_result_panel.show_launch(_last_report)
	var slope: Vector2 = course_root.get_meta("slope", hole.green_slope)
	ball.launch(
		result, _aim_target, shot_routine.club_max_yards, wind, slope, hole, _green_center,
		shot_routine.flight_shot_type()
	)
	_follow_ball()
	# Panel owns the glance — don't stack the same tempo text on Feedback.
	if result.is_perfect() and result.stance_stability >= 0.72:
		feedback.text = "PURE"
		feedback.modulate = Color(1.0, 0.92, 0.35)
		_pulse_pure_label()
	else:
		feedback.text = ""
		feedback.modulate = Color(0.9, 0.9, 0.9)


func _on_pure_strike(_result: ShotResult) -> void:
	## Slow-mo + flash + haptic. Zoom owned by up-and-in flight camera (don't fight it).
	if ball.get_lie() == "Green":
		AudioBus.play_putt_pure()
	else:
		AudioBus.play_pure()
	GameState.record_pure_strike()
	# ponytail: one sharp pulse for pure; scale duration by contact quality after playtest
	Input.vibrate_handheld(22)
	Engine.time_scale = 0.55
	flash_rect.color = Color(1.0, 0.95, 0.55, 1.0)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(flash_rect, "modulate:a", 0.55, 0.04)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.18)
	tw.tween_interval(0.22)
	tw.tween_callback(func(): Engine.time_scale = 1.0)


func _pulse_pure_label() -> void:
	var tw := create_tween()
	tw.tween_property(feedback, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(feedback, "scale", Vector2.ONE, 0.18)


func _pin_yards() -> float:
	return BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))


func _desired_camera_zoom() -> Vector2:
	## Higher zoom = closer. Fit green into portrait for putts; corridor-owned for full shots.
	var pin_yd := _pin_yards()
	var view := get_viewport().get_visible_rect().size
	var view_min := minf(view.x, view.y)
	var z: float
	if _is_putt_context():
		# Frame ball→cup; zoom out sooner on lags so 40 ft reads as travel, not a short lag.
		# Floor/cap tuned so short putts (<~10 ft) actually read tighter than 20-40 ft ones —
		# old floor (34) + cap (7.5) together clamped everything under ~70 ft to one flat zoom.
		var dist := ball.global_position.distance_to(_cup_pos)
		var half_span := maxf(dist * 0.90 + 6.0, 12.0)
		z = clampf(view_min * 0.52 / half_span, 2.6, 42.0)
	else:
		# Full / approach: zoom so fairway + side belts own ~half the portrait width
		# (not a needle fairway in an ocean of mid-rough).
		var z_cor := _corridor_zoom_level()
		if _aiming and _should_show_green_book():
			# Slightly wider so book + landing stay readable
			z = lerpf(z_cor * 0.92, z_cor * 0.78, clampf((pin_yd - 28.0) / 52.0, 0.0, 1.0))
		elif pin_yd <= 90.0:
			z = lerpf(z_cor * 1.08, z_cor, clampf((pin_yd - 28.0) / 62.0, 0.0, 1.0))
		else:
			# Long tee: a touch wider for aim cone, still corridor-first
			z = z_cor * 0.88
	# Pinch-to-zoom override — aim phase only; auto-framing owns zoom everywhere else.
	if _aiming and _user_zoom_mult != 1.0:
		z = clampf(z * _user_zoom_mult, PINCH_ABS_ZOOM_MIN, PINCH_ABS_ZOOM_MAX)
	return Vector2(z, z)


func _desired_camera_look() -> Vector2:
	if _is_putt_context():
		var focus := ball.global_position.lerp(_cup_pos, 0.55)
		if _aiming:
			focus = focus.lerp(_aim_target, 0.2)
		return focus
	if _aiming and _should_show_green_book():
		# Bias toward green so the book is on-screen with the landing circle
		var mid := ball.global_position.lerp(_aim_target, 0.4)
		return mid.lerp(_green_center, 0.35)
	if _aiming:
		return ball.global_position.lerp(_aim_target, 0.45)
	return ball.global_position


func _flight_camera_zoom() -> Vector2:
	## Mild open through apex; snap tighter than aim on descent (TV "up and in").
	## Scales from _flight_zoom_base so corridor aim never jumps to an old absolute wide shot.
	var t := ball.air_progress()
	var z: float
	if ball.state == GolfBall.State.ROLL or t >= 1.0:
		z = _flight_z_land()
	elif t < FLIGHT_ZOOM_IN_START:
		z = lerpf(_flight_z_launch(), _flight_z_apex(), t / FLIGHT_ZOOM_IN_START)
	else:
		var u := (t - FLIGHT_ZOOM_IN_START) / maxf(1.0 - FLIGHT_ZOOM_IN_START, 0.01)
		z = lerpf(_flight_z_apex(), _flight_z_land(), u)
	return Vector2(z, z)


func _lock_putt_camera() -> void:
	## Capture ball→cup framing before the ball moves; hold it for the whole roll.
	_putt_cam_active = true
	_putt_cam_zoom = _desired_camera_zoom()
	_putt_cam_look = _desired_camera_look()


func _clear_putt_camera_lock() -> void:
	_putt_cam_active = false


func _follow_ball() -> void:
	## Smoothing fights the up-and-in punch — own the transform directly in flight.
	camera.position_smoothing_enabled = false
	if _is_putt_context():
		_lock_putt_camera()
		var tw_p := create_tween()
		# Ease into locked mid-frame — not ball-only (that yanked short putts).
		tw_p.tween_property(camera, "global_position", _putt_cam_look, 0.18).set_trans(Tween.TRANS_SINE)
		tw_p.parallel().tween_property(camera, "zoom", _putt_cam_zoom, 0.2)
		return
	# Capture pre-shot framing; flight fracs open slightly then land tighter than aim.
	_flight_zoom_base = maxf(camera.zoom.x, _corridor_zoom_level() * 0.9)
	var z := Vector2(_flight_z_launch(), _flight_z_launch())
	var tw := create_tween()
	tw.tween_property(camera, "global_position", ball.global_position, 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(camera, "zoom", z, 0.2)


func _refresh_hole_map() -> void:
	if _hole_map == null or hole == null:
		return
	var cl := PackedVector2Array()
	for i in 17:
		var a := float(i) / 16.0
		cl.append(_fairway_center_at(a))
	var tees: Array = []
	for p in _tee_pads:
		tees.append({
			"pos": p["pos"],
			"set": p["set"],
			"active": p["set"] == _active_tee,
		})
	_hole_map.configure(
		hole,
		_green_center,
		_cup_pos,
		_fairway_half,
		cl,
		_bunkers,
		_trees,
		tees,
		ball.global_position if ball else _tee_pos
	)


func _process(_delta: float) -> void:
	_sync_pin_flag_visible()
	_update_pin_flag_wind()
	if _hole_map and ball:
		_hole_map.set_ball(ball.global_position)
	if ball_in_flight and ball.state != GolfBall.State.SETTLED and ball.state != GolfBall.State.IDLE:
		if _is_putt_context() and _putt_cam_active:
			# Hold stroke-start zoom; soft drift toward the ball so it can leave center.
			var look := _putt_cam_look.lerp(ball.global_position, PUTT_ROLL_BALL_WEIGHT)
			camera.global_position = camera.global_position.lerp(look, PUTT_ROLL_LOOK_LERP)
			camera.zoom = camera.zoom.lerp(_putt_cam_zoom, PUTT_ROLL_ZOOM_LERP)
		else:
			var look := ball.global_position
			if ball.velocity.length() > 20.0:
				var tight := inverse_lerp(_flight_z_launch(), _flight_z_land(), camera.zoom.x)
				var lead := lerpf(FLIGHT_LOOK_LEAD_WIDE, FLIGHT_LOOK_LEAD_TIGHT, clampf(tight, 0.0, 1.0))
				look += ball.velocity.normalized() * lead
			camera.global_position = camera.global_position.lerp(look, 0.18)
			var target_zoom := _flight_camera_zoom()
			# Aggressive zoom lerp on the "in" beat / roll so short flights still punch tight.
			var z_lerp := 0.12
			if ball.state == GolfBall.State.ROLL or ball.air_progress() >= FLIGHT_ZOOM_IN_START:
				z_lerp = 0.35
			camera.zoom = camera.zoom.lerp(target_zoom, z_lerp)
	elif _aiming:
		if _magnify_last_ms >= 0 and Time.get_ticks_msec() - _magnify_last_ms > MAGNIFY_IDLE_RELEASE_MS:
			_user_zoom_mult = 1.0
			_magnify_last_ms = -1
		# Snap-feel aim follow (faster) so book/zoom don't crawl in
		camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.28)
		camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.28)
		_sync_screen_line_widths()
	elif shot_routine and shot_routine.visible:
		camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.18)
		camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.18)
		_sync_screen_line_widths()
	elif not ball_in_flight:
		# Hold land framing while the glance/result panel is up so the "in" punch isn't undone.
		if shot_result_panel and shot_result_panel.visible and not _is_putt_context():
			camera.global_position = camera.global_position.lerp(ball.global_position, 0.12)
			var z_land := _flight_z_land()
			camera.zoom = camera.zoom.lerp(Vector2(z_land, z_land), 0.16)
		else:
			camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.08)
			camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.08)


func _on_ball_settled(pos: Vector2, lie_hint: String) -> void:
	if hole_complete:
		return
	if lie_hint == "Water" or lie_hint == "OOB":
		_clear_putt_camera_lock()
		return
	ball_in_flight = false
	_clear_putt_camera_lock()
	_set_green_book_visible(false)
	var actual := ball.distance_traveled_yards()
	# Holed shots short-circuit below before _last_report.set_actual — record here so
	# a made putt (the one "longest putt" actually cares about) isn't dropped.
	var holed := pos.distance_to(_cup_pos) < CUP_RADIUS and not GameState.range_mode
	if _last_result and _last_report:
		GameState.club_coach.record(_last_report.club_name, _last_result, GameState.last_tempo_metrics, actual, holed)
	if GameState.green_mode and holed:
		_on_practice_green_holed()
		return
	if not GameState.range_mode and not GameState.green_mode and holed:
		_on_holed_out()
		return
	if GameState.range_mode:
		ball.set_lie("Tee")
	elif GameState.green_mode:
		ball.set_lie("Green")
	else:
		ball.set_lie(_classify_lie(pos))
	_update_hud()
	if _last_report:
		_last_report.set_actual(actual)
		GameState.last_shot_metrics["actual_yd"] = actual
		GameState.last_shot_metrics["summary"] = _last_report.glance_text()
		# Apex debug for tree-carry playtest (same units as canopy_h).
		GameState.last_shot_metrics["height_peak"] = ball.flight_height_peak()
		GameState.last_shot_metrics["height_max"] = ball.flight_height_max()
		# Panel owns the report; clearing Feedback avoids the stacked double-text bug.
		feedback.text = ""
		if shot_result_panel and shot_result_panel.has_method("show_final"):
			shot_result_panel.show_final(_last_report)
			if not shot_result_panel.dismissed.is_connected(_on_shot_report_dismissed):
				shot_result_panel.dismissed.connect(_on_shot_report_dismissed, CONNECT_ONE_SHOT)
			return
	else:
		feedback.text = "Stopped  %d yd" % int(actual)
	feedback.modulate = Color(0.85, 0.9, 0.8)
	_after_shot_continue()


func _on_shot_report_dismissed() -> void:
	feedback.modulate = Color(0.85, 0.9, 0.8)
	_after_shot_continue()


func _after_shot_continue() -> void:
	if hole_complete or not GameState.run_active:
		return
	if GameState.range_mode:
		ball.reset_at(_tee_pos, "Tee")
		camera.global_position = Vector2(_tee_pos.x, _tee_pos.y - 120)
		_set_aim_visuals_visible(false)
		_start_shot_ui()
		return
	if GameState.green_mode:
		_reset_practice_green()
		return
	_start_shot_ui()


func _reset_practice_green() -> void:
	ball.reset_at(_practice_green_pos, "Green")
	camera.global_position = Vector2(_practice_green_pos.x, _practice_green_pos.y - 40)
	camera.zoom = Vector2(2.2, 2.2)
	_set_aim_visuals_visible(false)
	_update_hud()
	_start_shot_ui()


func _on_practice_green_holed() -> void:
	## Sink juice, then reset — no scoring / hole advance.
	ball_in_flight = false
	_end_aim_phase()
	shot_routine.set_active(false)
	AudioBus.play_putt_drop()
	feedback.text = "IN THE HOLE"
	feedback.modulate = Color(1.0, 0.95, 0.5)
	_update_hud()
	var cam_tw := create_tween()
	cam_tw.tween_property(camera, "global_position", _cup_pos, 0.15)
	cam_tw.parallel().tween_property(camera, "zoom", Vector2(4.5, 4.5), 0.12)
	await get_tree().create_timer(0.7).timeout
	if GameState.green_mode and GameState.run_active:
		_reset_practice_green()


func _classify_lie(pos: Vector2) -> String:
	for tr in _trees:
		if pos.distance_to(tr["c"]) <= float(tr["r"]):
			return "Trees"
	for b in _bunkers:
		# Cheap reject on design radius; opaque sand pixels are the real gate.
		if pos.distance_to(b["c"]) > float(b["r"]) * 1.15:
			continue
		if _on_painted_sand(pos, b):
			return "Sand"
	if _on_painted_green(pos):
		return "Green"
	# Any teeing ground (Blue / White / Red pads)
	for p in _tee_pads:
		var r: Rect2 = p.get("rect", Rect2())
		if r.size != Vector2.ZERO and r.has_point(pos):
			return "Tee"
		var tp: Vector2 = p["pos"]
		if absf(pos.x - tp.x) <= 26.0 and absf(pos.y - tp.y) <= 28.0:
			return "Tee"
	# Was a fixed green-end x offset regardless of the ball's y — read through
	# _fairway_center_at() instead so this tracks the real centerline (matters
	# for bent fairways in general, and is load-bearing for sharp-dogleg mode).
	var along := clampf(inverse_lerp(GREEN_Y, _tee_back_pos.y, pos.y), 0.0, 1.0)
	var fx := absf(pos.x - _fairway_center_at(along).x)
	if fx <= _fairway_half + 20.0:
		return "Fairway"
	if fx <= _fairway_half + 80.0:
		return "Rough"
	return "Rough"


func _on_painted_sand(pos: Vector2, bunker: Dictionary) -> bool:
	## Painted bunker alpha (blob/crescent/cluster) — circle alone over-fires Sand.
	var spr: Sprite2D = bunker.get("sprite") as Sprite2D
	var img: Image = bunker.get("img") as Image
	if spr == null or img == null:
		return pos.distance_to(bunker["c"]) <= float(bunker["r"]) * SAND_COLLISION_FRAC
	var sz := Vector2(float(img.get_width()), float(img.get_height()))
	var sc := spr.scale
	if absf(sc.x) < 0.001 or absf(sc.y) < 0.001:
		return false
	var local := (pos - spr.position) / sc + sz * 0.5
	var ix := int(local.x)
	var iy := int(local.y)
	if ix < 0 or iy < 0 or ix >= int(sz.x) or iy >= int(sz.y):
		return false
	return img.get_pixel(ix, iy).a > 0.5


func _on_painted_green(pos: Vector2) -> bool:
	## Ellipse is a cheap reject; painted alpha is the real silhouette
	## (island beach / L-shape edge cutouts must not count as Green).
	var dx := (pos.x - _green_center.x) / maxf(hole.green_radius_x + 14.0, 1.0)
	var dy := (pos.y - _green_center.y) / maxf(hole.green_radius_y + 14.0, 1.0)
	if dx * dx + dy * dy > 1.0:
		return false
	if _green_img == null or _green_sprite == null:
		return true
	var sz := Vector2(float(_green_img.get_width()), float(_green_img.get_height()))
	var local := (pos - _green_sprite.position) / _green_sprite.scale + sz * 0.5
	var ix := int(local.x)
	var iy := int(local.y)
	if ix < 0 or iy < 0 or ix >= int(sz.x) or iy >= int(sz.y):
		return false
	return _green_img.get_pixel(ix, iy).a > 0.5


func _on_hazard(kind: String) -> void:
	AudioBus.play_splash()
	feedback.text = "WATER +1" if kind == "water" else "OOB +1"
	feedback.modulate = Color(0.4, 0.7, 1.0) if kind == "water" else Color(0.95, 0.5, 0.4)
	ball_in_flight = false
	_clear_putt_camera_lock()
	_set_aim_visuals_visible(false)
	if GameState.range_mode:
		feedback.text = "OOB — try again"
		ball.reset_at(_tee_pos, "Tee")
		_update_hud()
		await get_tree().create_timer(0.45).timeout
		if GameState.range_mode:
			_start_shot_ui()
		return
	if GameState.green_mode:
		feedback.text = "Off green — try again"
		_update_hud()
		await get_tree().create_timer(0.45).timeout
		if GameState.green_mode:
			_reset_practice_green()
		return
	strokes += 1
	GameState.record_stroke()
	ball.reset_at(ball.get_last_safe(), "Fairway")
	_update_hud()
	await get_tree().create_timer(0.55).timeout
	if not hole_complete:
		_start_shot_ui()


func _on_holed_out() -> void:
	if GameState.green_mode:
		_on_practice_green_holed()
		return
	if hole_complete:
		return
	hole_complete = true
	ball_in_flight = false
	_end_aim_phase()
	shot_routine.set_active(false)
	ball.reset_at(_cup_pos, "Green")
	# Soft hole-out: ease into a modest cup hold, then ease out — no jarring 6× punch.
	AudioBus.play_putt_drop()
	var close_z := Vector2(3.15, 3.15)
	var hold_z := Vector2(2.55, 2.55)
	var cam_tw := create_tween()
	cam_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	cam_tw.tween_property(camera, "global_position", _cup_pos, 0.38)
	cam_tw.parallel().tween_property(camera, "zoom", close_z, 0.42)
	cam_tw.tween_property(flash_rect, "modulate:a", 0.18, 0.12)
	cam_tw.tween_property(flash_rect, "modulate:a", 0.0, 0.45)
	cam_tw.tween_interval(0.35)
	cam_tw.set_ease(Tween.EASE_IN_OUT)
	cam_tw.tween_property(camera, "zoom", hold_z, 0.55)
	var diff := strokes - hole.par
	var result := Scoring.result_from_diff(diff)
	GameState.add_score_to_par(diff)
	if GameState.is_stroke_play() and scorecard:
		scorecard.reveal_hole(GameState.hole_scores.size() - 1, diff)
	var life_delta := GameState.apply_hole_result_lives(result)
	_update_hud()
	feedback.text = _hole_result_feedback(result, diff, life_delta)
	feedback.modulate = Color(1.0, 0.95, 0.5)
	if Scoring.is_birdie_or_better(result):
		_show_birdie(result, diff)
		AudioBus.play_golf_clap()
	elif result == Scoring.Result.PAR:
		AudioBus.play_golf_clap()
	# Survival: death sting on lives out / finish. Stroke play: only soft finish on 18.
	var died := GameState.is_survival() and (not GameState.run_active or GameState.lives <= 0)
	var finished := GameState.current_hole >= GameState.HOLE_COUNT
	if died:
		AudioBus.play_water_hazard()
	# Let the soft cam settle before advancing (was 1.1 with snappy zoom).
	await get_tree().create_timer(1.55).timeout
	if GameState.is_survival() and (not GameState.run_active or GameState.lives <= 0):
		request_game_over.emit()
		return
	if finished:
		GameState.end_run("course_complete")
		request_game_over.emit()
		return
	request_next_hole.emit()


func _hole_result_feedback(result: Scoring.Result, diff: int, life_delta: int) -> String:
	var label := Scoring.label(result)
	if GameState.is_stroke_play():
		return "IN THE HOLE  ·  %s (%+d)" % [label, diff]
	var life_txt := ""
	if life_delta > 0:
		life_txt = "  +%d life" % life_delta
	elif life_delta < 0:
		life_txt = "  %d life" % life_delta
	return "IN THE HOLE  ·  %s (%+d)%s" % [label, diff, life_txt]


func _show_birdie(result: Scoring.Result = Scoring.Result.BIRDIE, diff: int = -1) -> void:
	birdie_label.visible = true
	birdie_label.modulate.a = 0.0
	if GameState.is_stroke_play():
		birdie_label.text = "%s (%+d)" % [Scoring.label(result).to_upper(), diff]
	else:
		birdie_label.text = "BIRDIE MOMENTUM  +1 LIFE"
	var tw := create_tween()
	tw.tween_property(birdie_label, "modulate:a", 1.0, 0.15)
	tw.tween_property(flash_rect, "modulate:a", 0.45, 0.08)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.35)
	tw.tween_interval(0.5)
	tw.tween_property(birdie_label, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): birdie_label.visible = false)


func _on_perfect_flash() -> void:
	ball.flash_perfect()
	var tw := create_tween()
	flash_rect.color = Color(1.0, 0.92, 0.4, 1.0)
	tw.tween_property(flash_rect, "modulate:a", 0.35, 0.05)
	tw.parallel().tween_property(camera, "zoom", Vector2(0.9, 0.9), 0.08)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.28)
	tw.parallel().tween_property(camera, "zoom", Vector2(0.85, 0.85), 0.22)


func _update_hud() -> void:
	if hud == null:
		return
	if GameState.range_mode and hud.has_method("refresh_range"):
		hud.refresh_range(strokes)
	elif GameState.green_mode and hud.has_method("refresh_practice_green"):
		hud.refresh_practice_green(strokes)
	elif hud.has_method("refresh"):
		hud.refresh(hole, strokes)


func _on_run_ended(_deepest: int, _reason: String) -> void:
	_end_aim_phase()
	shot_routine.set_active(false)


func skip_hole() -> void:
	if GameState.in_practice():
		return
	if hole_complete:
		return
	_end_aim_phase()
	strokes = hole.par
	GameState.strokes_this_hole = hole.par
	_on_holed_out()


func debug_force_shot(perfect: bool) -> void:
	if ball_in_flight or hole_complete:
		return
	if GameState.range_mode and not shot_routine.visible:
		if _selecting_club:
			return
		_begin_range_swing()
	elif _aiming:
		_confirm_aim()
	shot_routine.force_result(perfect)

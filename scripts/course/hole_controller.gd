class_name HoleController
extends Node2D

signal request_game_over
signal request_next_hole

const GREEN_Y := -80.0
## Legacy span used to convert old absolute hazard Y → fraction along tee→green.
const _LEGACY_SPAN := 940.0
const AIM_NUDGE_PX := 14.0
## Catch / draw radius. ~7px ≈ playable (not real 4.25"); was 14px + ball Area → magnetized.
const CUP_RADIUS := 7.0

const TEX_ROUGH := preload("res://assets/terrain/rough_tile_a.png")
const TEX_ROUGH_DARK := preload("res://assets/terrain/rough_tile_b.png")
const TEX_FAIRWAY := preload("res://assets/terrain/fairway_tile_a.png")
const TEX_WATER := preload("res://assets/terrain/water_tile.png")
const TEX_CUP := preload("res://assets/greens/cup.png")
const TEX_PIN_FLAG := preload("res://assets/greens/pin_flag.png")
const TEX_FOG := preload("res://assets/background/fog_overlay.png")
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
]
var hole: HoleData
var strokes: int = 0
var ball_in_flight: bool = false
var hole_complete: bool = false
var _cup_pos: Vector2 = Vector2.ZERO
var _green_center: Vector2 = Vector2.ZERO
var _tee_pos: Vector2 = Vector2(540, 860.0)
var _fairway_half: float = 70.0
var _bunkers: Array = []  ## {c: Vector2, r: float} — for settle lie
var _green_book: Node2D  ## aim-only yardage-book overlay (height heat)

var _aiming: bool = false
var _selecting_club: bool = false
var _power_previewing: bool = false
var _aim_dragging: bool = false
var _practice_btn: Button
var _aim_target: Vector2 = Vector2.ZERO
var _aim_radius_yd: float = 22.0
var _aim_radius_base_yd: float = 22.0
var _aim_lock_yards: float = 160.0
var _chosen_club: Dictionary = {}
var _aim_cone: Polygon2D
var _aim_cone_edge: Line2D
var _pin_ref_line: Line2D
var _aim_circle: Line2D
var _wind_bias: Line2D
var _wind_flag: WindFlag
var _last_report: ShotReport
var _club_select: ClubSelect

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
	_setup_practice_btn()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	UiScale.apply_hole_safe_area(
		hud, feedback, _wind_flag, shot_routine, confirm_aim_btn, shot_result_panel
	)
	if wind_banner:
		wind_banner.visible = false


func _setup_club_select() -> void:
	_club_select = ClubSelect.new()
	_club_select.name = "ClubSelect"
	ui_layer.add_child(_club_select)
	# Below shot panel / result, above feedback
	ui_layer.move_child(_club_select, confirm_aim_btn.get_index())
	_club_select.club_chosen.connect(_on_club_chosen)


func _setup_aim_visuals() -> void:
	_pin_ref_line = Line2D.new()
	_pin_ref_line.width = 2.0
	_pin_ref_line.default_color = Color(1.0, 1.0, 1.0, 0.22)
	_pin_ref_line.z_index = 4
	_pin_ref_line.visible = false
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
	GameState.exit_range_mode()
	_end_aim_phase()
	hole = GameState.get_hole(hole_index)
	GameState.begin_hole(hole_index)
	strokes = 0
	GameState.strokes_this_hole = 0
	hole_complete = false
	ball_in_flight = false
	_build_course()
	ball.reset_at(_tee_pos, "Tee")
	camera.global_position = Vector2(_tee_pos.x, _tee_pos.y - 120)
	if not camera.is_current():
		camera.make_current()
	_update_hud()
	_start_shot_ui()


func load_range() -> void:
	## Flat fairway tee — swing practice, no aim phase, infinite reset.
	_end_aim_phase()
	GameState.enter_range_mode()
	hole = _make_range_hole()
	strokes = 0
	hole_complete = false
	ball_in_flight = false
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


func _make_range_hole() -> HoleData:
	var d := HoleData.new()
	d.hole_number = 0
	d.par = 4
	d.fairway_width = 240.0
	d.green_radius_x = 36.0
	d.green_radius_y = 36.0
	d.pin_offset = Vector2.ZERO
	d.tee_offset_x = 0.0
	d.fairway_bend = 0.0
	d.wind_vector = Vector2.ZERO
	d.green_slope = Vector2.ZERO
	d.timing_window_scale = 1.0
	d.has_bunker = false
	d.has_water = false
	d.hazard_bias = HoleData.HazardBias.NONE
	d.suggested_shape = HoleData.SuggestedShape.STRAIGHT
	d.name_label = "RANGE"
	d.archetype = "range"
	d.yardage = 420.0
	return d


func _build_course() -> void:
	for c in course_root.get_children():
		c.queue_free()
	if _green_book:
		_green_book.queue_free()
		_green_book = null
	_bunkers.clear()

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

	var tee_y := GREEN_Y + BallPhysics.yards_to_pixels(maxf(hole.yardage, 80.0))
	_tee_pos = Vector2(540.0 + hole.tee_offset_x, tee_y)
	_green_center = Vector2(540.0, GREEN_Y)
	_cup_pos = _green_center + hole.pin_offset
	var course_len := (tee_y - GREEN_Y) + 180.0

	# Rough apron
	_add_rect(course_root, Rect2(0, GREEN_Y - 140, 1080, course_len + 220), Color(0.92, 0.98, 0.92), "", TEX_ROUGH, 340.0)

	# Bent / shaped fairway
	_add_bent_fairway(fairway_w, hole.fairway_bend)

	# Green sprite (variant per layout) + detection area
	_add_green(hole.green_radius_x + 14.0, hole.green_radius_y + 14.0)

	_add_circle(course_root, _cup_pos, CUP_RADIUS, Color(0, 0, 0, 0), "cup")
	var cup_spr := Sprite2D.new()
	cup_spr.texture = TEX_CUP
	cup_spr.position = _cup_pos
	cup_spr.scale = Vector2.ONE * ((CUP_RADIUS * 2.0) / float(TEX_CUP.get_width()))
	cup_spr.z_index = 2
	course_root.add_child(cup_spr)

	var flag_spr := Sprite2D.new()
	flag_spr.texture = TEX_PIN_FLAG
	flag_spr.centered = false
	# Anchor the pole base (x ≈ 10% into the texture) at the cup
	flag_spr.offset = Vector2(-float(TEX_PIN_FLAG.get_width()) * 0.101, -float(TEX_PIN_FLAG.get_height()))
	flag_spr.position = _cup_pos + Vector2(0, -4)
	flag_spr.scale = Vector2.ONE * (68.0 / float(TEX_PIN_FLAG.get_height()))
	flag_spr.z_index = 3
	course_root.add_child(flag_spr)

	_place_layout_hazards(adapt_bias)

	_add_rect(course_root, Rect2(-80, GREEN_Y - 140, 70, course_len + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_add_rect(course_root, Rect2(1090, GREEN_Y - 140, 70, course_len + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_scatter_trees()
	_add_fog_band()
	_add_circle(course_root, _tee_pos, 8.0, Color(0.95, 0.95, 0.2), "")

	_build_green_book()


func _add_bent_fairway(width: float, bend: float) -> void:
	## Trapezoid / dogleg strip from tee to green.
	var half := width * 0.5
	var tee_y := _tee_pos.y
	var top := Vector2(540.0 + bend * 0.35, GREEN_Y - 20.0)
	var mid := Vector2(540.0 + bend, tee_y * 0.45 + GREEN_Y * 0.55)
	var bot := Vector2(_tee_pos.x, tee_y - 20.0)
	var poly := Polygon2D.new()
	poly.color = Color(1, 1, 1)
	poly.texture = TEX_FAIRWAY
	poly.texture_scale = Vector2.ONE * (float(TEX_FAIRWAY.get_width()) / 300.0)
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.polygon = PackedVector2Array([
		bot + Vector2(-half, 0),
		mid + Vector2(-half * 0.85, 0),
		top + Vector2(-half * 0.7, 0),
		top + Vector2(half * 0.7, 0),
		mid + Vector2(half * 0.85, 0),
		bot + Vector2(half, 0),
	])
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
	## 0 = green, 1 = tee. Fracs from legacy absolute Y / _LEGACY_SPAN.
	return lerpf(GREEN_Y, _tee_pos.y, frac)


func _place_layout_hazards(adapt_bias: HoleData.HazardBias) -> void:
	var side := 1.0
	if adapt_bias == HoleData.HazardBias.LEFT:
		side = -1.0
	elif adapt_bias == HoleData.HazardBias.RIGHT:
		side = 1.0

	var place_bunker := hole.has_bunker
	var place_water := hole.has_water
	var h_scale := clampf((_tee_pos.y - GREEN_Y) / _LEGACY_SPAN, 0.35, 1.35)

	var water_tint := Color(1, 1, 1, 0.92)
	match hole.layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			if place_bunker:
				_add_bunker(Vector2(540 + 110, _y_at(460.0 / _LEGACY_SPAN)), 50.0, 0)
			if place_water:
				_add_rect(
					course_root,
					Rect2(700, _y_at(280.0 / _LEGACY_SPAN), 90, 180.0 * h_scale),
					water_tint, "water", TEX_WATER, 260.0
				)
		HoleData.LayoutStyle.DOGLEG_LEFT:
			if place_bunker:
				_add_bunker(Vector2(540 - 120, _y_at(440.0 / _LEGACY_SPAN)), 55.0, 1)
			if place_water:
				_add_rect(
					course_root,
					Rect2(200, _y_at(240.0 / _LEGACY_SPAN), 100, 220.0 * h_scale),
					water_tint, "water", TEX_WATER, 260.0
				)
		HoleData.LayoutStyle.CHUTE:
			if place_water:
				var chute_y := _y_at(330.0 / _LEGACY_SPAN)
				var chute_h := 280.0 * h_scale
				_add_rect(course_root, Rect2(540 - _fairway_half - 70, chute_y, 55, chute_h), water_tint, "water", TEX_WATER, 260.0)
				_add_rect(course_root, Rect2(540 + _fairway_half + 15, chute_y, 55, chute_h), water_tint, "water", TEX_WATER, 260.0)
			if place_bunker:
				_add_bunker(Vector2(540 + 40, _y_at(200.0 / _LEGACY_SPAN)), 36.0, 2)
		HoleData.LayoutStyle.ISLAND:
			# Keep water outside green detection + ball Area sensor (10px).
			# Fixed (540±70) rects used to overlap the putting surface on early/large greens.
			var clear := maxf(hole.green_radius_x, hole.green_radius_y) + 14.0 + 12.0
			var side_w := 90.0
			var side_h := 160.0
			var side_y := GREEN_Y - 30.0
			_add_rect(course_root, Rect2(540.0 - clear - side_w, side_y, side_w, side_h), water_tint, "water", TEX_WATER, 260.0)
			_add_rect(course_root, Rect2(540.0 + clear, side_y, side_w, side_h), water_tint, "water", TEX_WATER, 260.0)
			_add_rect(course_root, Rect2(540.0 - 100.0, GREEN_Y + clear, 200.0, 70.0), water_tint, "water", TEX_WATER, 260.0)
			if place_bunker:
				_add_bunker(Vector2(540 + side * 90, _y_at(380.0 / _LEGACY_SPAN)), 40.0, 0)
		HoleData.LayoutStyle.BI_TIER:
			if place_bunker:
				_add_bunker(Vector2(540 + 80, _y_at(280.0 / _LEGACY_SPAN)), 48.0, 1)
			if place_water:
				_add_rect(
					course_root,
					Rect2(300, _y_at(220.0 / _LEGACY_SPAN), 80, 200.0 * h_scale),
					water_tint, "water", TEX_WATER, 260.0
				)
		_:
			if place_bunker and hole.hole_number >= 2:
				_add_bunker(Vector2(540 + side * (_fairway_half + 36), _y_at(400.0 / _LEGACY_SPAN)), 42.0, 2)


func _add_bunker(center: Vector2, radius: float, variant: int) -> void:
	var tex: Texture2D = BUNKER_TEXTURES[variant % BUNKER_TEXTURES.size()]
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = center
	var max_dim := maxf(float(tex.get_width()), float(tex.get_height()))
	spr.scale = Vector2.ONE * (radius * 2.3 / max_dim)
	course_root.add_child(spr)
	_bunkers.append({"c": center, "r": radius})
	_add_circle(course_root, center, radius, Color(0, 0, 0, 0), "sand")


func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("trees_%d" % hole.hole_number)
	for strip_x in [-45.0, 1125.0]:
		var y := GREEN_Y - 100.0
		while y < _tee_pos.y + 60.0:
			var tex: Texture2D = TREE_TEXTURES[rng.randi_range(0, TREE_TEXTURES.size() - 1)]
			var spr := Sprite2D.new()
			spr.texture = tex
			var size_px := rng.randf_range(95.0, 150.0)
			spr.scale = Vector2.ONE * (size_px / float(tex.get_width()))
			spr.position = Vector2(strip_x + rng.randf_range(-18.0, 18.0), y)
			spr.rotation = rng.randf_range(-0.25, 0.25)
			spr.z_index = 1
			course_root.add_child(spr)
			y += rng.randf_range(110.0, 190.0)


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
	if _practice_btn:
		_practice_btn.visible = false
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
	_aiming = false
	_aim_dragging = false
	_selecting_club = true
	_set_aim_visuals_visible(false)
	_refresh_wind_indicator(false)
	_set_green_book_visible(false)
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _practice_btn:
		_practice_btn.visible = false
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	feedback.text = "RANGE — pick a club" if GameState.range_mode else "%d yd — pick a club" % int(pin_yd)
	feedback.modulate = Color(0.95, 0.92, 0.7)
	_show_wind_flag(wind)
	_club_select.present(lie, pin_yd, wind)


func _on_club_chosen(club: Dictionary) -> void:
	_selecting_club = false
	_chosen_club = club
	AudioBus.play_ui()
	if GameState.range_mode:
		_begin_range_swing()
	else:
		_begin_aim_phase()


func _begin_range_swing() -> void:
	## Skip aim — fixed center line at recommended carry for the chosen club.
	_aiming = false
	_aim_dragging = false
	if _club_select:
		_club_select.dismiss()
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _practice_btn:
		_practice_btn.visible = false
	_set_green_book_visible(false)
	_refresh_wind_indicator(false)
	var lie := "Tee"
	var club_max := float(_chosen_club.get("max_yards", 180.0))
	var wind: Vector2 = course_root.get_meta("wind", Vector2.ZERO)
	var recommend := BallPhysics.recommended_power(club_max * 0.85, club_max, lie, wind)
	var est := BallPhysics.estimate_carry_yards(recommend, club_max, lie)
	var bearing := _cup_pos - _tee_pos
	if bearing.length_squared() < 1.0:
		bearing = Vector2(0, -1)
	_aim_target = AimControl.point_along_bearing(_tee_pos, bearing, est)
	_aim_radius_base_yd = GameState.get_aim_radius_yards(false)
	_aim_radius_yd = _aim_radius_base_yd
	_aim_lock_yards = est
	_power_previewing = true
	_refresh_aim_visuals()
	_set_aim_visuals_visible(true)
	_start_power_swing(false)


func _begin_aim_phase() -> void:
	_aiming = true
	_aim_dragging = false
	_selecting_club = false
	if _club_select:
		_club_select.dismiss()
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	if _chosen_club.is_empty():
		_chosen_club = BallPhysics.pick_club(pin_yd, lie)
	var club_max := float(_chosen_club["max_yards"])
	_power_previewing = false
	_aim_radius_base_yd = GameState.get_aim_radius_yards(lie == "Green")
	_aim_radius_yd = _aim_radius_base_yd
	_aim_target = AimControl.default_aim_target(ball.global_position, _cup_pos, lie, club_max)
	_aim_target = AimControl.clamp_aim(_aim_target)
	# Lock radial distance during aim — player picks line/shape, not yardage yet.
	_aim_lock_yards = BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	var show_book := _should_show_green_book()
	var is_putt := lie == "Green"
	_set_green_book_visible(show_book)
	if confirm_aim_btn:
		confirm_aim_btn.visible = true
	if _practice_btn:
		_practice_btn.visible = true
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
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
	if _practice_btn:
		_practice_btn.visible = false


func _setup_practice_btn() -> void:
	_practice_btn = Button.new()
	_practice_btn.name = "PracticeSwingButton"
	_practice_btn.text = "Practice Swing"
	_practice_btn.visible = false
	_practice_btn.custom_minimum_size = Vector2(UiScale.TOUCH_MIN * 2.2, UiScale.TOUCH_MIN)
	if confirm_aim_btn:
		_practice_btn.add_theme_font_size_override("font_size", confirm_aim_btn.get_theme_font_size("font_size"))
		# Sit just above Confirm Aim
		_practice_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_practice_btn.offset_left = confirm_aim_btn.offset_left
		_practice_btn.offset_right = confirm_aim_btn.offset_right
		_practice_btn.offset_top = confirm_aim_btn.offset_top - 140.0
		_practice_btn.offset_bottom = confirm_aim_btn.offset_bottom - 140.0
	ui_layer.add_child(_practice_btn)
	_practice_btn.pressed.connect(_start_practice_swing)


func _start_practice_swing() -> void:
	if not _aiming or hole_complete:
		return
	_aiming = false
	_aim_dragging = false
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _practice_btn:
		_practice_btn.visible = false
	_set_green_book_visible(false)
	AudioBus.play_ui()
	_start_power_swing(true)


func _confirm_aim() -> void:
	if not _aiming or hole_complete:
		return
	_aiming = false
	_aim_dragging = false
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	if _practice_btn:
		_practice_btn.visible = false
	_set_green_book_visible(false)  # close the book before stroking
	_refresh_wind_indicator(false)
	AudioBus.play_ui()
	_start_power_swing(false)


func _start_power_swing(p_practice: bool = false) -> void:
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
	shot_routine.configure(
		lie, aim_yd, pin_yd, wind, shape_label, timing, shape_amt, _aim_radius_yd, club_name, club_max
	)
	# Landing preview locked to committed carry (gesture can only subtract).
	_power_previewing = not p_practice
	_apply_committed_preview()
	shot_routine.begin_shot(p_practice)
	if not shot_routine.practice_result.is_connected(_on_practice_result):
		shot_routine.practice_result.connect(_on_practice_result)
	_set_green_book_visible(false)
	if p_practice:
		feedback.text = "Practice — find your tempo"
	elif lie == "Green":
		var pace_yd := BallPhysics.estimate_carry_yards(
			shot_routine.committed_power, club_max, lie
		)
		feedback.text = "Putter · pace %d yd" % int(pace_yd)
	else:
		feedback.text = "%s · nail the tempo" % club_name


func _refresh_putt_pace_feedback() -> void:
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var pace_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_aim_target))
	feedback.text = "Pin %d yd · pace %d" % [int(pin_yd), int(pace_yd)]
	feedback.modulate = Color(0.95, 0.92, 0.7)


func _apply_committed_preview() -> void:
	var lie := ball.get_lie()
	var club_max := float(_chosen_club.get("max_yards", shot_routine.club_max_yards))
	var power := shot_routine.committed_power
	var est := BallPhysics.estimate_carry_yards(power, club_max, lie)
	var from := ball.global_position
	var bearing := _aim_target - from
	if bearing.length_squared() < 1.0:
		bearing = _cup_pos - from
	_aim_target = AimControl.point_along_bearing(from, bearing, est)
	_aim_radius_yd = _aim_radius_base_yd
	_refresh_aim_visuals()


func _on_practice_result(verdict: Dictionary) -> void:
	feedback.text = str(verdict.get("note", "Practice swing"))
	shot_routine.set_active(false)
	_power_previewing = false
	_aiming = true
	if confirm_aim_btn:
		confirm_aim_btn.visible = true
	if _practice_btn:
		_practice_btn.visible = true
	_refresh_aim_visuals()
	var is_putt := ball.get_lie() == "Green"
	if is_putt:
		_refresh_wind_indicator(false)
	else:
		var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
		_show_wind_flag(wind)


func _set_aim_visuals_visible(on: bool) -> void:
	if _aim_cone:
		_aim_cone.visible = on
	if _aim_cone_edge:
		_aim_cone_edge.visible = on
	if _pin_ref_line:
		_pin_ref_line.visible = on
	if _aim_circle:
		_aim_circle.visible = on
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


func _refresh_aim_visuals() -> void:
	var from := ball.global_position
	var to := _aim_target
	var inv_z := 1.0 / maxf(camera.zoom.x, 0.35)
	var cone: Dictionary = AimControl.make_aim_cone(
		from, to, _aim_shape_bend(), 42.0 * inv_z, 16.0 * inv_z, _power_previewing
	)
	_aim_cone.polygon = cone["points"]
	_aim_cone.vertex_colors = cone["colors"]
	# Soft edge stroke along the wedge flanks (skip the near-ball base).
	var edge := PackedVector2Array()
	var pts: PackedVector2Array = cone["points"]
	if pts.size() >= 6:
		edge.append(pts[0])
		edge.append(pts[5])
		edge.append(pts[4])
		edge.append(pts[3])
		edge.append(pts[2])
		edge.append(pts[1])
	_aim_cone_edge.points = edge
	_aim_cone_edge.width = (2.4 if _power_previewing else 1.8) / maxf(camera.zoom.x, 0.35)
	_aim_cone_edge.default_color = Color(1.0, 0.92, 0.4, 0.55 if _power_previewing else 0.28)
	_pin_ref_line.points = PackedVector2Array([from, _cup_pos])
	var radius_px := BallPhysics.yards_to_pixels(_aim_radius_yd)
	_aim_circle.points = AimControl.make_circle_points(to, radius_px)
	_aim_circle.default_color = Color(1.0, 0.92, 0.35, 0.95 if _power_previewing else 0.85)
	_set_aim_visuals_visible(true)
	if _aiming:
		var is_putt := ball.get_lie() == "Green"
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


func _unhandled_input(event: InputEvent) -> void:
	if not _aiming:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_aim_dragging = true
			var screen := AimControl.touch_aim_screen(touch.position)
			var world := get_viewport().get_canvas_transform().affine_inverse() * screen
			_apply_aim_world(world)
		else:
			_aim_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and _aim_dragging:
		var drag := event as InputEventScreenDrag
		var screen := AimControl.touch_aim_screen(drag.position)
		var world := get_viewport().get_canvas_transform().affine_inverse() * screen
		_apply_aim_world(world)
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
	_last_report = ShotReport.from_shot(
		result,
		shot_routine.club_name,
		shot_routine.club_max_yards,
		lie_at_strike,
		_aim_radius_yd,
		aim_offset,
		wind_note
	)
	GameState.last_shot_metrics = {
		"power": result.power,
		"stability": result.stance_stability,
		"path_error": result.path_error,
		"contact": result.contact_label(),
		"club": shot_routine.club_name,
		"lie": lie_at_strike,
		"planned_yd": _last_report.planned_yards,
		"summary": _last_report.summary_line(),
		"aim_radius_yd": _aim_radius_yd,
		"aim_offset": aim_offset,
		"form": GameState.get_form(),
	}
	if shot_result_panel and shot_result_panel.has_method("show_launch"):
		shot_result_panel.show_launch(_last_report)
	var slope: Vector2 = course_root.get_meta("slope", hole.green_slope)
	ball.launch(result, _aim_target, shot_routine.club_max_yards, wind, slope, hole, _green_center)
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
	## Slow-mo + camera punch + haptic + visual pop (sound-off parity).
	if ball.get_lie() == "Green":
		AudioBus.play_putt_pure()
	else:
		AudioBus.play_pure()
	GameState.record_pure_strike()
	# ponytail: one sharp pulse for pure; scale duration by contact quality after playtest
	Input.vibrate_handheld(22)
	Engine.time_scale = 0.55
	flash_rect.color = Color(1.0, 0.95, 0.55, 1.0)
	var punch := _desired_camera_zoom() * 1.12
	var restore := _desired_camera_zoom()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(flash_rect, "modulate:a", 0.55, 0.04)
	tw.parallel().tween_property(camera, "zoom", punch, 0.06)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.18)
	tw.tween_interval(0.22)
	tw.tween_callback(func(): Engine.time_scale = 1.0)
	tw.tween_property(camera, "zoom", restore, 0.28)


func _pulse_pure_label() -> void:
	var tw := create_tween()
	tw.tween_property(feedback, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(feedback, "scale", Vector2.ONE, 0.18)


func _pin_yards() -> float:
	return BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))


func _desired_camera_zoom() -> Vector2:
	## Higher zoom = closer. Fit green into portrait for putts; moderate for approach book.
	var pin_yd := _pin_yards()
	var view := get_viewport().get_visible_rect().size
	var view_min := minf(view.x, view.y)
	if _is_putt_context():
		var half_span := maxf(
			ball.global_position.distance_to(_cup_pos) * 0.5 + 40.0,
			maxf(hole.green_radius_x, hole.green_radius_y) + 36.0
		)
		var z := clampf(view_min * 0.55 / maxf(half_span, 24.0), 4.0, 10.0)
		return Vector2(z, z)
	# Approach with green book — frame ball toward green without losing landing circle
	if _aiming and _should_show_green_book():
		var z := lerpf(2.0, 1.35, clampf((pin_yd - 28.0) / 52.0, 0.0, 1.0))
		return Vector2(z, z)
	if pin_yd <= 90.0:
		var z := lerpf(1.35, 0.95, clampf((pin_yd - 28.0) / 62.0, 0.0, 1.0))
		return Vector2(z, z)
	return Vector2(0.85, 0.85)


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


func _follow_ball() -> void:
	camera.position_smoothing_enabled = not _is_putt_context()
	var tw := create_tween()
	tw.tween_property(camera, "global_position", ball.global_position, 0.25).set_trans(Tween.TRANS_SINE)
	var z := _desired_camera_zoom()
	if not _is_putt_context():
		z = Vector2(0.72, 0.72)
	tw.parallel().tween_property(camera, "zoom", z, 0.35)


func _process(_delta: float) -> void:
	if ball_in_flight and ball.state != GolfBall.State.SETTLED and ball.state != GolfBall.State.IDLE:
		var look := ball.global_position
		if ball.velocity.length() > 20.0:
			var lead := 40.0 if _is_putt_context() else 80.0
			look += ball.velocity.normalized() * lead
		if _is_putt_context():
			look = look.lerp(_cup_pos, 0.35)
		camera.global_position = camera.global_position.lerp(look, 0.18)
		var target_zoom := _desired_camera_zoom()
		if not _is_putt_context():
			target_zoom = Vector2(0.7, 0.7) if ball.state == GolfBall.State.FLIGHT else Vector2(0.78, 0.78)
		camera.zoom = camera.zoom.lerp(target_zoom, 0.1)
	elif _aiming:
		# Snap-feel aim follow (faster) so book/zoom don't crawl in
		camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.28)
		camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.28)
		_sync_screen_line_widths()
	elif shot_routine and shot_routine.visible:
		camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.18)
		camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.18)
		_sync_screen_line_widths()
	elif not ball_in_flight:
		camera.zoom = camera.zoom.lerp(_desired_camera_zoom(), 0.08)
		camera.global_position = camera.global_position.lerp(_desired_camera_look(), 0.08)


func _on_ball_settled(pos: Vector2, lie_hint: String) -> void:
	if hole_complete:
		return
	if lie_hint == "Water" or lie_hint == "OOB":
		return
	ball_in_flight = false
	_set_green_book_visible(false)
	if not GameState.range_mode and pos.distance_to(_cup_pos) < CUP_RADIUS:
		_on_holed_out()
		return
	if GameState.range_mode:
		ball.set_lie("Tee")
	else:
		ball.set_lie(_classify_lie(pos))
	_update_hud()
	var actual := ball.distance_traveled_yards()
	if _last_report:
		_last_report.set_actual(actual)
		GameState.last_shot_metrics["actual_yd"] = actual
		GameState.last_shot_metrics["summary"] = _last_report.glance_text()
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
	_start_shot_ui()


func _classify_lie(pos: Vector2) -> String:
	for b in _bunkers:
		if pos.distance_to(b["c"]) <= float(b["r"]):
			return "Sand"
	var dx := (pos.x - _green_center.x) / maxf(hole.green_radius_x + 14.0, 1.0)
	var dy := (pos.y - _green_center.y) / maxf(hole.green_radius_y + 14.0, 1.0)
	if dx * dx + dy * dy <= 1.0:
		return "Green"
	var fx := absf(pos.x - (540.0 + hole.fairway_bend * 0.35))
	if fx <= _fairway_half + 20.0:
		return "Fairway"
	if fx <= _fairway_half + 80.0:
		return "Rough"
	return "Rough"


func _on_hazard(kind: String) -> void:
	AudioBus.play_splash()
	feedback.text = "WATER +1" if kind == "water" else "OOB +1"
	feedback.modulate = Color(0.4, 0.7, 1.0) if kind == "water" else Color(0.95, 0.5, 0.4)
	ball_in_flight = false
	_set_aim_visuals_visible(false)
	if GameState.range_mode:
		feedback.text = "OOB — try again"
		ball.reset_at(_tee_pos, "Tee")
		_update_hud()
		await get_tree().create_timer(0.45).timeout
		if GameState.range_mode:
			_start_shot_ui()
		return
	strokes += 1
	GameState.record_stroke()
	ball.reset_at(ball.get_last_safe(), "Fairway")
	_update_hud()
	await get_tree().create_timer(0.55).timeout
	if not hole_complete:
		_start_shot_ui()


func _on_holed_out() -> void:
	if hole_complete:
		return
	hole_complete = true
	ball_in_flight = false
	_end_aim_phase()
	shot_routine.set_active(false)
	ball.reset_at(_cup_pos, "Green")
	# Sink juice — keep a tight cup close-up
	AudioBus.play_putt_drop()
	var cam_tw := create_tween()
	cam_tw.tween_property(camera, "global_position", _cup_pos, 0.2)
	cam_tw.parallel().tween_property(camera, "zoom", Vector2(6.0, 6.0), 0.15)
	cam_tw.tween_property(flash_rect, "modulate:a", 0.4, 0.06)
	cam_tw.tween_property(flash_rect, "modulate:a", 0.0, 0.25)
	cam_tw.tween_property(camera, "zoom", Vector2(4.5, 4.5), 0.35)
	var diff := strokes - hole.par
	var result := Scoring.result_from_diff(diff)
	var life_delta := GameState.apply_hole_result_lives(result)
	_update_hud()
	var life_txt := ""
	if life_delta > 0:
		life_txt = "  +%d life" % life_delta
	elif life_delta < 0:
		life_txt = "  %d life" % life_delta
	feedback.text = "IN THE HOLE  ·  %s (%+d)%s" % [Scoring.label(result), diff, life_txt]
	feedback.modulate = Color(1.0, 0.95, 0.5)
	if Scoring.is_birdie_or_better(result):
		_show_birdie()
		AudioBus.play_birdie()
	elif result == Scoring.Result.PAR:
		AudioBus.play_ui()
	await get_tree().create_timer(1.1).timeout
	if not GameState.run_active or GameState.lives <= 0:
		request_game_over.emit()
		return
	if GameState.current_hole >= GameState.HOLE_COUNT:
		GameState.end_run("course_complete")
		request_game_over.emit()
		return
	request_next_hole.emit()


func _show_birdie() -> void:
	birdie_label.visible = true
	birdie_label.modulate.a = 0.0
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
	elif hud.has_method("refresh"):
		hud.refresh(hole, strokes)


func _on_run_ended(_deepest: int, _reason: String) -> void:
	_end_aim_phase()
	shot_routine.set_active(false)


func skip_hole() -> void:
	if GameState.range_mode:
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

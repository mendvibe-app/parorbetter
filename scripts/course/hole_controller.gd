class_name HoleController
extends Node2D

signal request_game_over
signal request_next_hole

const COURSE_LENGTH := 980.0
const TEE_Y := 860.0
const GREEN_Y := -80.0
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
const WIND_TEXTURES := {
	"light": preload("res://assets/wind/wind_light.png"),
	"medium": preload("res://assets/wind/wind_medium.png"),
	"strong": preload("res://assets/wind/wind_strong.png"),
}

var hole: HoleData
var strokes: int = 0
var ball_in_flight: bool = false
var hole_complete: bool = false
var _cup_pos: Vector2 = Vector2.ZERO
var _green_center: Vector2 = Vector2.ZERO
var _tee_pos: Vector2 = Vector2(540, TEE_Y)
var _fairway_half: float = 70.0
var _bunkers: Array = []  ## {c: Vector2, r: float} — for settle lie
var _green_book: Node2D  ## aim-only yardage-book overlay (heat + slope arrow)

var _aiming: bool = false
var _selecting_club: bool = false
var _power_previewing: bool = false
var _aim_dragging: bool = false
var _aim_target: Vector2 = Vector2.ZERO
var _aim_radius_yd: float = 22.0
var _aim_radius_base_yd: float = 22.0
var _aim_lock_yards: float = 160.0
var _chosen_club: Dictionary = {}
var _aim_cone: Polygon2D
var _aim_cone_edge: Line2D
var _pin_ref_line: Line2D
var _aim_circle: Line2D
var _wind_sprite: Sprite2D
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
	shot_routine.power_stance.updated.connect(_on_power_preview_updated)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	UiScale.apply_hole_safe_area(
		hud, feedback, wind_banner, shot_routine, confirm_aim_btn, shot_result_panel
	)


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

	_wind_sprite = Sprite2D.new()
	_wind_sprite.z_index = 7
	_wind_sprite.visible = false
	add_child(_wind_sprite)


func load_hole(hole_index: int) -> void:
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

	_tee_pos = Vector2(540.0 + hole.tee_offset_x, TEE_Y)
	_green_center = Vector2(540.0, GREEN_Y)
	_cup_pos = _green_center + hole.pin_offset

	# Rough apron
	_add_rect(course_root, Rect2(0, GREEN_Y - 140, 1080, COURSE_LENGTH + 220), Color(0.92, 0.98, 0.92), "", TEX_ROUGH, 340.0)

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

	_add_rect(course_root, Rect2(-80, GREEN_Y - 140, 70, COURSE_LENGTH + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_add_rect(course_root, Rect2(1090, GREEN_Y - 140, 70, COURSE_LENGTH + 240), Color(0.62, 0.5, 0.42), "oob", TEX_ROUGH_DARK, 220.0)
	_scatter_trees()
	_add_fog_band()
	_add_circle(course_root, _tee_pos, 8.0, Color(0.95, 0.95, 0.2), "")

	_build_green_book()


func _add_bent_fairway(width: float, bend: float) -> void:
	## Trapezoid / dogleg strip from tee to green.
	var half := width * 0.5
	var top := Vector2(540.0 + bend * 0.35, GREEN_Y - 20.0)
	var mid := Vector2(540.0 + bend, TEE_Y * 0.45 + GREEN_Y * 0.55)
	var bot := Vector2(_tee_pos.x, TEE_Y - 20.0)
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


func _place_layout_hazards(adapt_bias: HoleData.HazardBias) -> void:
	var side := 1.0
	if adapt_bias == HoleData.HazardBias.LEFT:
		side = -1.0
	elif adapt_bias == HoleData.HazardBias.RIGHT:
		side = 1.0

	var place_bunker := hole.has_bunker
	var place_water := hole.has_water

	var water_tint := Color(1, 1, 1, 0.92)
	match hole.layout:
		HoleData.LayoutStyle.DOGLEG_RIGHT:
			if place_bunker:
				_add_bunker(Vector2(540 + 110, 380), 50.0, 0)
			if place_water:
				_add_rect(course_root, Rect2(700, 200, 90, 180), water_tint, "water", TEX_WATER, 260.0)
		HoleData.LayoutStyle.DOGLEG_LEFT:
			if place_bunker:
				_add_bunker(Vector2(540 - 120, 360), 55.0, 1)
			if place_water:
				_add_rect(course_root, Rect2(200, 160, 100, 220), water_tint, "water", TEX_WATER, 260.0)
		HoleData.LayoutStyle.CHUTE:
			if place_water:
				_add_rect(course_root, Rect2(540 - _fairway_half - 70, 250, 55, 280), water_tint, "water", TEX_WATER, 260.0)
				_add_rect(course_root, Rect2(540 + _fairway_half + 15, 250, 55, 280), water_tint, "water", TEX_WATER, 260.0)
			if place_bunker:
				_add_bunker(Vector2(540 + 40, 120), 36.0, 2)
		HoleData.LayoutStyle.ISLAND:
			# Water ring is the island identity.
			_add_rect(course_root, Rect2(540 - 160, GREEN_Y - 30, 90, 160), water_tint, "water", TEX_WATER, 260.0)
			_add_rect(course_root, Rect2(540 + 70, GREEN_Y - 30, 90, 160), water_tint, "water", TEX_WATER, 260.0)
			_add_rect(course_root, Rect2(540 - 100, GREEN_Y + 90, 200, 70), water_tint, "water", TEX_WATER, 260.0)
			if place_bunker:
				_add_bunker(Vector2(540 + side * 90, 300), 40.0, 0)
		HoleData.LayoutStyle.BI_TIER:
			if place_bunker:
				_add_bunker(Vector2(540 + 80, 200), 48.0, 1)
			if place_water:
				_add_rect(course_root, Rect2(300, 140, 80, 200), water_tint, "water", TEX_WATER, 260.0)
		_:
			if place_bunker and hole.hole_number >= 2:
				_add_bunker(Vector2(540 + side * (_fairway_half + 36), 320), 42.0, 2)


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
		while y < TEE_Y + 60.0:
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

	# Downhill arrow from the shared slope field (replaces marching-squares contours).
	var slope := hole.green_slope_at(Vector2.ZERO)
	if slope.length() > 0.02:
		drawer.arrow_dir = slope.normalized()
		drawer.arrow_len = minf(rx, ry) * 0.38
	drawer.queue_redraw()


class _GreenBookDraw extends Node2D:
	var heat: Array = []
	var arrow_dir: Vector2 = Vector2.ZERO
	var arrow_len: float = 0.0
	var arrow_width: float = 2.4

	func _draw() -> void:
		for h in heat:
			draw_colored_polygon(h["pts"], h["color"])
		if arrow_dir == Vector2.ZERO or arrow_len <= 0.0:
			return
		var tip := arrow_dir * arrow_len
		var base := -arrow_dir * arrow_len * 0.15
		var c := Color(0.08, 0.12, 0.1, 0.78)
		draw_line(base, tip, c, arrow_width, true)
		var across := Vector2(-arrow_dir.y, arrow_dir.x) * arrow_len * 0.18
		draw_line(tip, tip - arrow_dir * arrow_len * 0.22 + across, c, arrow_width, true)
		draw_line(tip, tip - arrow_dir * arrow_len * 0.22 - across, c, arrow_width, true)


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
	if _wind_sprite and _wind_sprite.visible and _wind_sprite.texture:
		_wind_sprite.scale = Vector2.ONE * (110.0 / z / float(_wind_sprite.texture.get_width()))
	if _green_book:
		for c in _green_book.get_children():
			if c is Line2D:
				var target_px := float(c.get_meta("screen_px", 2.2))
				(c as Line2D).width = target_px / z
			elif c is _GreenBookDraw:
				(c as _GreenBookDraw).arrow_width = 2.4 / z
				(c as _GreenBookDraw).queue_redraw()


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
		_begin_aim_phase()
	else:
		_begin_club_select()


func _begin_club_select() -> void:
	_aiming = false
	_aim_dragging = false
	_selecting_club = true
	_set_aim_visuals_visible(false)
	_refresh_wind_indicator(false)
	_set_green_book_visible(false)
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	var lie := ball.get_lie()
	var pin_yd := BallPhysics.pixels_to_yards(ball.global_position.distance_to(_cup_pos))
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	feedback.text = "CLUB  ·  %d yd to pin  ·  pick from the bag" % int(pin_yd)
	feedback.modulate = Color(0.95, 0.92, 0.7)
	if wind_banner:
		wind_banner.visible = true
		wind_banner.text = "%s\n%s" % [AimControl.wind_label(wind), AimControl.wind_aim_hint(wind)]
	_club_select.present(lie, pin_yd, wind)


func _on_club_chosen(club: Dictionary) -> void:
	_selecting_club = false
	_chosen_club = club
	AudioBus.play_ui()
	_begin_aim_phase()


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
	_refresh_aim_visuals()
	var show_book := _should_show_green_book()
	var is_putt := lie == "Green"
	_set_green_book_visible(show_book)
	# Putts: no wind. Approaches: keep wind even with book open.
	_refresh_wind_indicator(not is_putt)
	if confirm_aim_btn:
		confirm_aim_btn.visible = true
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector)
	if wind_banner:
		if is_putt:
			wind_banner.visible = false
		else:
			wind_banner.visible = true
			var wind_txt := AimControl.wind_label(wind)
			var wind_advice := AimControl.wind_aim_hint(wind)
			if show_book:
				wind_banner.text = "%s\n%s\nGreen book open — read the break" % [wind_txt, wind_advice]
			else:
				wind_banner.text = "%s\n%s" % [wind_txt, wind_advice]
	var club_bit := String(_chosen_club.get("name", ""))
	if is_putt:
		feedback.text = "READ THE GREEN  ○%d yd — drag aim, then Confirm" % int(_aim_radius_yd)
	elif show_book:
		feedback.text = "%s  ·  AIM + GREEN READ  ○%d yd — drag line/shape, Confirm" % [
			club_bit, int(_aim_radius_yd)
		]
	else:
		feedback.text = "%s  ·  AIM line/shape  ○%d yd (%s) — drag, then Confirm" % [
			club_bit, int(_aim_radius_yd), GameState.form_label()
		]
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
	if wind_banner:
		wind_banner.visible = false


func _confirm_aim() -> void:
	if not _aiming or hole_complete:
		return
	_aiming = false
	_aim_dragging = false
	if confirm_aim_btn:
		confirm_aim_btn.visible = false
	_set_green_book_visible(false)  # close the book before stroking
	_refresh_wind_indicator(false)
	if wind_banner:
		wind_banner.visible = false
	AudioBus.play_ui()
	_start_power_swing()


func _start_power_swing() -> void:
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
	shot_routine.begin_shot()
	_power_previewing = true
	_on_power_preview_updated(shot_routine.power_stance.power, shot_routine.power_stance.stability)
	_set_green_book_visible(false)
	feedback.text = "%s · hold the white tick · circle tightens with judgment" % club_name


func _on_power_preview_updated(power: float, _stability: float) -> void:
	if not _power_previewing or hole_complete or ball_in_flight:
		return
	var lie := ball.get_lie()
	if lie == "Green":
		return
	var club_max := float(_chosen_club.get("max_yards", shot_routine.club_max_yards))
	var est := BallPhysics.estimate_carry_yards(power, club_max, lie)
	var from := ball.global_position
	var bearing := _aim_target - from
	if bearing.length_squared() < 1.0:
		bearing = _cup_pos - from
	_aim_target = AimControl.point_along_bearing(from, bearing, est)
	# Precision sharpens as power approaches the recommend tick.
	var recommend := shot_routine.power_stance.recommend_power
	var err := absf(power - recommend)
	var tight := clampf(1.0 - err / 0.18, 0.0, 1.0)
	_aim_radius_yd = lerpf(_aim_radius_base_yd, _aim_radius_base_yd * 0.45, tight)
	_refresh_aim_visuals()


func _set_aim_visuals_visible(on: bool) -> void:
	if _aim_cone:
		_aim_cone.visible = on
	if _aim_cone_edge:
		_aim_cone_edge.visible = on
	if _pin_ref_line:
		_pin_ref_line.visible = on
	if _aim_circle:
		_aim_circle.visible = on


func _refresh_wind_indicator(on: bool) -> void:
	if _wind_sprite == null:
		return
	if not on:
		_wind_sprite.visible = false
		return
	var wind: Vector2 = course_root.get_meta("wind", hole.wind_vector) if course_root else Vector2.ZERO
	if wind.length() < 4.0:
		_wind_sprite.visible = false
		return
	# Place near ball, arrow points the way the ball will be pushed
	var strength := wind.length()
	var tex: Texture2D = WIND_TEXTURES["light"]
	if strength >= 34.0:
		tex = WIND_TEXTURES["strong"]
	elif strength >= 16.0:
		tex = WIND_TEXTURES["medium"]
	_wind_sprite.texture = tex
	_wind_sprite.global_position = ball.global_position + Vector2(90, -60)
	_wind_sprite.rotation = wind.angle()
	var inv_z := 1.0 / maxf(camera.zoom.x, 0.35)
	_wind_sprite.scale = Vector2.ONE * (110.0 * inv_z / float(tex.get_width()))
	_wind_sprite.visible = true


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


func _world_mouse() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()


func _accept_mouse() -> bool:
	## On phones, Godot also emits emulated mouse for each touch — ignore those.
	return not DisplayServer.is_touchscreen_available()


func _apply_aim_world(world: Vector2) -> void:
	var from := ball.global_position
	if ball.get_lie() == "Green":
		# Putts still aim a real point on the green.
		_aim_target = AimControl.clamp_aim(world)
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
			var world := get_viewport().get_canvas_transform().affine_inverse() * touch.position
			_apply_aim_world(world)
		else:
			_aim_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and _aim_dragging:
		var drag := event as InputEventScreenDrag
		var world := get_viewport().get_canvas_transform().affine_inverse() * drag.position
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
	if wind_banner:
		wind_banner.visible = false
	var lie_at_strike := ball.get_lie()
	_set_green_book_visible(false)
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
	feedback.text = _last_report.summary_line()
	if result.is_perfect() and result.stance_stability >= 0.72:
		feedback.text = "PURE"
		feedback.modulate = Color(1.0, 0.92, 0.35)
		_pulse_pure_label()
	elif result.contact_quality == ShotResult.ContactQuality.FAT \
		or result.contact_quality == ShotResult.ContactQuality.MISS \
		or result.contact_quality == ShotResult.ContactQuality.THIN:
		feedback.modulate = Color(1.0, 0.55, 0.4)
	else:
		feedback.modulate = Color(0.9, 0.9, 0.9)


func _on_pure_strike(_result: ShotResult) -> void:
	## Slow-mo + camera punch + haptic when dual-finger coordination nails it.
	AudioBus.play_pure()
	GameState.record_pure_strike()
	# ponytail: one sharp pulse for pure; scale duration by contact quality after playtest
	Input.vibrate_handheld(22)
	Engine.time_scale = 0.55
	var punch := _desired_camera_zoom() * 1.12
	var restore := _desired_camera_zoom()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(camera, "zoom", punch, 0.06)
	# Hold a beat longer than the old 0.12s so pure flight reads after contact
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
	if pos.distance_to(_cup_pos) < CUP_RADIUS:
		_on_holed_out()
		return
	ball.set_lie(_classify_lie(pos))
	_update_hud()
	var actual := ball.distance_traveled_yards()
	if _last_report:
		_last_report.set_actual(actual)
		GameState.last_shot_metrics["actual_yd"] = actual
		GameState.last_shot_metrics["summary"] = _last_report.summary_line()
		feedback.text = _last_report.summary_line()
		if shot_result_panel and shot_result_panel.has_method("show_final"):
			shot_result_panel.show_final(_last_report)
			if not shot_result_panel.dismissed.is_connected(_on_shot_report_dismissed):
				shot_result_panel.dismissed.connect(_on_shot_report_dismissed, CONNECT_ONE_SHOT)
			return
	else:
		feedback.text = "Stopped  %d yd" % int(actual)
	feedback.modulate = Color(0.85, 0.9, 0.8)
	if not hole_complete and GameState.run_active:
		_start_shot_ui()


func _on_shot_report_dismissed() -> void:
	feedback.modulate = Color(0.85, 0.9, 0.8)
	if not hole_complete and GameState.run_active:
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
	strokes += 1
	GameState.record_stroke()
	ball_in_flight = false
	_set_aim_visuals_visible(false)
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
	if hud and hud.has_method("refresh"):
		hud.refresh(hole, strokes)


func _on_run_ended(_deepest: int, _reason: String) -> void:
	_end_aim_phase()
	shot_routine.set_active(false)


func skip_hole() -> void:
	if hole_complete:
		return
	_end_aim_phase()
	strokes = hole.par
	GameState.strokes_this_hole = hole.par
	_on_holed_out()


func debug_force_shot(perfect: bool) -> void:
	if ball_in_flight or hole_complete:
		return
	if _aiming:
		_confirm_aim()
	shot_routine.force_result(perfect)

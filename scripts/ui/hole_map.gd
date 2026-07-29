class_name HoleMap
extends Control

## Cart-GPS mini map: whole hole + ball. Sits under Debug on the main hole UI.

const MAP_W := 152.0
const MAP_H := 228.0
const PAD := 10.0

var _hole: HoleData
var _ball: Vector2 = Vector2.ZERO
var _green: Vector2 = Vector2.ZERO
var _cup: Vector2 = Vector2.ZERO
var _half: float = 70.0
var _centerline: PackedVector2Array = PackedVector2Array()
var _bunkers: Array = []
var _trees: Array = []
var _tees: Array = []  ## {pos: Vector2, set: HoleData.TeeSet, active: bool}
var _wr: Rect2 = Rect2()


func _ready() -> void:
	custom_minimum_size = Vector2(MAP_W, MAP_H)
	size = Vector2(MAP_W, MAP_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5


func park_under_debug(vp: Viewport) -> void:
	## Top-right, below Debug button (HUD strip + safe top + button + gap).
	var margins := UiScale.viewport_safe_margins(vp)
	var top := UiScale.HUD_HEIGHT + margins.y + 8.0 + 60.0 + 10.0
	var right := margins.z + 16.0
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -MAP_W - right
	offset_top = top
	offset_right = -right
	offset_bottom = top + MAP_H


func configure(
	hole: HoleData,
	green: Vector2,
	cup: Vector2,
	fairway_half: float,
	centerline: PackedVector2Array,
	bunkers: Array,
	trees: Array,
	tees: Array,
	ball: Vector2
) -> void:
	_hole = hole
	_green = green
	_cup = cup
	_half = fairway_half
	_centerline = centerline
	_bunkers = bunkers
	_trees = trees
	_tees = tees
	_ball = ball
	_wr = _compute_world_rect()
	visible = hole != null and not GameState.green_mode
	queue_redraw()


func set_ball(p: Vector2) -> void:
	_ball = p
	queue_redraw()


func _compute_world_rect() -> Rect2:
	var min_p := _green
	var max_p := _green
	for p in _centerline:
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	for t in _tees:
		var tp: Vector2 = t["pos"]
		min_p = Vector2(minf(min_p.x, tp.x), minf(min_p.y, tp.y))
		max_p = Vector2(maxf(max_p.x, tp.x), maxf(max_p.y, tp.y))
	for b in _bunkers:
		var c: Vector2 = b["c"]
		var r: float = float(b["r"])
		min_p = Vector2(minf(min_p.x, c.x - r), minf(min_p.y, c.y - r))
		max_p = Vector2(maxf(max_p.x, c.x + r), maxf(max_p.y, c.y + r))
	# Side padding for rough / corridor
	min_p -= Vector2(_half + 80.0, 60.0)
	max_p += Vector2(_half + 80.0, 80.0)
	return Rect2(min_p, max_p - min_p)


func _to_map(p: Vector2) -> Vector2:
	if _wr.size.x < 1.0 or _wr.size.y < 1.0:
		return size * 0.5
	var u := (p.x - _wr.position.x) / _wr.size.x
	var v := (p.y - _wr.position.y) / _wr.size.y
	var inner := Vector2(size.x - PAD * 2.0, size.y - PAD * 2.0)
	return Vector2(PAD + u * inner.x, PAD + v * inner.y)


func _draw() -> void:
	if _hole == null or _wr.size.x < 1.0:
		return
	var r := Rect2(Vector2.ZERO, size)
	# Panel chrome
	draw_rect(r, Color(0.06, 0.1, 0.08, 0.82), true)
	draw_rect(r, Color(0.35, 0.5, 0.38, 0.85), false, 2.0)

	# Rough fill (whole map field)
	draw_rect(r.grow(-PAD * 0.35), Color(0.28, 0.36, 0.26, 0.95), true)

	# Fairway ribbon along centerline
	if _centerline.size() >= 2:
		var half_map := maxf(_half / maxf(_wr.size.x, 1.0) * (size.x - PAD * 2.0), 4.0)
		for i in range(_centerline.size() - 1):
			var a := _to_map(_centerline[i])
			var b := _to_map(_centerline[i + 1])
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * half_map
			var poly := PackedVector2Array([a + n, b + n, b - n, a - n])
			draw_colored_polygon(poly, Color(0.42, 0.58, 0.32, 1.0))

	# Green
	var g := _to_map(_green)
	var grx := maxf((_hole.green_radius_x * 2.0) / maxf(_wr.size.x, 1.0) * (size.x - PAD * 2.0), 6.0)
	var gry := maxf((_hole.green_radius_y * 2.0) / maxf(_wr.size.y, 1.0) * (size.y - PAD * 2.0), 6.0)
	draw_ellipse_poly(g, grx * 0.5, gry * 0.5, Color(0.48, 0.72, 0.4, 1.0))

	# Bunkers
	for b in _bunkers:
		var c := _to_map(b["c"])
		var rr := maxf(float(b["r"]) / maxf(_wr.size.x, 1.0) * (size.x - PAD * 2.0), 2.5)
		draw_circle(c, rr, Color(0.82, 0.7, 0.48, 1.0))

	# Trees as dark dots
	for tr in _trees:
		var c := _to_map(tr["c"])
		var rr := maxf(float(tr["r"]) / maxf(_wr.size.x, 1.0) * (size.x - PAD * 2.0) * 0.55, 1.8)
		draw_circle(c, rr, Color(0.12, 0.22, 0.14, 1.0))

	# Tees (Blue / White / Red markers)
	const TEE_COL := {
		HoleData.TeeSet.BLUE: Color(0.23, 0.43, 0.65, 1.0),
		HoleData.TeeSet.WHITE: Color(0.92, 0.94, 0.9, 1.0),
		HoleData.TeeSet.RED: Color(0.77, 0.23, 0.23, 1.0),
	}
	for t in _tees:
		var p := _to_map(t["pos"])
		var col: Color = TEE_COL.get(t["set"], Color.WHITE)
		var rad := 4.0 if bool(t.get("active", false)) else 2.6
		draw_circle(p, rad + 1.0, Color(0, 0, 0, 0.55))
		draw_circle(p, rad, col)

	# Pin
	var pin := _to_map(_cup)
	draw_circle(pin, 2.2, Color(0.95, 0.2, 0.2, 1.0))
	draw_line(pin, pin + Vector2(0, -7), Color(0.95, 0.25, 0.25, 1.0), 1.5)

	# Ball
	var bp := _to_map(_ball)
	draw_circle(bp, 3.6, Color(0, 0, 0, 0.5))
	draw_circle(bp, 2.8, Color(1.0, 1.0, 0.92, 1.0))


func draw_ellipse_poly(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

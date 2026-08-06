class_name WindFlag
extends Control

## HUD wind glance: rigid pole + cloth reshape (direction + strength).
## Visual truth: plans/wind_direction_speed.png
## Course pin shares paint_flag() — same modes and colors.

const TIP_SEC := 2.2
const FLAG_H := 120.0
const CALM := 0.5

const STRENGTH_NORM := 40.0  ## mph at which tautness maxes out

## Layout in “design space” (height FLAG_H); paint_flag scales by height_px / FLAG_H.
const POLE_TOP_Y := 10.0
const POLE_BOTTOM_Y := FLAG_H - 6.0
const ATTACH_Y := POLE_TOP_Y + 6.0
const FLAG_LOCAL_H := 24.0
const POLE_W := 4.0

const CROSS_REACH_MIN := 14.0
const CROSS_REACH_MAX := 46.0
const CROSS_DROOP_MIN := 2.0
const CROSS_DROOP_MAX := 10.0

const BILLOW_BASE := 10.0
const INTO_SCALE_MAX := 1.9
const DOWN_SCALE_MIN := 0.22  ## high downwind ≈ sliver (mockup), not zero

const COLOR_POLE := Color(0.95, 0.95, 0.97)
const COLOR_FRONT := Color(0.886, 0.294, 0.290)  ## cross + into
const COLOR_BEHIND := Color(0.639, 0.176, 0.176)  ## downwind muted


## Shared by HUD + course pin.
## origin = pole foot in ci local space; Y+ is down; pole extends toward −Y.
static func paint_flag(
	ci: CanvasItem, origin: Vector2, wind: Vector2, t_sec: float, height_px: float
) -> void:
	var s := height_px / FLAG_H
	var pole_h := (POLE_BOTTOM_Y - POLE_TOP_Y) * s
	var attach_up := (POLE_BOTTOM_Y - ATTACH_Y) * s
	var cloth_h := FLAG_LOCAL_H * s
	var pole_w := maxf(POLE_W * s, 1.5)

	var foot := origin
	var top := origin + Vector2(0.0, -pole_h)
	var attach := origin + Vector2(0.0, -attach_up)

	var ax := absf(wind.x)
	var ay := absf(wind.y)
	var use_cross := ax >= ay
	var strength_amt := clampf(wind.length() / STRENGTH_NORM, 0.0, 1.0)
	var flutter := sin(t_sec * (1.5 + strength_amt * 3.0)) * 1.5 * strength_amt * s

	if wind.length() < CALM:
		_paint_pole(ci, top, foot, pole_w)
		_paint_pennant(
			ci,
			attach,
			attach + Vector2(0.0, cloth_h * 0.55),
			attach
			+ Vector2(
				-CROSS_REACH_MIN * 0.55 * s,
				cloth_h * 0.35 * 0.55 + CROSS_DROOP_MAX * 0.6 * s
			),
			COLOR_FRONT
		)
		return

	if use_cross:
		var side := signf(wind.x) if ax > CALM else -1.0
		if side == 0.0:
			side = -1.0
		var cross_amt := clampf(ax / STRENGTH_NORM, 0.0, 1.0)
		var reach := lerpf(CROSS_REACH_MIN, CROSS_REACH_MAX, cross_amt) * s
		var droop := lerpf(CROSS_DROOP_MAX, CROSS_DROOP_MIN, cross_amt) * s
		_paint_pole(ci, top, foot, pole_w)
		_paint_pennant(
			ci,
			attach,
			attach + Vector2(0.0, cloth_h),
			attach + Vector2(side * reach + flutter, cloth_h * 0.35 + droop),
			COLOR_FRONT
		)
	elif wind.y < -CALM:
		var fwd_amt := clampf(ay / STRENGTH_NORM, 0.0, 1.0)
		var sc := lerpf(1.0, INTO_SCALE_MAX, fwd_amt)
		_paint_pole(ci, top, foot, pole_w)
		_paint_billow(ci, attach, cloth_h, sc, flutter, COLOR_FRONT, s)
	else:
		var fwd2 := clampf(ay / STRENGTH_NORM, 0.0, 1.0)
		var sc2 := lerpf(1.0, DOWN_SCALE_MIN, fwd2)
		_paint_billow(ci, attach, cloth_h, sc2, flutter * 0.5, COLOR_BEHIND, s)
		_paint_pole(ci, top, foot, pole_w)


static func _paint_pole(ci: CanvasItem, from: Vector2, to: Vector2, width: float) -> void:
	ci.draw_line(from, to, COLOR_POLE, width, true)


static func _paint_pennant(
	ci: CanvasItem, top: Vector2, bottom: Vector2, tip: Vector2, color: Color
) -> void:
	ci.draw_colored_polygon(PackedVector2Array([top, tip, bottom]), color)


static func _paint_billow(
	ci: CanvasItem,
	attach: Vector2,
	cloth_h: float,
	scale: float,
	flutter: float,
	color: Color,
	s: float
) -> void:
	var h := cloth_h * scale
	var top := attach
	var bot := attach + Vector2(0.0, h)
	var bulge := BILLOW_BASE * scale * s + flutter
	var tip_a := attach + Vector2(bulge, h * 0.28)
	var tip_b := attach + Vector2(bulge * 0.85, h * 0.72)
	ci.draw_colored_polygon(PackedVector2Array([top, tip_a, tip_b, bot]), color)


var _wind: Vector2 = Vector2.ZERO
var _extra: String = ""
var _tip_until_msec: int = 0
var _t: float = 0.0

var _tip: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(96, FLAG_H + 28.0)

	_tip = Label.new()
	_tip.visible = false
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_tip.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0, 1.0))
	_tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_left = -220.0
	_tip.offset_right = 220.0
	_tip.offset_top = 4.0
	_tip.offset_bottom = 72.0
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)

	gui_input.connect(_on_gui_input)
	set_process(false)


func show_wind(wind: Vector2, extra: String = "") -> void:
	_wind = wind
	_extra = extra
	visible = true
	set_process(true)
	queue_redraw()


func set_wind_vector(wind: Vector2) -> void:
	## Update without clearing tap-tip extra (green book note, etc.).
	_wind = wind
	visible = true
	set_process(true)
	queue_redraw()


func hide_wind() -> void:
	visible = false
	_tip.visible = false
	_tip_until_msec = 0
	_extra = ""
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _tip.visible and Time.get_ticks_msec() >= _tip_until_msec:
		_tip.visible = false


func _draw() -> void:
	var w := size.x if size.x > 1.0 else custom_minimum_size.x
	var foot := Vector2(w * 0.5, POLE_BOTTOM_Y)
	paint_flag(self, foot, _wind, _t, FLAG_H)


func _on_gui_input(event: InputEvent) -> void:
	var tap := false
	if event is InputEventScreenTouch and event.pressed:
		tap = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap = true
	if not tap:
		return
	_show_tip()
	accept_event()


func _show_tip() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d mph" % int(roundf(_wind.length())))
	if absf(_wind.y) > 0.5:
		lines.append("helping" if _wind.y > 0.0 else "into the wind")
	elif absf(_wind.x) > 0.5:
		lines.append("crosswind")
	if not _extra.is_empty():
		lines.append(_extra)
	_tip.text = "\n".join(lines)
	_tip.visible = true
	_tip_until_msec = Time.get_ticks_msec() + int(TIP_SEC * 1000.0)

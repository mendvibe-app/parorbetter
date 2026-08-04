class_name WindFlag
extends Control

## Flagstick glance for wind: lean + wave from vector; tap for advice sentence.

const TEX_FLAG := preload("res://assets/greens/pin_flag.png")
const TIP_SEC := 2.2
const MAX_LEAN := 0.61  ## ~35°
const FLAG_H := 120.0

var _wind: Vector2 = Vector2.ZERO
var _extra: String = ""
var _tip_until_msec: int = 0

var _flag: TextureRect
var _axis: Label  ## Head/tail cue (↑ INTO / ↓ HELP); lean still owns crosswind.
var _tip: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(96, FLAG_H + 28.0)

	_flag = TextureRect.new()
	_flag.texture = TEX_FLAG
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flag.offset_bottom = -22.0
	# Pivot near pole base (texture center-x) so lean reads as a flagstick.
	_flag.pivot_offset = Vector2(custom_minimum_size.x * 0.5, FLAG_H - 8.0)
	add_child(_flag)

	_axis = Label.new()
	_axis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_axis.add_theme_font_size_override("font_size", int(UiScale.CAPTION * 0.55))
	_axis.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0, 1.0))
	_axis.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_axis.anchor_top = 1.0
	_axis.anchor_bottom = 1.0
	_axis.offset_left = -48.0
	_axis.offset_right = 48.0
	_axis.offset_top = -20.0
	_axis.offset_bottom = 2.0
	_axis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_axis.visible = false
	add_child(_axis)

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
	_layout_flag_pivot()


func set_wind_vector(wind: Vector2) -> void:
	## Update lean without clearing tap-tip extra (green book note, etc.).
	_wind = wind
	visible = true
	set_process(true)
	_layout_flag_pivot()


func hide_wind() -> void:
	visible = false
	_tip.visible = false
	_tip_until_msec = 0
	_extra = ""
	set_process(false)


func _layout_flag_pivot() -> void:
	if _flag == null:
		return
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = custom_minimum_size
	_flag.pivot_offset = Vector2(sz.x * 0.5, sz.y - 10.0)


func _process(_delta: float) -> void:
	_layout_flag_pivot()
	var strength := _wind.length()
	var t := float(Time.get_ticks_msec()) * 0.001
	# ponytail: lean capped ~35°; cloth sim if this ever looks silly in a gale.
	var lean_amt := clampf(strength / 40.0, 0.0, 1.0)
	# Lean = crosswind only; pure head/tail wind keeps the flag upright (flutter only).
	var side := signf(_wind.x) if absf(_wind.x) > 0.5 else 0.0
	var lean := side * lean_amt * MAX_LEAN
	var wave := 0.0
	if lean_amt > 0.02:
		var speed := 1.2 + lean_amt * 3.5
		# Flutter amplitude scales with strength so a wind-4 breeze barely ripples.
		wave = sin(t * speed * TAU) * deg_to_rad(12.0 * lean_amt)
	_flag.rotation = lean + wave
	_refresh_axis_glyph()

	if _tip.visible and Time.get_ticks_msec() >= _tip_until_msec:
		_tip.visible = false


func _refresh_axis_glyph() -> void:
	## Head/tail at a glance. Physics: wind_yards = -wind.y * 0.35 → +y helps, −y into.
	if _axis == null:
		return
	var ay := _wind.y
	if absf(ay) <= 0.5:
		_axis.visible = false
		return
	_axis.visible = true
	if ay > 0.0:
		_axis.text = "↓ HELP"
	else:
		_axis.text = "↑ INTO"
	var a := clampf(absf(ay) / 40.0, 0.35, 1.0)
	_axis.modulate = Color(1.0, 1.0, 1.0, a)


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

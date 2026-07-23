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
var _tip: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(96, FLAG_H + 8.0)

	_flag = TextureRect.new()
	_flag.texture = TEX_FLAG
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flag.offset_bottom = -4.0
	# Pivot near pole base so lean reads as a flagstick, not a spinner.
	_flag.pivot_offset = Vector2(48, FLAG_H - 8.0)
	add_child(_flag)

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
	var side := 0.0
	if absf(_wind.x) > 0.5:
		side = signf(_wind.x)
	elif strength >= 4.0:
		side = signf(_wind.x) if _wind.x != 0.0 else 1.0
	var lean := side * lean_amt * MAX_LEAN
	var wave := 0.0
	if lean_amt > 0.02:
		var speed := 1.2 + lean_amt * 3.5
		wave = sin(t * speed * TAU) * deg_to_rad(5.0 + lean_amt * 7.0)
	_flag.rotation = lean + wave

	if _tip.visible and Time.get_ticks_msec() >= _tip_until_msec:
		_tip.visible = false


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
	lines.append(AimControl.wind_label(_wind))
	var advice := AimControl.wind_aim_hint(_wind)
	if not advice.is_empty():
		lines.append(advice)
	if not _extra.is_empty():
		lines.append(_extra)
	_tip.text = "\n".join(lines)
	_tip.visible = true
	_tip_until_msec = Time.get_ticks_msec() + int(TIP_SEC * 1000.0)

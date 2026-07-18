class_name ClubSelect
extends Control

## Pre-aim bag picker. Tap a club to proceed.

signal club_chosen(club: Dictionary)

var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280.0
	panel.offset_top = -340.0
	panel.offset_right = 280.0
	panel.offset_bottom = 340.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.text = "CHOOSE CLUB"
	root.add_child(_title)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.7, 1))
	hint.text = "Suggested club is highlighted"
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 520)
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)


func present(lie: String, pin_yd: float, wind: Vector2) -> void:
	for child in _list.get_children():
		child.queue_free()

	var suggested := BallPhysics.pick_club(pin_yd, lie)
	var suggested_name := String(suggested["name"])
	_title.text = "CHOOSE CLUB  ·  %d yd" % int(pin_yd)

	for club in BallPhysics.clubs_for_lie(lie):
		var name := String(club["name"])
		var max_yd := float(club["max_yards"])
		var pct := BallPhysics.club_percent_today(pin_yd, max_yd, lie, wind)
		var is_suggested := name == suggested_name
		var btn := Button.new()
		btn.text = "%s%s  —  %d max  —  %d%% today" % [
			"★ " if is_suggested else "",
			name,
			int(max_yd),
			int(pct * 100.0),
		]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_suggested:
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1))
		var chosen: Dictionary = club
		btn.pressed.connect(func() -> void: _pick(chosen))
		_list.add_child(btn)

	visible = true


func dismiss() -> void:
	visible = false


func _pick(club: Dictionary) -> void:
	dismiss()
	club_chosen.emit(club)

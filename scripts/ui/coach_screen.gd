class_name CoachScreen
extends Control

## Player-facing per-club tendency breakdown. Reachable from the start screen.
## Icon-first per design principle; badges are text stubs until tendency art
## exists (see club_select.gd).

signal dismissed

var _panel: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.05, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	var view_h := get_viewport_rect().size.y
	_panel.custom_minimum_size = Vector2(680, minf(760.0, maxf(420.0, view_h - 48.0)))
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(640, 0)
	margin.add_child(root)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiScale.TITLE)
	title.text = "CLUB COACH"
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 380)
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, UiScale.TOUCH_MIN)
	close_btn.add_theme_font_size_override("font_size", UiScale.BODY)
	close_btn.pressed.connect(func():
		AudioBus.play_ui()
		dismiss()
		dismissed.emit()
	)
	root.add_child(close_btn)


func present() -> void:
	_rebuild_list()
	visible = true


func dismiss() -> void:
	visible = false


func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var clubs: Dictionary = GameState.club_coach.clubs
	var names := clubs.keys()
	names.sort()

	var any_shots := false
	for club_name in names:
		var stats: Dictionary = clubs[club_name]
		if int(stats.get("shots_logged", 0)) <= 0:
			continue
		any_shots = true
		_list.add_child(_build_row(club_name, stats))

	if not any_shots:
		var empty := Label.new()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", UiScale.BODY)
		empty.text = "No club data yet — play a round to build your tendency card."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		_list.add_child(empty)


func _build_row(club_name: String, stats: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", UiScale.BODY)
	var avg_yd := int(ClubCoachLog.avg(stats.get("yardage_history", [])))
	var shots := int(stats.get("shots_logged", 0))
	head.text = "%s — avg %d yd (%d shots)" % [club_name, avg_yd, shots]
	row.add_child(head)

	if club_name == "Putter":
		var longest_row := Label.new()
		longest_row.add_theme_font_size_override("font_size", UiScale.CAPTION)
		longest_row.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
		var longest_ft := PuttStroke.yd_to_ft(float(stats.get("longest_made_yards", 0.0)))
		longest_row.text = "Longest putt made: %d ft" % int(round(longest_ft))
		row.add_child(longest_row)

	var tip := ClubCoachLog.resolve_tip(stats)
	var tip_label := Label.new()
	tip_label.add_theme_font_size_override("font_size", UiScale.CAPTION)
	tip_label.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip_label.text = str(tip.get("label", ""))
	row.add_child(tip_label)

	return row

class_name ClubSelect
extends Control

## Pre-aim club picker. Default: 3 clubs near the shot; Full bag for the rest.

signal club_chosen(club: Dictionary)

const OPEN_LOCK_SEC := 0.45
const SWITCH_LOCK_SEC := 0.28

var _panel: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _hint: Label
var _confirm: Button
var _bag_toggle: Button
var _selected: Dictionary = {}
var _confirm_ready_at_msec: int = 0
var _lie: String = ""
var _pin_yd: float = 0.0
var _wind: Vector2 = Vector2.ZERO
var _full_bag: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_set_panel_compact(true)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", UiScale.TITLE)
	_title.text = "CHOOSE CLUB"
	root.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_hint.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
	_hint.text = "Tap a club, then Confirm"
	root.add_child(_hint)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.custom_minimum_size = Vector2(0, 280)
	root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	_scroll.add_child(_list)

	_bag_toggle = Button.new()
	_bag_toggle.text = "Full bag"
	_bag_toggle.custom_minimum_size = Vector2(0, UiScale.TOUCH_MIN * 0.75)
	_bag_toggle.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_bag_toggle.pressed.connect(_toggle_bag)
	root.add_child(_bag_toggle)

	_confirm = Button.new()
	_confirm.text = "Confirm club"
	_confirm.custom_minimum_size = Vector2(0, UiScale.TOUCH_MIN)
	_confirm.add_theme_font_size_override("font_size", UiScale.BODY)
	_confirm.disabled = true
	_confirm.pressed.connect(_commit)
	root.add_child(_confirm)


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_confirm_enabled()


func present(lie: String, pin_yd: float, wind: Vector2) -> void:
	_lie = lie
	_pin_yd = pin_yd
	_wind = wind
	_full_bag = false
	_selected = {}
	_confirm_ready_at_msec = Time.get_ticks_msec() + int(OPEN_LOCK_SEC * 1000.0)
	_title.text = "CHOOSE CLUB  ·  %d yd" % int(pin_yd)
	_rebuild_list()
	visible = true
	set_process(true)
	_refresh_confirm_enabled()


func dismiss() -> void:
	visible = false
	set_process(false)
	_selected = {}


func _toggle_bag() -> void:
	_full_bag = not _full_bag
	var keep_name := String(_selected.get("name", ""))
	_rebuild_list(keep_name)
	_refresh_confirm_enabled()


func _set_panel_compact(compact: bool) -> void:
	var half_h := 300.0 if compact else 420.0
	_panel.offset_left = -320.0
	_panel.offset_top = -half_h
	_panel.offset_right = 320.0
	_panel.offset_bottom = half_h


func _rebuild_list(prefer_name: String = "") -> void:
	for child in _list.get_children():
		child.queue_free()

	var suggested := BallPhysics.pick_club(_pin_yd, _lie)
	var suggested_name := String(suggested["name"])
	var clubs: Array[Dictionary] = (
		BallPhysics.clubs_for_lie(_lie) if _full_bag else BallPhysics.suggest_clubs(_pin_yd, _lie)
	)
	_bag_toggle.text = "Suggested" if _full_bag else "Full bag"
	_set_panel_compact(not _full_bag)
	_scroll.custom_minimum_size.y = 480.0 if _full_bag else 280.0
	_hint.text = "Tap a club, then Confirm"

	var select_name := prefer_name if not prefer_name.is_empty() else suggested_name
	_selected = {}
	for club in clubs:
		if String(club["name"]) == select_name:
			_selected = club
			break
	if _selected.is_empty():
		for club in clubs:
			if String(club["name"]) == suggested_name:
				_selected = club
				break
	if _selected.is_empty() and not clubs.is_empty():
		_selected = clubs[0]

	var selected_name := String(_selected.get("name", ""))
	for club in clubs:
		var name := String(club["name"])
		var max_yd := float(club["max_yards"])
		var pct := BallPhysics.club_percent_today(_pin_yd, max_yd, _lie, _wind)
		var is_suggested := name == suggested_name
		var btn := Button.new()
		btn.toggle_mode = true
		btn.icon = HudIcons.club_texture(name)
		btn.expand_icon = true
		btn.text = "%s%s  —  %d max  —  %d%% today" % [
			"★ " if is_suggested else "",
			name,
			int(max_yd),
			int(pct * 100.0),
		]
		btn.custom_minimum_size = Vector2(0, UiScale.TOUCH_MIN)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UiScale.BODY)
		if is_suggested:
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1))
		var chosen: Dictionary = club
		btn.pressed.connect(func() -> void: _select(chosen, btn))
		_list.add_child(btn)
		if name == selected_name:
			btn.button_pressed = true

	_confirm.text = (
		"Confirm %s" % selected_name if not selected_name.is_empty() else "Confirm club"
	)


func _select(club: Dictionary, btn: Button) -> void:
	_selected = club
	for child in _list.get_children():
		if child is Button and child != btn:
			(child as Button).button_pressed = false
	btn.button_pressed = true
	_confirm.text = "Confirm %s" % String(club["name"])
	# Switching clubs re-locks confirm briefly — no endless dither-commit.
	_confirm_ready_at_msec = maxi(
		_confirm_ready_at_msec,
		Time.get_ticks_msec() + int(SWITCH_LOCK_SEC * 1000.0)
	)
	_refresh_confirm_enabled()


func _refresh_confirm_enabled() -> void:
	var ready := Time.get_ticks_msec() >= _confirm_ready_at_msec
	_confirm.disabled = _selected.is_empty() or not ready
	if _selected.is_empty():
		_hint.text = "Tap a club, then Confirm"
	elif not ready:
		_hint.text = "Commit to it…"
	else:
		_hint.text = "Confirm to aim with %s" % String(_selected["name"])


func _commit() -> void:
	if _selected.is_empty() or _confirm.disabled:
		return
	var club := _selected
	dismiss()
	club_chosen.emit(club)

class_name ClubSelect
extends Control

## Pre-aim bag picker. Tap to highlight, Confirm to commit (small dither friction).

signal club_chosen(club: Dictionary)

const OPEN_LOCK_SEC := 0.45
const SWITCH_LOCK_SEC := 0.28

var _list: VBoxContainer
var _title: Label
var _hint: Label
var _confirm: Button
var _selected: Dictionary = {}
var _confirm_ready_at_msec: int = 0


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
	panel.offset_left = -320.0
	panel.offset_top = -420.0
	panel.offset_right = 320.0
	panel.offset_bottom = 420.0
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
	_title.add_theme_font_size_override("font_size", UiScale.TITLE)
	_title.text = "CHOOSE CLUB"
	root.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_hint.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
	_hint.text = "Tap a club, then Confirm"
	root.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 480)
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

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
	for child in _list.get_children():
		child.queue_free()

	_selected = {}
	_confirm_ready_at_msec = Time.get_ticks_msec() + int(OPEN_LOCK_SEC * 1000.0)
	var suggested := BallPhysics.pick_club(pin_yd, lie)
	var suggested_name := String(suggested["name"])
	_title.text = "CHOOSE CLUB  ·  %d yd" % int(pin_yd)
	_hint.text = "Tap a club, then Confirm"

	for club in BallPhysics.clubs_for_lie(lie):
		var name := String(club["name"])
		var max_yd := float(club["max_yards"])
		var pct := BallPhysics.club_percent_today(pin_yd, max_yd, lie, wind)
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
		if is_suggested:
			btn.button_pressed = true
			_selected = chosen

	_confirm.text = "Confirm %s" % suggested_name if not _selected.is_empty() else "Confirm club"
	visible = true
	set_process(true)
	_refresh_confirm_enabled()


func dismiss() -> void:
	visible = false
	set_process(false)
	_selected = {}


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

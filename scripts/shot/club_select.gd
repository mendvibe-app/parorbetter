class_name ClubSelect
extends Control

## Pre-aim club picker. Default: 3 clubs near the shot; Full bag for the rest.

signal club_chosen(club: Dictionary)

const OPEN_LOCK_SEC := 0.45
const SWITCH_LOCK_SEC := 0.28

var _panel: PanelContainer
var _center: CenterContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _hint: Label
var _lie_preview: LiePreview
var _confirm: Button
var _bag_toggle: Button
var _selected: Dictionary = {}
var _confirm_ready_at_msec: int = 0
var _lie: String = ""
var _severity: String = ""
var _pin_yd: float = 0.0
var _wind: Vector2 = Vector2.ZERO
var _full_bag: bool = false
## Scroll at row press — if it moved past deadzone, release is a drag not a tap.
var _press_scroll: int = 0
var _drag_origin_y: float = 0.0
var _drag_origin_scroll: int = 0
var _drag_scrolling: bool = false
const DRAG_DEADZONE := 12

const TENDENCY_BADGE_TEXT := {
	"rushed_transition": "Rushing",
	"lingering_top": "Lingering",
	"slice_tendency": "Slice",
	"hook_tendency": "Hook",
	"contact_issue": "Inconsistent",
}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	_panel = PanelContainer.new()
	_set_panel_compact(true)
	_center.add_child(_panel)

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

	# Lie diorama above the bag — read severity before you commit a club.
	var prev_wrap := CenterContainer.new()
	prev_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lie_preview = LiePreview.new()
	_lie_preview.custom_minimum_size = Vector2(160, 56)
	prev_wrap.add_child(_lie_preview)
	root.add_child(prev_wrap)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# SHOW_ALWAYS: desktop scrollbar. We own drag ourselves (deadzone below is unused).
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	# ponytail: huge deadzone disables built-in touch-drag so it can't double with ours.
	_scroll.scroll_deadzone = 1_000_000
	_scroll.custom_minimum_size = Vector2(0, 320)
	_scroll.gui_input.connect(_on_scroll_gui_input)
	root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
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


func present(lie: String, pin_yd: float, wind: Vector2, severity: String = "") -> void:
	_lie = lie
	_severity = severity
	_pin_yd = pin_yd
	_wind = wind
	_full_bag = false
	_selected = {}
	_confirm_ready_at_msec = Time.get_ticks_msec() + int(OPEN_LOCK_SEC * 1000.0)
	_title.text = "CHOOSE CLUB  ·  %d yd" % int(pin_yd)
	if _lie_preview:
		_lie_preview.set_state(lie, severity)
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
	## Size the panel; CenterContainer keeps it viewport-centered.
	## Cap to viewport so the list must scroll instead of growing off-screen.
	var view_h := get_viewport_rect().size.y
	var want := 620.0 if compact else 900.0
	var h := minf(want, maxf(420.0, view_h - 48.0))
	_panel.custom_minimum_size = Vector2(680, h)


func _on_scroll_gui_input(event: InputEvent) -> void:
	## Drag-to-scroll (rows PASS events here; built-in SC drag is disabled).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_origin_y = event.global_position.y
			_drag_origin_scroll = _scroll.scroll_vertical
			_drag_scrolling = false
			_press_scroll = _scroll.scroll_vertical
		else:
			_drag_scrolling = false
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var motion := event as InputEventMouseMotion
		var dy: float = motion.global_position.y - _drag_origin_y
		if _drag_scrolling or absf(dy) >= float(DRAG_DEADZONE):
			_drag_scrolling = true
			_scroll.scroll_vertical = _drag_origin_scroll - int(dy)
			accept_event()


func _club_row_text(name: String, max_yd: float, is_suggested: bool) -> String:
	## Effort copy for this pin. Full (≥95%) is unlabeled; oversized clubs run through.
	var pct := BallPhysics.club_percent_today(_pin_yd, max_yd, _lie, _wind, _severity)
	var star := "★ " if is_suggested else ""
	var badge := _tendency_badge(name)
	if (
		_lie != "Green"
		and not BallPhysics.is_shortest_available(max_yd, _lie)
		and pct < BallPhysics.POWER_POCKET_LO
	):
		return "%s%s  —  %d yd · runs through%s" % [star, name, int(max_yd), badge]
	if pct >= 0.95:
		return "%s%s  —  %d yd%s" % [star, name, int(max_yd), badge]
	# PLAYTEST TARGET: band edges. Real golf effort language, not a raw %.
	var descriptor := "tight — one more club plays smoother"
	if pct >= 0.85:
		descriptor = "smooth"
	elif pct >= 0.70:
		descriptor = "3/4"
	return "%s%s  —  %d yd · %s%s" % [star, name, int(max_yd), descriptor, badge]


func _tendency_badge(name: String) -> String:
	## Text stub for the tendency icon (Phase 3) — swap for an icon lookup in hud_icons.gd
	## once tendency art exists; resolve_tip().tag is already the icon key to use then.
	if not GameState.club_coach_ui_enabled:
		return ""
	var stats: Dictionary = GameState.club_coach.clubs.get(name, {})
	if int(stats.get("shots_logged", 0)) < ClubCoachLog.MIN_SAMPLES_FOR_TIP:
		return ""
	var tag := str(ClubCoachLog.resolve_tip(stats).get("tag", ""))
	if not TENDENCY_BADGE_TEXT.has(tag):
		return ""
	return " · %s" % TENDENCY_BADGE_TEXT[tag]


func _rebuild_list(prefer_name: String = "") -> void:
	for child in _list.get_children():
		child.queue_free()

	var suggested := BallPhysics.pick_club(_pin_yd, _lie, _severity)
	var suggested_name := String(suggested["name"])
	var clubs: Array[Dictionary] = (
		BallPhysics.clubs_for_lie(_lie)
		if _full_bag
		else BallPhysics.suggest_clubs(_pin_yd, _lie, 3, _severity)
	)
	_bag_toggle.text = "Suggested" if _full_bag else "Full bag"
	_set_panel_compact(not _full_bag)
	# Leave room for title/hint/toggle/confirm; rest is the scroll viewport.
	var chrome := 260.0
	_scroll.custom_minimum_size.y = maxf(180.0, _panel.custom_minimum_size.y - chrome)
	_scroll.scroll_vertical = 0
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
		var is_suggested := name == suggested_name
		var btn := Button.new()
		btn.toggle_mode = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		# PASS: drag reaches ScrollContainer (STOP ate the gesture — bag felt stuck).
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.icon = HudIcons.club_texture(name)
		btn.expand_icon = true
		btn.text = _club_row_text(name, max_yd, is_suggested)
		btn.custom_minimum_size = Vector2(0, UiScale.TOUCH_MIN)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UiScale.BODY)
		btn.set_meta("club_name", name)
		if is_suggested:
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1))
		var chosen: Dictionary = club
		btn.button_down.connect(_on_row_button_down)
		btn.pressed.connect(func() -> void: _on_row_pressed(chosen, btn))
		_list.add_child(btn)
		if name == selected_name:
			btn.button_pressed = true

	_confirm.text = (
		"Confirm %s" % selected_name if not selected_name.is_empty() else "Confirm club"
	)


func _on_row_button_down() -> void:
	_press_scroll = _scroll.scroll_vertical


func _on_row_pressed(club: Dictionary, btn: Button) -> void:
	# Drag past deadzone → scroll, not club change.
	if _drag_scrolling or absi(_scroll.scroll_vertical - _press_scroll) > DRAG_DEADZONE:
		_sync_row_pressed()
		return
	_select(club, btn)


func _sync_row_pressed() -> void:
	var sel := String(_selected.get("name", ""))
	for child in _list.get_children():
		if child is Button:
			var b := child as Button
			b.set_pressed_no_signal(String(b.get_meta("club_name", "")) == sel)


func _select(club: Dictionary, btn: Button) -> void:
	_selected = club
	_sync_row_pressed()
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

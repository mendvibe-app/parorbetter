class_name ScoreCard
extends Control

## Paper-style 18-hole card for stroke play. Marks: circle birdie, double eagle,
## square bogey, double square double+. Expand/collapse tab during the round.

const MARK_UNDER := Color(1.0, 0.88, 0.35, 1.0)  # birdie/eagle gold
const MARK_OVER := Color(0.55, 0.62, 0.72, 1.0)  # bogey slate
const PAPER := Color(0.12, 0.16, 0.13, 0.96)
const REVEAL_SEC := 0.45

var _expanded: bool = false
var _panel: PanelContainer
var _dim: ColorRect
var _title: Label
var _to_par: Label
var _tab_btn: Button
var _close_btn: Button
var _cells: Array = []  ## 18 cell dicts
var _out_lab: Label
var _in_lab: Label
var _tot_lab: Label
var _grid: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_chrome()
	visible = false
	set_expanded(false)


func _build_chrome() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.04, 0.03, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			set_expanded(false)
			accept_event()
		elif ev is InputEventScreenTouch and ev.pressed:
			set_expanded(false)
			accept_event()
	)
	add_child(_dim)

	_tab_btn = Button.new()
	_tab_btn.name = "ScoreTab"
	_tab_btn.text = "Card  E"
	_tab_btn.custom_minimum_size = Vector2(140, 52)
	_tab_btn.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_tab_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tab_btn.offset_left = 16.0
	_tab_btn.offset_top = 96.0
	_tab_btn.offset_right = 156.0
	_tab_btn.offset_bottom = 148.0
	_tab_btn.z_index = 8
	_tab_btn.focus_mode = Control.FOCUS_NONE
	_tab_btn.pressed.connect(func() -> void:
		AudioBus.play_ui()
		set_expanded(not _expanded)
	)
	add_child(_tab_btn)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.z_index = 9
	_panel.custom_minimum_size = Vector2(1000, 520)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -500.0
	_panel.offset_top = -280.0
	_panel.offset_right = 500.0
	_panel.offset_bottom = 280.0
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color(0.35, 0.42, 0.32, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)

	var head := HBoxContainer.new()
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", UiScale.BODY)
	_title.text = "SCORECARD"
	head.add_child(_title)
	_to_par = Label.new()
	_to_par.add_theme_font_size_override("font_size", UiScale.BODY)
	_to_par.add_theme_color_override("font_color", MARK_UNDER)
	_to_par.text = "E"
	head.add_child(_to_par)
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(120, 48)
	_close_btn.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_close_btn.pressed.connect(func() -> void:
		AudioBus.play_ui()
		set_expanded(false)
	)
	head.add_child(_close_btn)
	root.add_child(head)

	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 6)
	root.add_child(_grid)

	_out_lab = Label.new()
	_out_lab.add_theme_font_size_override("font_size", UiScale.CAPTION)
	root.add_child(_out_lab)
	_in_lab = Label.new()
	_in_lab.add_theme_font_size_override("font_size", UiScale.CAPTION)
	root.add_child(_in_lab)
	_tot_lab = Label.new()
	_tot_lab.add_theme_font_size_override("font_size", UiScale.BODY)
	root.add_child(_tot_lab)


func set_expanded(on: bool) -> void:
	_expanded = on
	_panel.visible = on
	_dim.visible = on
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_tab_btn.mouse_filter = Control.MOUSE_FILTER_STOP


func populate() -> void:
	## Rebuild grid from GameState course + already-posted hole_scores.
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()

	var theme_name := "COURSE"
	match GameState.course_theme:
		HoleData.CourseTheme.PARKLAND:
			theme_name = "PARKLAND"
		HoleData.CourseTheme.LINKS:
			theme_name = "LINKS"
		HoleData.CourseTheme.DESERT:
			theme_name = "DESERT"
	_title.text = "%s · 18" % theme_name

	var n := mini(GameState.HOLE_COUNT, 18)
	if GameState.course.size() > 0:
		n = mini(GameState.course.size(), 18)

	_grid.add_child(_make_nine_row(0, mini(9, n), "OUT"))
	if n > 9:
		_grid.add_child(_make_nine_row(9, n, "IN"))

	# Apply any already-posted scores (resume / game over).
	for i in GameState.hole_scores.size():
		if i < _cells.size():
			_apply_cell(i, int(GameState.hole_scores[i]), 1.0)

	_refresh_totals()
	_refresh_tab()


func _make_nine_row(start: int, end: int, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var tag := Label.new()
	tag.text = label
	tag.custom_minimum_size = Vector2(48, 0)
	tag.add_theme_font_size_override("font_size", int(UiScale.CAPTION * 0.7))
	row.add_child(tag)
	for i in range(start, end):
		var cell := _make_cell(i)
		_cells.append(cell)
		row.add_child(cell["root"])
	return row


func _make_cell(index: int) -> Dictionary:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(88, 96)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)

	var par := 4
	if index < GameState.course.size():
		par = int(GameState.course[index].par)

	var hnum := Label.new()
	hnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hnum.add_theme_font_size_override("font_size", int(UiScale.CAPTION * 0.55))
	hnum.text = "%d" % (index + 1)
	root.add_child(hnum)

	var p_lab := Label.new()
	p_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lab.add_theme_font_size_override("font_size", int(UiScale.CAPTION * 0.5))
	p_lab.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
	p_lab.text = "p%d" % par
	root.add_child(p_lab)

	var mark_host := Control.new()
	mark_host.custom_minimum_size = Vector2(0, 40)
	mark_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mark_host)

	var stroke_lab := Label.new()
	stroke_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stroke_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stroke_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stroke_lab.add_theme_font_size_override("font_size", UiScale.BODY)
	stroke_lab.text = "·"
	mark_host.add_child(stroke_lab)

	var mark_draw := _ScoreMarkDraw.new()
	mark_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_host.add_child(mark_draw)

	return {
		"root": root,
		"par": par,
		"strokes": stroke_lab,
		"mark": mark_draw,
		"diff": null,
		"revealed": false,
	}


func reveal_hole(hole_index: int, diff: int) -> void:
	if hole_index < 0 or hole_index >= _cells.size():
		return
	_apply_cell(hole_index, diff, 0.0)
	var cell: Dictionary = _cells[hole_index]
	var mark: _ScoreMarkDraw = cell["mark"]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		mark.draw_progress = v
		mark.queue_redraw()
	, 0.0, 1.0, REVEAL_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_refresh_totals()
	_refresh_tab()


func reveal_all() -> void:
	for i in GameState.hole_scores.size():
		if i < _cells.size():
			_apply_cell(i, int(GameState.hole_scores[i]), 1.0)
	_refresh_totals()
	_refresh_tab()


## Embed full card in another panel (round complete) without tab/dim chrome.
func present_embedded() -> void:
	visible = true
	_tab_btn.visible = false
	_dim.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_btn.visible = false
	_panel.visible = true
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 0.0
	_panel.offset_top = 0.0
	_panel.offset_right = 0.0
	_panel.offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	populate()
	reveal_all()


func _apply_cell(i: int, diff: int, progress: float) -> void:
	var cell: Dictionary = _cells[i]
	var par: int = int(cell["par"])
	var strokes := par + diff
	var lab: Label = cell["strokes"]
	lab.text = "%d" % strokes
	cell["diff"] = diff
	cell["revealed"] = true
	var mark: _ScoreMarkDraw = cell["mark"]
	mark.result = Scoring.result_from_diff(diff)
	mark.draw_progress = progress
	mark.queue_redraw()


func _refresh_totals() -> void:
	var out_par := 0
	var out_st := 0
	var in_par := 0
	var in_st := 0
	var out_n := 0
	var in_n := 0
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		var par: int = int(cell["par"])
		if i < 9:
			out_par += par
			if cell["revealed"]:
				out_st += par + int(cell["diff"])
				out_n += 1
		else:
			in_par += par
			if cell["revealed"]:
				in_st += par + int(cell["diff"])
				in_n += 1
	_out_lab.text = "OUT  par %d · scored %s" % [
		out_par, str(out_st) if out_n > 0 else "—"
	]
	_in_lab.text = "IN  par %d · scored %s" % [
		in_par, str(in_st) if in_n > 0 else "—"
	]
	var tot := GameState.format_score_to_par(GameState.score_to_par)
	_tot_lab.text = "TOTAL  %s" % tot
	_to_par.text = tot


func _refresh_tab() -> void:
	var tot := GameState.format_score_to_par(GameState.score_to_par)
	var n := GameState.hole_scores.size()
	if n <= 0:
		_tab_btn.text = "Card  %s" % tot
	else:
		var last := int(GameState.hole_scores[n - 1])
		var mark := _tab_mark_char(Scoring.result_from_diff(last))
		_tab_btn.text = "Card %s %s" % [mark, tot]


func _tab_mark_char(r: Scoring.Result) -> String:
	match r:
		Scoring.Result.ALBATROSS, Scoring.Result.EAGLE:
			return "◎"
		Scoring.Result.BIRDIE:
			return "○"
		Scoring.Result.BOGEY:
			return "□"
		Scoring.Result.DOUBLE_PLUS:
			return "▣"
		_:
			return "·"


func show_for_stroke_play() -> void:
	visible = GameState.is_stroke_play()
	_tab_btn.visible = visible
	if visible:
		set_expanded(false)
		populate()


func hide_card() -> void:
	visible = false
	set_expanded(false)


## Child that draws golf marks.
class _ScoreMarkDraw:
	extends Control
	var result: Scoring.Result = Scoring.Result.PAR
	var draw_progress: float = 0.0

	func _draw() -> void:
		if draw_progress <= 0.01:
			return
		if result == Scoring.Result.PAR:
			return
		var c := size * 0.5
		var under := (
			result == Scoring.Result.BIRDIE
			or result == Scoring.Result.EAGLE
			or result == Scoring.Result.ALBATROSS
		)
		var col := Color(1.0, 0.88, 0.35, 1.0) if under else Color(0.55, 0.62, 0.72, 1.0)
		var t := clampf(draw_progress, 0.0, 1.0)
		match result:
			Scoring.Result.BIRDIE:
				_draw_arc_stroke(c, minf(size.x, size.y) * 0.32, col, t)
			Scoring.Result.EAGLE, Scoring.Result.ALBATROSS:
				_draw_arc_stroke(c, minf(size.x, size.y) * 0.36, col, t)
				_draw_arc_stroke(c, minf(size.x, size.y) * 0.24, col, t)
			Scoring.Result.BOGEY:
				_draw_square_stroke(c, minf(size.x, size.y) * 0.55, col, t)
			Scoring.Result.DOUBLE_PLUS:
				_draw_square_stroke(c, minf(size.x, size.y) * 0.62, col, t)
				_draw_square_stroke(c, minf(size.x, size.y) * 0.42, col, t)
			_:
				pass

	func _draw_arc_stroke(c: Vector2, r: float, col: Color, t: float) -> void:
		var segs := 28
		var end_a := TAU * t
		var pts := PackedVector2Array()
		for i in segs + 1:
			var a := -PI * 0.5 + end_a * (float(i) / float(segs))
			if a > -PI * 0.5 + end_a + 0.001:
				break
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if pts.size() >= 2:
			draw_polyline(pts, col, 2.5, true)

	func _draw_square_stroke(c: Vector2, side: float, col: Color, t: float) -> void:
		var h := side * 0.5
		var corners := PackedVector2Array([
			c + Vector2(-h, -h),
			c + Vector2(h, -h),
			c + Vector2(h, h),
			c + Vector2(-h, h),
			c + Vector2(-h, -h),
		])
		var total_len := side * 4.0
		var want := total_len * t
		var drawn := 0.0
		var out := PackedVector2Array()
		out.append(corners[0])
		for i in 4:
			var a := corners[i]
			var b := corners[i + 1]
			var seg := a.distance_to(b)
			if drawn + seg <= want:
				out.append(b)
				drawn += seg
			else:
				var u := (want - drawn) / maxf(seg, 0.001)
				out.append(a.lerp(b, clampf(u, 0.0, 1.0)))
				break
		if out.size() >= 2:
			draw_polyline(out, col, 2.5, true)

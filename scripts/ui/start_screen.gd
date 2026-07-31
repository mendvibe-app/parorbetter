extends Control

signal start_pressed
signal stroke_play_pressed
signal green_pressed
signal range_pressed
signal coach_pressed

@onready var score_label: Label = $Panel/RecordBox/Inner/ScoreRow/RecordCol/ScoreLabel
@onready var deepest_label: Label = $Panel/RecordBox/Inner/DeepestLabel
@onready var start_btn: Button = $Panel/Buttons/StartButton
@onready var stroke_play_btn: Button = $Panel/Buttons/StrokePlayButton
@onready var green_btn: Button = $Panel/Buttons/GreenButton
@onready var range_btn: Button = $Panel/Buttons/RangeButton
@onready var coach_btn: Button = $Panel/Buttons/CoachButton

var _hcp_label: Label


func _ready() -> void:
	visible = false
	start_btn.pressed.connect(func():
		AudioBus.play_ui()
		start_pressed.emit()
	)
	if stroke_play_btn:
		stroke_play_btn.pressed.connect(func():
			AudioBus.play_ui()
			stroke_play_pressed.emit()
		)
	green_btn.pressed.connect(func():
		AudioBus.play_ui()
		green_pressed.emit()
	)
	range_btn.pressed.connect(func():
		AudioBus.play_ui()
		range_pressed.emit()
	)
	coach_btn.pressed.connect(func():
		AudioBus.play_ui()
		coach_pressed.emit()
	)
	_setup_hcp_label()


func _setup_hcp_label() -> void:
	## Small line under 18 Hole Round for handicap status.
	if stroke_play_btn == null:
		return
	_hcp_label = Label.new()
	_hcp_label.name = "HcpLabel"
	_hcp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hcp_label.add_theme_font_size_override("font_size", UiScale.CAPTION)
	_hcp_label.add_theme_color_override("font_color", UiScale.TEXT_SECONDARY)
	_hcp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var buttons := stroke_play_btn.get_parent()
	if buttons:
		var idx := stroke_play_btn.get_index()
		buttons.add_child(_hcp_label)
		buttons.move_child(_hcp_label, idx + 1)


func show_screen() -> void:
	_refresh_record()
	coach_btn.visible = true
	visible = true


func hide_screen() -> void:
	visible = false


func _refresh_record() -> void:
	## Dual records: Survival + 18 Hole Round, always labeled.
	var surv := "—"
	if GameState.has_finished_course:
		surv = GameState.format_score_to_par(GameState.best_score_to_par)
	elif GameState.best_deepest_hole > 0:
		surv = "Hole %d" % GameState.best_deepest_hole
	var stroke := "—"
	if GameState.has_finished_stroke_round:
		stroke = GameState.format_score_to_par(GameState.best_stroke_score_to_par)
	score_label.text = "Survival %s" % surv
	deepest_label.text = "18 Hole %s" % stroke
	deepest_label.visible = true
	if _hcp_label:
		_hcp_label.text = GameState.handicap_label()

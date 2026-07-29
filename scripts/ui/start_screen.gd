extends Control

signal start_pressed
signal green_pressed
signal range_pressed
signal coach_pressed

@onready var score_label: Label = $Panel/RecordBox/Inner/ScoreRow/RecordCol/ScoreLabel
@onready var deepest_label: Label = $Panel/RecordBox/Inner/DeepestLabel
@onready var start_btn: Button = $Panel/Buttons/StartButton
@onready var green_btn: Button = $Panel/Buttons/GreenButton
@onready var range_btn: Button = $Panel/Buttons/RangeButton
@onready var coach_btn: Button = $Panel/Buttons/CoachButton


func _ready() -> void:
	visible = false
	start_btn.pressed.connect(func():
		AudioBus.play_ui()
		start_pressed.emit()
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


func show_screen() -> void:
	_refresh_record()
	coach_btn.visible = true
	visible = true


func hide_screen() -> void:
	visible = false


func _refresh_record() -> void:
	## Primary = score to par once you've cleared a course; else deepest hole.
	if GameState.has_finished_course:
		score_label.text = GameState.format_score_to_par(GameState.best_score_to_par)
		deepest_label.text = "Hole %d" % GameState.best_deepest_hole
		deepest_label.visible = GameState.best_deepest_hole > 0
	elif GameState.best_deepest_hole > 0:
		score_label.text = str(GameState.best_deepest_hole)
		deepest_label.text = "deepest"
		deepest_label.visible = true
	else:
		score_label.text = "—"
		deepest_label.visible = false

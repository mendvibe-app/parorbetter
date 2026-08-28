extends Control

signal start_pressed
signal stroke_play_pressed
signal green_pressed
signal range_pressed
signal short_game_pressed
signal coach_pressed

@onready var score_label: Label = $Panel/Hero/RecordBox/Inner/ScoreRow/RecordCol/ScoreLabel
@onready var deepest_label: Label = $Panel/Hero/RecordBox/Inner/DeepestLabel
@onready var hcp_label: Label = $Panel/Hero/RecordBox/Inner/HcpLabel
@onready var start_btn: Button = $Panel/Buttons/StartButton
@onready var stroke_play_btn: Button = $Panel/Buttons/StrokePlayButton
@onready var green_btn: Button = $Panel/Buttons/GreenButton
@onready var range_btn: Button = $Panel/Buttons/RangeButton
@onready var short_game_btn: Button = $Panel/Buttons/ShortGameButton
@onready var coach_btn: Button = $Panel/Buttons/CoachButton
@onready var golfer_hint: TextureButton = $Panel/Hero/HandPick/GolferHint
@onready var hand_label: Button = $Panel/Hero/HandPick/HandLabel


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
	if short_game_btn:
		short_game_btn.pressed.connect(func():
			AudioBus.play_ui()
			short_game_pressed.emit()
		)
	coach_btn.pressed.connect(func():
		AudioBus.play_ui()
		coach_pressed.emit()
	)
	if golfer_hint:
		golfer_hint.pressed.connect(_on_hand_pressed)
	if hand_label:
		hand_label.pressed.connect(_on_hand_pressed)
	_refresh_hand()


func show_screen() -> void:
	_refresh_record()
	_refresh_hand()
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
	if hcp_label:
		hcp_label.text = GameState.handicap_label()


func _on_hand_pressed() -> void:
	AudioBus.play_ui()
	GameState.set_left_handed(not GameState.left_handed)
	_refresh_hand()


func _refresh_hand() -> void:
	if hand_label:
		hand_label.text = "Left-handed" if GameState.left_handed else "Right-handed"
	if golfer_hint:
		golfer_hint.flip_h = GameState.left_handed

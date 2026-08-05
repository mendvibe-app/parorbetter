extends Control

signal restart_pressed

@onready var title: Label = $Panel/Title
@onready var detail: Label = $Panel/Detail
@onready var restart_btn: Button = $Panel/RestartButton

var _score_host: Control
var _scorecard: ScoreCard


func _ready() -> void:
	visible = false
	restart_btn.pressed.connect(func():
		AudioBus.play_ui()
		restart_pressed.emit()
	)
	_score_host = Control.new()
	_score_host.name = "ScoreHost"
	_score_host.custom_minimum_size = Vector2(0, 300)
	_score_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Panel.add_child(_score_host)
	$Panel.move_child(_score_host, restart_btn.get_index())
	_scorecard = ScoreCard.new()
	_scorecard.name = "SummaryScoreCard"
	_score_host.add_child(_scorecard)
	_scorecard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scorecard.visible = false


func show_result(deepest: int, reason: String) -> void:
	visible = true
	if GameState.is_stroke_play() or (reason == "course_complete" and GameState.stroke_play_mode):
		_show_stroke_complete()
		return
	if _score_host:
		_score_host.visible = false
	if _scorecard:
		_scorecard.hide_card()
		_scorecard.visible = false
	if reason == "course_complete":
		title.text = "COURSE CLEAR"
		detail.text = "Survival — finished all %d holes.\nScore %s · Deepest: %d" % [
			GameState.HOLE_COUNT,
			GameState.format_score_to_par(GameState.score_to_par),
			deepest,
		]
	else:
		title.text = "GAME OVER"
		detail.text = "Survival — keep the card alive.\nDeepest hole reached: %d / %d" % [
			deepest, GameState.HOLE_COUNT
		]


func _show_stroke_complete() -> void:
	title.text = "ROUND COMPLETE"
	var gross := GameState.format_score_to_par(GameState.score_to_par)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("18 Hole Round")
	lines.append("Gross  %s" % gross)
	if GameState.handicap_index() != null:
		lines.append("Net  %s" % GameState.format_score_to_par(GameState.net_score_to_par))
		lines.append(GameState.handicap_label())
	detail.text = "\n".join(lines)
	if _score_host:
		_score_host.visible = true
	if _scorecard:
		_scorecard.present_embedded()


func hide_panel() -> void:
	AudioBus.stop_water_hazard()
	visible = false
	if _scorecard:
		_scorecard.hide_card()
		_scorecard.visible = false
	if _score_host:
		_score_host.visible = false

extends Control

signal restart_pressed

@onready var title: Label = $Panel/Title
@onready var detail: Label = $Panel/Detail
@onready var restart_btn: Button = $Panel/RestartButton


func _ready() -> void:
	visible = false
	restart_btn.pressed.connect(func():
		AudioBus.play_ui()
		restart_pressed.emit()
	)


func show_result(deepest: int, reason: String) -> void:
	visible = true
	if reason == "course_complete":
		title.text = "COURSE CLEAR"
		detail.text = "You finished all %d holes.\nDeepest: %d" % [GameState.HOLE_COUNT, deepest]
	else:
		title.text = "GAME OVER"
		detail.text = "Par or Better — keep the card alive.\nDeepest hole reached: %d / %d" % [deepest, GameState.HOLE_COUNT]


func hide_panel() -> void:
	visible = false

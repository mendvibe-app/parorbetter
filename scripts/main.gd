extends Node

@onready var hole_controller: HoleController = $Hole
@onready var game_over: Control = $UIOverlay/GameOver
@onready var debug_panel: Control = $UIOverlay/DebugPanel


func _ready() -> void:
	hole_controller.request_next_hole.connect(_on_next_hole)
	hole_controller.request_game_over.connect(_on_game_over)
	hole_controller.hole_finished.connect(_on_hole_finished)
	game_over.restart_pressed.connect(_on_restart)
	debug_panel.skip_hole.connect(func(): hole_controller.skip_hole())
	debug_panel.jump_hole.connect(_on_jump)
	debug_panel.force_perfect.connect(func(): hole_controller.debug_force_shot(true))
	debug_panel.force_mishit.connect(func(): hole_controller.debug_force_shot(false))
	debug_panel.reload_hole.connect(func(): hole_controller.load_hole(GameState.current_hole))
	_start_run()


func _start_run() -> void:
	game_over.hide_panel()
	GameState.reset_run()
	hole_controller.load_hole(1)


func _on_next_hole() -> void:
	if GameState.advance_hole():
		hole_controller.load_hole(GameState.current_hole)


func _on_game_over() -> void:
	game_over.show_result(GameState.deepest_hole, "out_of_lives" if GameState.lives <= 0 else "course_complete")


func _on_hole_finished(_strokes: int, _par: int, _result: Scoring.Result) -> void:
	pass


func _on_restart() -> void:
	_start_run()


func _on_jump(index: int) -> void:
	GameState.jump_to_hole(index)
	hole_controller.load_hole(index)








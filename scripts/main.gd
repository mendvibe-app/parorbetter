extends Node

@onready var hole_controller: HoleController = $Hole
@onready var game_over: Control = $UIOverlay/GameOver
@onready var start_screen: Control = $UIOverlay/StartScreen
@onready var debug_panel: Control = $UIOverlay/DebugPanel

var coach_screen: CoachScreen


func _ready() -> void:
	coach_screen = CoachScreen.new()
	coach_screen.name = "CoachScreen"
	$UIOverlay.add_child(coach_screen)
	coach_screen.dismissed.connect(_on_coach_dismissed)

	hole_controller.request_next_hole.connect(_on_next_hole)
	hole_controller.request_game_over.connect(_on_game_over)
	game_over.restart_pressed.connect(_on_restart)
	start_screen.start_pressed.connect(_on_start)
	start_screen.green_pressed.connect(_on_practice_green)
	start_screen.range_pressed.connect(_on_practice_range)
	start_screen.coach_pressed.connect(_on_coach)
	debug_panel.skip_hole.connect(func(): hole_controller.skip_hole())
	debug_panel.jump_hole.connect(_on_jump)
	debug_panel.force_perfect.connect(func(): hole_controller.debug_force_shot(true))
	debug_panel.force_mishit.connect(func(): hole_controller.debug_force_shot(false))
	debug_panel.reload_hole.connect(_on_debug_reload)
	if hole_controller.hud and hole_controller.hud.has_signal("menu_pressed"):
		hole_controller.hud.menu_pressed.connect(_return_to_start)
	_return_to_start()


func _return_to_start() -> void:
	AudioBus.stop_music()
	game_over.hide_panel()
	if GameState.in_practice():
		GameState.exit_range_mode()
		GameState.exit_green_mode()
	start_screen.show_screen()


func _on_start() -> void:
	start_screen.hide_screen()
	_start_run()


func _on_practice_green() -> void:
	start_screen.hide_screen()
	game_over.hide_panel()
	AudioBus.start_music()
	hole_controller.load_practice_green()


func _on_practice_range() -> void:
	start_screen.hide_screen()
	game_over.hide_panel()
	AudioBus.start_music()
	hole_controller.load_range()


func _start_run() -> void:
	game_over.hide_panel()
	GameState.reset_run()
	AudioBus.start_music()
	hole_controller.load_hole(1)


func _on_next_hole() -> void:
	if GameState.advance_hole():
		hole_controller.load_hole(GameState.current_hole)


func _on_game_over() -> void:
	game_over.show_result(GameState.deepest_hole, "out_of_lives" if GameState.lives <= 0 else "course_complete")


func _on_restart() -> void:
	_return_to_start()


func _on_coach() -> void:
	start_screen.hide_screen()
	coach_screen.present()


func _on_coach_dismissed() -> void:
	start_screen.show_screen()


func _on_jump(index: int) -> void:
	GameState.jump_to_hole(index)
	hole_controller.load_hole(index)


func _on_debug_reload() -> void:
	## Apply Tweaks reloads whatever practice/course context is active.
	if GameState.range_mode:
		hole_controller.load_range()
	elif GameState.green_mode:
		hole_controller.load_practice_green()
	else:
		hole_controller.load_hole(GameState.current_hole)

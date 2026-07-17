extends Control

signal skip_hole
signal jump_hole(index: int)
signal force_perfect
signal force_mishit
signal reload_hole

@onready var panel: PanelContainer = $Panel
@onready var metrics: Label = $Panel/VBox/Metrics
@onready var hole_spin: SpinBox = $Panel/VBox/HoleRow/HoleSpin
@onready var lives_spin: SpinBox = $Panel/VBox/LivesRow/LivesSpin
@onready var timing_slider: HSlider = $Panel/VBox/TimingRow/TimingSlider
@onready var wind_slider: HSlider = $Panel/VBox/WindRow/WindSlider
@onready var fairway_slider: HSlider = $Panel/VBox/FairwayRow/FairwaySlider


func _ready() -> void:
	visible = true
	panel.visible = false
	hole_spin.min_value = 1
	hole_spin.max_value = GameState.HOLE_COUNT
	hole_spin.value = 1
	lives_spin.min_value = 0
	lives_spin.max_value = GameState.MAX_LIVES
	lives_spin.value = GameState.lives
	timing_slider.value = 1.0
	wind_slider.value = 1.0
	fairway_slider.value = 1.0
	$Panel/VBox/ToggleHint.text = "F1 / Debug — toggle"
	$Panel/VBox/Buttons/SkipBtn.pressed.connect(func(): skip_hole.emit())
	$Panel/VBox/Buttons/JumpBtn.pressed.connect(func(): jump_hole.emit(int(hole_spin.value)))
	$Panel/VBox/Buttons/PerfectBtn.pressed.connect(func():
		GameState.force_perfect = true
		force_perfect.emit()
		GameState.force_perfect = false
	)
	$Panel/VBox/Buttons/MishitBtn.pressed.connect(func():
		GameState.force_mishit = true
		force_mishit.emit()
		GameState.force_mishit = false
	)
	$Panel/VBox/Buttons/ApplyBtn.pressed.connect(_apply_tweaks)
	$Panel/VBox/LivesRow/SetLivesBtn.pressed.connect(func():
		GameState.set_lives(int(lives_spin.value))
	)
	GameState.hole_changed.connect(func(_i: int):
		hole_spin.max_value = GameState.HOLE_COUNT
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		panel.visible = not panel.visible
		AudioBus.play_ui()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	var m: Dictionary = GameState.last_shot_metrics
	if m.is_empty():
		metrics.text = "Adapt: %s (%.2f)\nForm: %s (%.2f) circle %d yd\nLast shot: —" % [
			Adaptation.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			GameState.get_form(),
			int(GameState.get_aim_radius_yards(false)),
		]
	else:
		metrics.text = "Adapt: %s (%.2f)\nForm: %s · Aim ○ %d yd · %s\n%s\nPwr %d%%  Stance %d%%  Path %+.2f\nContact %s  Lie %s\nPlan %d yd → Actual %s" % [
			Adaptation.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			int(float(m.get("aim_radius_yd", GameState.get_aim_radius_yards(false)))),
			str(m.get("aim_offset", "")),
			str(m.get("summary", "")),
			int(float(m.get("power", 0.0)) * 100.0),
			int(float(m.get("stability", 0.0)) * 100.0),
			float(m.get("path_error", 0.0)),
			str(m.get("contact", "")).to_upper(),
			str(m.get("lie", "")),
			int(float(m.get("planned_yd", 0.0))),
			("%d yd" % int(float(m.get("actual_yd")))) if m.has("actual_yd") else "—",
		]


func _apply_tweaks() -> void:
	GameState.debug_timing_scale = timing_slider.value
	GameState.debug_wind_scale = wind_slider.value
	GameState.debug_fairway_scale = fairway_slider.value
	reload_hole.emit()
	AudioBus.play_ui()


func _on_debug_button_pressed() -> void:
	panel.visible = not panel.visible

extends Control

signal skip_hole
signal jump_hole(index: int)
signal force_perfect
signal force_mishit
signal reload_hole
signal enter_range
signal exit_range

@onready var panel: PanelContainer = $Panel
@onready var metrics: Label = $Panel/VBox/Metrics
@onready var hole_spin: SpinBox = $Panel/VBox/HoleRow/HoleSpin
@onready var lives_spin: SpinBox = $Panel/VBox/LivesRow/LivesSpin
@onready var timing_slider: HSlider = $Panel/VBox/TimingRow/TimingSlider
@onready var wind_slider: HSlider = $Panel/VBox/WindRow/WindSlider
@onready var fairway_slider: HSlider = $Panel/VBox/FairwayRow/FairwaySlider
@onready var tol_slider: HSlider = $Panel/VBox/TolRow/TolSlider
@onready var bal_slider: HSlider = $Panel/VBox/BalRow/BalSlider
@onready var ema_slider: HSlider = $Panel/VBox/EmaRow/EmaSlider
@onready var release_check: CheckButton = $Panel/VBox/ReleaseRow/ReleaseCheck
@onready var guide_check: CheckButton = $Panel/VBox/GuideRow/GuideCheck


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
	tol_slider.value = 1.0
	bal_slider.value = 1.0
	ema_slider.value = TempoGesture.EMA_ALPHA
	release_check.button_pressed = TempoGesture.RELEASE_IS_IMPACT
	guide_check.button_pressed = GameState.tempo_guide_enabled
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
	$Panel/VBox/Buttons/RangeBtn.pressed.connect(func():
		enter_range.emit()
		AudioBus.play_ui()
	)
	$Panel/VBox/Buttons/ExitRangeBtn.pressed.connect(func():
		exit_range.emit()
		AudioBus.play_ui()
	)
	$Panel/VBox/LivesRow/SetLivesBtn.pressed.connect(func():
		GameState.set_lives(int(lives_spin.value))
	)
	release_check.toggled.connect(func(on: bool): TempoGesture.RELEASE_IS_IMPACT = on)
	guide_check.toggled.connect(func(on: bool):
		GameState.tempo_guide_enabled = on
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
	var t: Dictionary = GameState.last_tempo_metrics
	var tempo_line := "Tempo: —"
	if not t.is_empty():
		tempo_line = "Tempo %.1f:1 (tgt %.0f)  bal %d%%  %d/%dms\n%s" % [
			float(t.get("ratio", 0.0)),
			float(t.get("target", 3.0)),
			int(float(t.get("balance", 0.0)) * 100.0),
			int(t.get("backswing_ms", 0)),
			int(t.get("downswing_ms", 0)),
			str(t.get("note", "")),
		]
	if m.is_empty():
		metrics.text = "Adapt: %s (%.2f)\nForm: %s (%.2f) circle %d yd\n%s\nLast shot: —" % [
			GameState.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			GameState.get_form(),
			int(GameState.get_aim_radius_yards(false)),
			tempo_line,
		]
	else:
		metrics.text = "Adapt: %s (%.2f)\nForm: %s · Aim ○ %d yd · %s\n%s\n%s\nPwr %d%%  Bal %d%%  Path %+.2f\nContact %s  Lie %s\nPlan %d yd → Actual %s" % [
			GameState.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			int(float(m.get("aim_radius_yd", GameState.get_aim_radius_yards(false)))),
			str(m.get("aim_offset", "")),
			tempo_line,
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
	GameState.debug_tempo_tol = tol_slider.value
	GameState.debug_balance_tighten = bal_slider.value
	TempoGesture.EMA_ALPHA = ema_slider.value
	TempoGesture.RELEASE_IS_IMPACT = release_check.button_pressed
	GameState.tempo_guide_enabled = guide_check.button_pressed
	if GameState.range_mode:
		enter_range.emit()
	else:
		reload_hole.emit()
	AudioBus.play_ui()


func _on_debug_button_pressed() -> void:
	panel.visible = not panel.visible

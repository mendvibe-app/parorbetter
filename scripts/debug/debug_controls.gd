extends Control

signal skip_hole
signal jump_hole(index: int)
signal force_perfect
signal force_mishit
signal reload_hole

@onready var panel: PanelContainer = $Panel
@onready var panel_margin: MarginContainer = $Panel/Margin
@onready var metrics: Label = $Panel/Margin/Root/Scroll/VBox/Metrics
@onready var club_coach_label: Label = $Panel/Margin/Root/Scroll/VBox/ClubCoachLabel
@onready var hole_spin: SpinBox = $Panel/Margin/Root/Scroll/VBox/HoleRow/HoleSpin
@onready var lives_spin: SpinBox = $Panel/Margin/Root/Scroll/VBox/LivesRow/LivesSpin
@onready var timing_slider: HSlider = $Panel/Margin/Root/Scroll/VBox/TimingRow/TimingSlider
@onready var wind_slider: HSlider = $Panel/Margin/Root/Scroll/VBox/WindRow/WindSlider
@onready var fairway_slider: HSlider = $Panel/Margin/Root/Scroll/VBox/FairwayRow/FairwaySlider
@onready var tol_slider: HSlider = $Panel/Margin/Root/Scroll/VBox/TolRow/TolSlider
@onready var bal_slider: HSlider = $Panel/Margin/Root/Scroll/VBox/BalRow/BalSlider


func _ready() -> void:
	visible = true
	panel.visible = false
	_park_below_hud()
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
	$Panel/Margin/Root/TitleBar/ToggleHint.text = "Debug Menu"
	$Panel/Margin/Root/TitleBar/CloseBtn.pressed.connect(func():
		panel.visible = false
		AudioBus.play_ui()
	)
	$Panel/Margin/Root/Scroll/VBox/Buttons/SkipBtn.pressed.connect(func(): skip_hole.emit())
	$Panel/Margin/Root/Scroll/VBox/Buttons/JumpBtn.pressed.connect(func(): jump_hole.emit(int(hole_spin.value)))
	$Panel/Margin/Root/Scroll/VBox/Buttons/PerfectBtn.pressed.connect(func():
		GameState.force_perfect = true
		force_perfect.emit()
		GameState.force_perfect = false
	)
	$Panel/Margin/Root/Scroll/VBox/Buttons/MishitBtn.pressed.connect(func():
		GameState.force_mishit = true
		force_mishit.emit()
		GameState.force_mishit = false
	)
	$Panel/Margin/Root/Scroll/VBox/Buttons/ApplyBtn.pressed.connect(_apply_tweaks)
	$Panel/Margin/Root/Scroll/VBox/LivesRow/SetLivesBtn.pressed.connect(func():
		GameState.set_lives(int(lives_spin.value))
	)
	GameState.hole_changed.connect(func(_i: int):
		hole_spin.max_value = GameState.HOLE_COUNT
	)


func _park_below_hud() -> void:
	## Sit under the HUD strip (incl. safe-area top) so Debug never shares AdaptLabel's band.
	var btn := $DebugButton as Control
	var margins := UiScale.viewport_safe_margins(get_viewport())
	var top := margins.y
	var y0 := UiScale.HUD_HEIGHT + top + 8.0
	btn.offset_top = y0
	btn.offset_bottom = y0 + 60.0
	## Full-page panel: pad for the notch/home-indicator instead of docking to a corner.
	panel_margin.add_theme_constant_override("margin_top", int(24.0 + top))
	panel_margin.add_theme_constant_override("margin_bottom", int(24.0 + margins.w))


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
	var shot_type := str(m.get("shot_type", "")) if not m.is_empty() else ""
	var type_bit := (" [%s]" % shot_type) if not shot_type.is_empty() else ""
	var tempo_line := "Tempo: —%s" % type_bit
	if not t.is_empty():
		if t.has("target_frac"):
			tempo_line = "Putt frac %.2f (tgt %.2f)  bal %d%%%s\n%s" % [
				float(t.get("actual_frac", 0.0)),
				float(t.get("target_frac", 0.0)),
				int(float(t.get("balance", 0.0)) * 100.0),
				type_bit,
				str(t.get("note", "")),
			]
		else:
			var tgt := float(t.get("target", 3.0))
			var accel_hint := "clean<14" if tgt < 2.5 else "clean<8"
			tempo_line = "Tempo %.1f:1 (tgt %.0f)  bal %d%%  %d/%dms%s\naccel %.1f (%s)  jerk %.2f\n%s" % [
				float(t.get("ratio", 0.0)),
				tgt,
				int(float(t.get("balance", 0.0)) * 100.0),
				int(t.get("backswing_ms", 0)),
				int(t.get("downswing_ms", 0)),
				type_bit,
				float(t.get("max_accel", 0.0)),
				accel_hint,
				float(t.get("max_jerk", 0.0)),
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
	club_coach_label.text = _club_coach_dump()


func _club_coach_dump() -> String:
	var clubs: Dictionary = GameState.club_coach.clubs
	var names := clubs.keys()
	names.sort()
	var lines: PackedStringArray = PackedStringArray()
	for club_name in names:
		var stats: Dictionary = clubs[club_name]
		var shots := int(stats.get("shots_logged", 0))
		if shots <= 0:
			continue
		var tally: Dictionary = stats.get("contact_tally", {})
		var contact_bits: PackedStringArray = PackedStringArray()
		for label_pair in [
			["PERFECT", ShotResult.ContactQuality.PERFECT],
			["GOOD", ShotResult.ContactQuality.GOOD],
			["THIN", ShotResult.ContactQuality.THIN],
			["FAT", ShotResult.ContactQuality.FAT],
			["MISS", ShotResult.ContactQuality.MISS],
		]:
			contact_bits.append("%d %s" % [int(tally.get(label_pair[1], 0)), label_pair[0]])
		var path_avg := ClubCoachLog.avg(stats.get("path_error_history", []))
		var tempo_avg := ClubCoachLog.avg(stats.get("tempo_err_history", []))
		var path_word := "slice bias" if path_avg > 0.0 else ("hook bias" if path_avg < 0.0 else "neutral")
		var tempo_word := "rushed" if tempo_avg < 0.0 else ("lingering" if tempo_avg > 0.0 else "neutral")
		var tip := ClubCoachLog.resolve_tip(stats)
		lines.append("%s — %d shots" % [club_name.to_upper(), shots])
		lines.append("  avg %d yd | contact: %s" % [
			int(ClubCoachLog.avg(stats.get("yardage_history", []))),
			" / ".join(contact_bits),
		])
		lines.append("  path avg %+.2f (%s) | tempo avg %+.2f (%s)" % [
			path_avg, path_word, tempo_avg, tempo_word,
		])
		if club_name == "Putter":
			var longest_ft := PuttStroke.yd_to_ft(float(stats.get("longest_made_yards", 0.0)))
			lines.append("  longest putt made: %d ft" % int(round(longest_ft)))
		lines.append("  → resolved tip: %s" % str(tip.get("tag", "")))
	if lines.is_empty():
		return "Club Coach — no shots logged yet"
	return "Club Coach:\n" + "\n".join(lines)


func _apply_tweaks() -> void:
	GameState.debug_timing_scale = timing_slider.value
	GameState.debug_wind_scale = wind_slider.value
	GameState.debug_fairway_scale = fairway_slider.value
	GameState.debug_tempo_tol = tol_slider.value
	GameState.debug_balance_tighten = bal_slider.value
	reload_hole.emit()
	AudioBus.play_ui()


func _on_debug_button_pressed() -> void:
	panel.visible = not panel.visible

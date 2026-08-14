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
var practice_spins: Dictionary = {}  ## shot_type → SpinBox
var _elevation_spark: ElevationSparkline  ## Phase 0 side-elevation profile
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
	_setup_practice_count_row()
	_setup_haptic_smoke_btn()
	_setup_copy_metrics_btn()
	_setup_elevation_sparkline()
	GameState.hole_changed.connect(func(_i: int):
		hole_spin.max_value = GameState.HOLE_COUNT
	)


func _setup_copy_metrics_btn() -> void:
	## Clipboard dump of the live metrics label (and club coach) for paste into chat/notes.
	var vbox := $Panel/Margin/Root/Scroll/VBox as VBoxContainer
	if vbox == null:
		return
	var btn := Button.new()
	btn.name = "CopyMetricsBtn"
	btn.text = "Copy metrics"
	btn.tooltip_text = "Copy F1 metrics text to clipboard"
	btn.pressed.connect(_copy_metrics_to_clipboard)
	var metrics_node := vbox.get_node_or_null("Metrics")
	if metrics_node:
		vbox.add_child(btn)
		vbox.move_child(btn, metrics_node.get_index() + 1)
	else:
		vbox.add_child(btn)


func _copy_metrics_to_clipboard() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if metrics:
		parts.append(metrics.text)
	if club_coach_label and not club_coach_label.text.is_empty():
		parts.append("--- club coach ---")
		parts.append(club_coach_label.text)
	var dump := "\n".join(parts).strip_edges()
	if dump.is_empty():
		dump = "(no metrics yet)"
	DisplayServer.clipboard_set(dump)
	AudioBus.play_ui()
	var btn := $Panel/Margin/Root/Scroll/VBox.get_node_or_null("CopyMetricsBtn") as Button
	if btn:
		var prev := btn.text
		btn.text = "Copied!"
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(btn):
				btn.text = prev
		)


func _setup_haptic_smoke_btn() -> void:
	## Device smoke: F1 → Haptic medium (native plugin or duration fallback).
	var vbox := $Panel/Margin/Root/Scroll/VBox as VBoxContainer
	if vbox == null:
		return
	var btn := Button.new()
	btn.name = "HapticSmokeBtn"
	btn.text = "Haptic medium (smoke)"
	btn.pressed.connect(func() -> void:
		Haptics.init()
		if Haptics.ready():
			Haptics.medium()
		else:
			Input.vibrate_handheld(20)
		AudioBus.play_ui()
	)
	var buttons := vbox.get_node_or_null("Buttons")
	if buttons:
		vbox.add_child(btn)
		vbox.move_child(btn, buttons.get_index() + 1)
	else:
		vbox.add_child(btn)


func _setup_practice_count_row() -> void:
	## Practice swings per shot type (0–3) — prefs until a real settings screen exists.
	var vbox := $Panel/Margin/Root/Scroll/VBox as VBoxContainer
	if vbox == null:
		return
	var block := VBoxContainer.new()
	block.name = "PracticeCountBlock"
	var header := Label.new()
	header.text = "Practice swings (0–3)"
	block.add_child(header)
	var insert_at := -1
	var lives_row := vbox.get_node_or_null("LivesRow")
	if lives_row:
		insert_at = lives_row.get_index() + 1
	for st: String in ["full", "pitch", "chip", "putt"]:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "  %s" % st.capitalize()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 3
		spin.value = GameState.practice_swing_count_for(st)
		spin.rounded = true
		var key: String = st
		spin.value_changed.connect(func(v: float):
			GameState.set_practice_swing_count(key, int(v))
		)
		practice_spins[st] = spin
		row.add_child(lab)
		row.add_child(spin)
		block.add_child(row)
	vbox.add_child(block)
	if insert_at >= 0:
		vbox.move_child(block, insert_at)


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
	# One shot → one metrics story (Phase 3): if tempo empty but shot has path, seed shape fields.
	if t.is_empty() and not m.is_empty() and m.has("path_error"):
		t = {
			"path_error": float(m.get("path_error", 0.0)),
			"swing_shape": float(m.get("path_error", 0.0)),
			"shape_blend": float(m.get("path_error", 0.0)),
			"transition_pull": 0.0,
			"max_lateral": 0.0,
			"note": str(m.get("summary", "")),
		}
	elif not t.is_empty() and not m.is_empty():
		if not t.has("path_error") and m.has("path_error"):
			t["path_error"] = float(m.get("path_error", 0.0))
		if not t.has("swing_shape") and t.has("path_error"):
			t["swing_shape"] = float(t.get("path_error", 0.0))
		if not t.has("shape_blend") and t.has("path_error"):
			t["shape_blend"] = float(t.get("path_error", 0.0))
	var shot_type := str(m.get("shot_type", "")) if not m.is_empty() else ""
	var type_bit := (" [%s]" % shot_type) if not shot_type.is_empty() else ""
	var guide_st := shot_type if not shot_type.is_empty() else "full"
	var guide_bit: String
	if GameState.is_survival() and GameState.run_active:
		guide_bit = " ghost α%.2f H%d/%d" % [
			GameState.guide_alpha_for_shot_type(guide_st),
			GameState.current_hole,
			GameState.HOLE_COUNT,
		]
	else:
		guide_bit = " ghost α%.2f reps%d" % [
			GameState.guide_alpha_for_shot_type(guide_st),
			GameState.shot_type_rep_count(guide_st),
		]
	var tempo_line := "Tempo: —%s%s" % [type_bit, guide_bit]
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
			var accel_hint := (
				"clean<%d" % int(TempoGrade.ACCEL_LO_PITCH)
				if tgt < 2.5
				else "clean<%d" % int(TempoGrade.ACCEL_LO_FULL)
			)
			# guide/Δ/transV: transition-timing verify (debug only; negative Δ = shorter than guide)
			tempo_line = "Tempo %.1f:1 (tgt %.0f)  bal %d%%  %d/%dms (guide %d/%dms, Δ%+.0f%%)%s%s\naccel %.1f (%s)  jerk %.2f  transV %.2f\n%s" % [
				float(t.get("ratio", 0.0)),
				tgt,
				int(float(t.get("balance", 0.0)) * 100.0),
				int(t.get("backswing_ms", 0)),
				int(t.get("downswing_ms", 0)),
				int(t.get("guide_back_ms", 0)),
				int(t.get("guide_down_ms", 0)),
				float(t.get("down_delta_pct", 0.0)),
				type_bit,
				guide_bit,
				float(t.get("max_accel", 0.0)),
				accel_hint,
				float(t.get("max_jerk", 0.0)),
				float(t.get("transition_ratio", 0.0)),
				str(t.get("note", "")),
			]
	# Phase 0 swing instrumentation: amplitude vs aim-solved vs rolled (no unit pick yet).
	# Putt/chip: PuttStroke.actual_frac is what power_from_frac used — not gesture BS keys.
	var amp_line := ""
	var commit_p := float(t.get("committed_power", m.get("committed_power", 0.0)))
	var true_p := float(t.get("true_power", m.get("true_power", 0.0)))
	var rolled_p := float(t.get("rolled_power", m.get("power", 0.0)))
	var putt_family := shot_type == "putt" or shot_type == "chip" or t.has("actual_frac")
	if putt_family and t.has("actual_frac"):
		amp_line = "\nAmp frac %.2f (tgt %.2f) · commit %d%% · true %d%% · rolled %d%%" % [
			float(t.get("actual_frac", 0.0)),
			float(t.get("target_frac", t.get("target", 0.0))),
			int(commit_p * 100.0),
			int(true_p * 100.0),
			int(rolled_p * 100.0),
		]
	elif t.has("backswing_len") or t.has("backswing_frac") or m.has("committed_power"):
		amp_line = "\nAmp BS len %.2f frac %.2f · commit %d%% · true %d%% · rolled %d%%" % [
			float(t.get("backswing_len", 0.0)),
			float(t.get("backswing_frac", 0.0)),
			int(commit_p * 100.0),
			int(true_p * 100.0),
			int(rolled_p * 100.0),
		]
	if m.is_empty():
		metrics.text = "Adapt: %s (%.2f)\nForm: %s (%.2f) circle %d yd\n%s%s\nLast shot: —" % [
			GameState.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			GameState.get_form(),
			int(GameState.get_aim_radius_yards(false)),
			tempo_line,
			amp_line,
		]
	else:
		var h_peak := float(m.get("height_peak", -1.0))
		var h_max := float(m.get("height_max", -1.0))
		var height_line := "Apex —"
		if h_peak >= 0.0 or h_max >= 0.0:
			# Indices: airy=4 (lowest), oak=3 (mid), tall=7 (wall) — single source TREE_CANOPY_H.
			var ch: Array = HoleController.TREE_CANOPY_H
			var airy_h := float(ch[4]) if ch.size() > 4 else 55.0
			var oak_h := float(ch[3]) if ch.size() > 3 else 72.0
			var tall_h := float(ch[7]) if ch.size() > 7 else 92.0
			height_line = "Apex peak %.1f · max %.1f (canopy airy~%.0f oak~%.0f tall~%.0f)" % [
				h_peak if h_peak >= 0.0 else 0.0,
				h_max if h_max >= 0.0 else 0.0,
				airy_h,
				oak_h,
				tall_h,
			]
		var flight: Dictionary = {}
		if shot_type != "putt" and m.get("flight") is Dictionary:
			flight = m["flight"] as Dictionary
		if not flight.is_empty():
			var carry_px := float(flight.get("carry_px", 0.0))
			var planned_px := float(flight.get("planned_px", 0.0))
			var air_frac := float(flight.get("air_fraction", 0.0))
			var hang := float(flight.get("hang_time", 0.0))
			var launch_spd := float(flight.get("launch_speed", 0.0))
			var carry_yd := BallPhysics.pixels_to_yards(carry_px)
			var roll_yd := BallPhysics.pixels_to_yards(maxf(planned_px * (1.0 - air_frac), 0.0))
			height_line += "\nCarry %.0f yd · roll %.0f yd · hang %.2fs · launch %.0f px/s" % [
				carry_yd, roll_yd, hang, launch_spd
			]
			if _elevation_spark:
				var contact_s := str(m.get("contact", "GOOD")).to_upper()
				var actual_yd := float(m.get("actual_yd", 0.0)) if m.has("actual_yd") else 0.0
				_elevation_spark.set_profile(
					carry_px,
					float(flight.get("apex_actual", h_max if h_max >= 0.0 else 0.0)),
					planned_px,
					actual_yd,
					contact_s
				)
		elif _elevation_spark:
			_elevation_spark.clear_profile()
		var path_v := float(m.get("path_error", 0.0))
		var swipe_v := float(t.get("swing_shape", 0.0))
		var pull_v := float(t.get("transition_pull", 0.0))
		var blend_v := float(t.get("shape_blend", 0.0))
		var lat_v := float(t.get("max_lateral", 0.0))
		var sign_tag := "~0"
		if absf(swipe_v) > 0.08 and absf(path_v) > 0.08:
			sign_tag = "SAME" if signf(swipe_v) == signf(path_v) else "FLIP"
		elif absf(swipe_v) > 0.08 or absf(path_v) > 0.08:
			sign_tag = "weak"
		var shape_line := (
			"\nPath %+.2f  (−draw/L  +fade/R)  sign:%s\nShape lat %+.2f swipe %+.2f pull %+.2f → blend %+.2f"
			% [path_v, sign_tag, lat_v, swipe_v, pull_v, blend_v]
		)
		metrics.text = "Adapt: %s (%.2f)\nForm: %s · Aim ○ %d yd · %s\n%s%s\n%s\nPwr %d%%  Bal %d%%  Path %+.2f\nContact %s  Lie %s\nPlan %d yd → Actual %s\n%s%s" % [
			GameState.bias_label(),
			GameState.get_adaptation_bias(),
			GameState.form_label(),
			int(float(m.get("aim_radius_yd", GameState.get_aim_radius_yards(false)))),
			str(m.get("aim_offset", "")),
			tempo_line,
			amp_line,
			str(m.get("summary", "")),
			int(float(m.get("power", 0.0)) * 100.0),
			int(float(m.get("stability", 0.0)) * 100.0),
			path_v,
			str(m.get("contact", "")).to_upper(),
			str(m.get("lie", "")),
			int(float(m.get("planned_yd", 0.0))),
			("%d yd" % int(float(m.get("actual_yd")))) if m.has("actual_yd") else "—",
			height_line,
			shape_line,
		]
	club_coach_label.text = _club_coach_dump()


func _club_coach_dump() -> String:
	var clubs: Dictionary = GameState.club_coach.clubs
	var names: Array = BallPhysics.sort_club_names_by_bag(clubs.keys())
	var lines: PackedStringArray = PackedStringArray()
	for club_name_v in names:
		var club_name := str(club_name_v)
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
		lines.append("%s — %d shots" % [BallPhysics.club_short_name(club_name), shots])
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


func _setup_elevation_sparkline() -> void:
	## Phase 0: side-elevation shot profile under Metrics (code-built, no .tscn edit).
	var vbox := $Panel/Margin/Root/Scroll/VBox as VBoxContainer
	if vbox == null:
		return
	var spark := ElevationSparkline.new()
	spark.name = "ElevationSparkline"
	spark.custom_minimum_size = Vector2(260, 90)
	spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var metrics_node := vbox.get_node_or_null("Metrics")
	vbox.add_child(spark)
	if metrics_node:
		var insert_at := metrics_node.get_index() + 1
		var copy_btn := vbox.get_node_or_null("CopyMetricsBtn")
		if copy_btn:
			insert_at = copy_btn.get_index() + 1
		vbox.move_child(spark, insert_at)
	_elevation_spark = spark


## Side-elevation profile of the last shot (schematic sin arc, not a live trace).
class ElevationSparkline extends Control:
	var _carry_px: float = 0.0
	var _apex: float = 0.0
	var _planned_px: float = 0.0
	var _actual_yd: float = 0.0
	var _contact: String = "GOOD"
	var _has: bool = false

	func set_profile(
		carry_px: float, apex: float, planned_px: float, actual_yd: float, contact: String
	) -> void:
		_carry_px = maxf(carry_px, 0.0)
		_apex = maxf(apex, 0.0)
		_planned_px = maxf(planned_px, 0.0)
		_actual_yd = maxf(actual_yd, 0.0)
		_contact = contact
		_has = _carry_px > 1.0 or _apex > 0.0
		queue_redraw()

	func clear_profile() -> void:
		_has = false
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.08, 0.1, 0.09, 0.95), true)
		draw_rect(r, Color(0.25, 0.3, 0.28, 0.9), false, 1.0)
		var pad := 8.0
		var plot := Rect2(pad, pad, maxf(size.x - pad * 2.0, 4.0), maxf(size.y - pad * 2.0, 4.0))
		# Ref lines from production table (airy / oak / tall) — no second hardcoded scale.
		var ch: Array = HoleController.TREE_CANOPY_H
		var canopies: Array = []
		var labels: Array = []
		if ch.size() > 4:
			canopies.append(float(ch[4]))
			labels.append("airy")
		if ch.size() > 3:
			canopies.append(float(ch[3]))
			labels.append("oak")
		if ch.size() > 7:
			canopies.append(float(ch[7]))
			labels.append("tall")
		var y_max := 48.0
		for ch_v in canopies:
			y_max = maxf(y_max, float(ch_v) * 1.05)
		if _has:
			y_max = maxf(y_max, _apex * 1.15)
		# Canopy reference lines
		for i in canopies.size():
			var h: float = float(canopies[i])
			var ty := plot.position.y + plot.size.y * (1.0 - clampf(h / y_max, 0.0, 1.0))
			var col := Color(0.55, 0.55, 0.5, 0.55)
			_draw_dashed_h(plot.position.x, plot.position.x + plot.size.x, ty, col)
			draw_string(
				UiScale.FONT,
				Vector2(plot.position.x + 2.0, ty - 2.0),
				"%s %.0f" % [labels[i], h],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				col
			)
		if not _has:
			draw_string(
				UiScale.FONT,
				Vector2(plot.position.x + 4.0, plot.position.y + plot.size.y * 0.5),
				"elevation profile — hit a shot",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12,
				Color(0.6, 0.65, 0.6, 0.7)
			)
			return
		# Faint planned-total marker (plan vs actual thesis)
		var x_span := maxf(_carry_px, maxf(_planned_px, 1.0))
		if _planned_px > 1.0:
			var px := plot.position.x + plot.size.x * clampf(_planned_px / x_span, 0.0, 1.0)
			draw_line(
				Vector2(px, plot.position.y),
				Vector2(px, plot.position.y + plot.size.y),
				Color(0.7, 0.7, 0.75, 0.35),
				1.0
			)
		# Curve: sin profile peaking at apex_actual over carry_px (schematic profile)
		var curve_col := Color(0.95, 0.85, 0.25, 0.95)  # GOOD amber
		match _contact:
			"PERFECT":
				curve_col = Color(0.35, 0.92, 0.45, 0.95)
			"GOOD":
				curve_col = Color(0.95, 0.85, 0.25, 0.95)
			_:
				curve_col = Color(0.95, 0.35, 0.3, 0.95)
		var pts := PackedVector2Array()
		var n := 48
		for i in n + 1:
			var t := float(i) / float(n)
			var x := plot.position.x + plot.size.x * t * clampf(_carry_px / x_span, 0.0, 1.0)
			var h := sin(t * PI) * _apex
			var y := plot.position.y + plot.size.y * (1.0 - clampf(h / y_max, 0.0, 1.0))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, curve_col, 2.0, true)
		draw_string(
			UiScale.FONT,
			Vector2(plot.position.x + 2.0, plot.position.y + plot.size.y - 2.0),
			"profile carry %.0fpx apex %.1f  (planned %.0fpx)" % [_carry_px, _apex, _planned_px],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color(0.75, 0.8, 0.75, 0.75)
		)

	func _draw_dashed_h(x0: float, x1: float, y: float, col: Color) -> void:
		var x := x0
		var on := true
		var dash := 4.0
		while x < x1:
			var x2 := minf(x + dash, x1)
			if on:
				draw_line(Vector2(x, y), Vector2(x2, y), col, 1.0)
			on = not on
			x = x2

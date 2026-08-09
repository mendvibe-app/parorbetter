class_name ShotRoutine
extends Control

## Tempo swing: committed pre-shot power × gesture ratio grade.
## Single-thumb drag; desktop LMB. Practice mode grades without launching.

signal shot_ready(result: ShotResult)
signal phase_changed(phase: String)
signal pure_strike(result: ShotResult)
signal practice_result(verdict: Dictionary)
signal back_requested

enum Phase { IDLE, ACTIVE, DONE }

const PURE_BALANCE := 0.72

var phase: Phase = Phase.IDLE
var timing_scale: float = 1.0
var suggested_shape: float = 0.0
var practice_mode: bool = false

var club_name: String = "Iron"
var club_max_yards: float = 180.0
var remaining_yards: float = 160.0
var pin_yards: float = 160.0
var current_lie: String = "Tee"
var current_severity: String = ""
var aim_radius_yd: float = 22.0
var committed_power: float = 0.75
## Uncapped solve % (club select / overclub UI); physics uses committed_power.
var true_power_pct: float = 0.75
var shot_type: String = "full"
## Trees punch: low flight (launch uses "punch"); gesture/grade still full/pitch.
var punch_mode: bool = false
var last_verdict: Dictionary = {}

@onready var info_label: Label = $GlanceRow/InfoLabel
@onready var lie_icon: TextureRect = $GlanceRow/LieIcon
@onready var club_icon: TextureRect = $GlanceRow/ClubIcon
@onready var club_label: Label = $GlanceRow/ClubLabel
@onready var meter_display: MeterDisplay = $MeterDisplay
@onready var tempo_gesture: TempoGesture = $Controls/TempoGesture
@onready var hint_label: Label = $HintLabel

## Re-do window: valid from Confirm until the gesture's first real sample
## (takeaway). Built here (not the .tscn) so it lives in the GlanceRow's
## already-safe strip above the swing pad, never over the live gesture area.
var back_btn: Button
## Practice rep dots (●○) — total = practice_count + 1 (real).
var _rep_row: HBoxContainer


func _ready() -> void:
	tempo_gesture.committed.connect(_on_tempo_committed)
	tempo_gesture.moment.connect(_on_tempo_moment)
	if meter_display:
		meter_display.bind(tempo_gesture)
	_setup_back_btn()
	_setup_rep_row()
	set_active(false)


func _setup_back_btn() -> void:
	back_btn = Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "‹ Back"
	back_btn.visible = false
	back_btn.custom_minimum_size = Vector2(96, 48)
	back_btn.add_theme_font_size_override("font_size", UiScale.CAPTION)
	var glance := get_node_or_null("GlanceRow") as Control
	if glance:
		glance.add_child(back_btn)
		glance.move_child(back_btn, 0)
	back_btn.pressed.connect(func() -> void: back_requested.emit())


func _setup_rep_row() -> void:
	_rep_row = HBoxContainer.new()
	_rep_row.name = "RepDots"
	_rep_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rep_row.add_theme_constant_override("separation", 8)
	_rep_row.visible = false
	_rep_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sit under GlanceRow, above meter/hint — thin strip.
	_rep_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rep_row.offset_left = 16.0
	_rep_row.offset_right = -16.0
	_rep_row.offset_top = 52.0
	_rep_row.offset_bottom = 72.0
	add_child(_rep_row)


func set_rep_indicator(practice_left: int, total_practice: int, is_real: bool) -> void:
	## practice_left includes the current practice rep when is_real is false.
	if _rep_row == null:
		return
	for c in _rep_row.get_children():
		c.queue_free()
	if total_practice <= 0 or GameState.range_mode:
		_rep_row.visible = false
		return
	var slots := total_practice + 1
	var cur := total_practice if is_real else (total_practice - practice_left)
	cur = clampi(cur, 0, slots - 1)
	for i in slots:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == cur:
			dot.color = Color(1.0, 0.85, 0.25, 1.0) if is_real else Color(0.45, 0.85, 1.0, 1.0)
		elif i < cur:
			dot.color = Color(0.35, 0.55, 0.4, 0.9)
		else:
			dot.color = Color(0.2, 0.28, 0.22, 0.75)
		_rep_row.add_child(dot)
	_rep_row.visible = true


func configure(
	lie: String,
	aim_distance_yd: float,
	pin_distance_yd: float,
	wind: Vector2,
	_shape_label: String,
	p_timing: float,
	p_shape: float = 0.0,
	p_aim_radius_yd: float = 22.0,
	p_club_name: String = "",
	p_club_max_yards: float = -1.0,
	p_severity: String = "",
	p_punch: bool = false,
	p_shot_type_override: String = ""
) -> void:
	timing_scale = p_timing
	suggested_shape = p_shape
	current_lie = lie
	current_severity = p_severity
	remaining_yards = aim_distance_yd
	pin_yards = pin_distance_yd
	aim_radius_yd = p_aim_radius_yd
	punch_mode = p_punch and lie == "Trees"
	if GameState.debug_timing_scale != null:
		timing_scale = float(GameState.debug_timing_scale)
	timing_scale *= BallPhysics.lie_timing_scale(lie, p_severity)

	if p_club_max_yards > 0.0 and not p_club_name.is_empty():
		club_name = p_club_name
		club_max_yards = p_club_max_yards
	else:
		var club := BallPhysics.pick_club(pin_distance_yd, lie, p_severity)
		club_name = String(club["name"])
		club_max_yards = float(club["max_yards"])

	var solved := BallPhysics.solve_committed_power(
		aim_distance_yd, club_max_yards, lie, wind, p_severity
	)
	committed_power = float(solved["power"])
	true_power_pct = float(solved["true_pct"])
	# Gesture/grade type; launch uses flight_shot_type() for punch loft/roll.
	# Green always putt. Override only if club-eligible (manual shot-type picker).
	if lie == "Green":
		shot_type = "putt"
	elif not p_shot_type_override.is_empty() and BallPhysics.eligible_shot_types(club_max_yards).has(
		p_shot_type_override
	):
		shot_type = p_shot_type_override
	else:
		shot_type = TempoGrade.recommend_shot_type(lie, aim_distance_yd, club_max_yards)

	# Green: feet (how golfers read putts). Full/pitch stay yards.
	if lie == "Green":
		info_label.text = "%d ft" % int(round(PuttStroke.yd_to_ft(aim_distance_yd)))
	elif absf(aim_distance_yd - pin_distance_yd) < 1.5:
		info_label.text = "%d yd" % int(pin_distance_yd)
	else:
		info_label.text = "Aim %d · pin %d" % [int(aim_distance_yd), int(pin_distance_yd)]
	if lie_icon:
		lie_icon.texture = HudIcons.lie_texture(lie)
	if club_icon:
		club_icon.texture = HudIcons.club_texture(club_name)
	if club_label:
		club_label.text = ("Punch · %s" % club_name) if punch_mode else club_name
	if tempo_gesture:
		tempo_gesture.set_lie_preview(lie, p_severity)


func flight_shot_type() -> String:
	## Physics flight identity (punch lowers apex); not the tempo pad type.
	if punch_mode and shot_type != "putt" and shot_type != "chip":
		return "punch"
	return shot_type


static func _shape_authority(contact: ShotResult.ContactQuality) -> float:
	## Mishits don't produce clean intentional draws (real golf + affordance).
	match contact:
		ShotResult.ContactQuality.PERFECT:
			return 1.0
		ShotResult.ContactQuality.GOOD:
			return 0.85
		ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
			return 0.38
		_:
			return 0.12


func begin_shot(p_practice: bool = false, p_allow_back: bool = false) -> void:
	practice_mode = p_practice
	phase = Phase.ACTIVE
	last_verdict.clear()
	tempo_gesture.reset()
	tempo_gesture.shot_type = shot_type
	# Always pass club max so pad drag head matches bag (driver/wood/hybrid/iron/wedge).
	tempo_gesture.club_max_yards = club_max_yards
	if shot_type == "putt" or shot_type == "chip":
		tempo_gesture.putt_target_frac = PuttStroke.marker_frac(committed_power)
		tempo_gesture.putt_show_marker = practice_mode
	else:
		tempo_gesture.putt_show_marker = false
	tempo_gesture.set_enabled(true)
	if meter_display:
		meter_display.set_shot_context(shot_type, timing_scale, practice_mode)
		if shot_type == "putt" or shot_type == "chip":
			meter_display.set_putt_target(tempo_gesture.putt_target_frac)
	_layout_shot_chrome()
	# One live instruction — golf moments, not engine marks.
	if practice_mode:
		if shot_type == "putt" or shot_type == "chip":
			hint_label.text = "Practice — address · to the pace tick · through the ball."
		elif punch_mode:
			hint_label.text = "PRACTICE PUNCH — low flight · same 3:1 · keep it under."
		else:
			hint_label.text = "PRACTICE ~%.0f:1 — address · to the top · through the ball." % TempoGrade.target_ratio(shot_type)
	elif shot_type == "putt":
		hint_label.text = "Address · feel your pace · through the ball."
	elif shot_type == "chip":
		hint_label.text = "CHIP — feel the distance · small stroke · through the ball."
	elif punch_mode:
		hint_label.text = "PUNCH — low · through the ball · more roll after."
	elif shot_type == "pitch":
		hint_label.text = "PITCH ~2:1 — address · to the top · through the ball."
	else:
		hint_label.text = "SWING ~3:1 — address · to the top · through the ball."
	phase_changed.emit("active")
	set_active(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glance := get_node_or_null("GlanceRow") as Control
	if glance:
		glance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if info_label:
		info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint_label:
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if meter_display:
		meter_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter_display.queue_redraw()
	var bg := get_node_or_null("PanelBG") as Control
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controls := get_node_or_null("Controls") as Control
	if controls:
		controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if back_btn:
		# Same re-do window on practice as real — exit sequence before takeaway.
		back_btn.visible = p_allow_back


func set_active(on: bool) -> void:
	visible = on
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		_layout_shot_chrome()


func layout_shot_chrome() -> void:
	## Meter/hint may hide or shift; pad size is shot-type only so practice = real.
	var show_meter := (
		(practice_mode or GameState.range_mode)
		and shot_type != "putt" and shot_type != "chip"
	)
	var hint_top := UiScale.HINT_TOP_WITH_METER if show_meter else UiScale.HINT_TOP_NO_METER
	# Pad size follows shot type only (putt/chip stay compact) — never practice-vs-real,
	# so the gesture area a player rehearses on is identical to the one they're scored on.
	var pad_top := (
		UiScale.SHOT_PAD_TOP_COMPACT if (shot_type == "putt" or shot_type == "chip")
		else UiScale.SHOT_PAD_TOP
	)
	if meter_display:
		meter_display.offset_top = UiScale.METER_TOP
		meter_display.offset_bottom = UiScale.METER_BOTTOM
	if hint_label:
		hint_label.offset_top = hint_top
		hint_label.offset_bottom = hint_top + UiScale.HINT_HEIGHT
	var controls := get_node_or_null("Controls") as Control
	if controls:
		var m := UiScale.viewport_safe_margins(get_viewport()) if get_viewport() else Vector4.ZERO
		controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		controls.offset_left = 12.0
		controls.offset_right = -12.0
		controls.offset_top = pad_top
		controls.offset_bottom = -(UiScale.CONTROLS_PAD_BOTTOM + m.w)


func _layout_shot_chrome() -> void:
	layout_shot_chrome()


func cancel_shot() -> void:
	## Abort a confirmed shot before the swing gesture has started moving —
	## the re-do window. No verdict was ever computed (that only happens on
	## commit, well past takeaway), so there's nothing to leak: just drop back
	## to idle and let the next configure()/begin_shot() rebuild state fresh.
	phase = Phase.IDLE
	last_verdict.clear()
	tempo_gesture.set_enabled(false)
	tempo_gesture.reset()
	if back_btn:
		back_btn.visible = false
	set_active(false)
	phase_changed.emit("idle")


func force_result(perfect: bool) -> void:
	var contact := ShotResult.ContactQuality.PERFECT if perfect else ShotResult.ContactQuality.FAT
	var path := 0.0 if perfect else 0.65
	var stab := 1.0 if perfect else 0.35
	var power_amt := committed_power if perfect else committed_power * 0.55
	var forced := ShotResult.make(power_amt, stab, path, contact, suggested_shape)
	forced.true_power = true_power_pct
	_emit_result(forced)


func _on_tempo_moment(name: String) -> void:
	if meter_display:
		meter_display.on_moment(name)
	match name:
		"takeaway":
			# Gesture is now in motion — the re-do window is closed for good.
			if back_btn:
				back_btn.visible = false
			if shot_type == "putt":
				AudioBus.play_putt_tick(0.35)
		"marker":
			if shot_type == "putt":
				AudioBus.play_putt_tick(0.7)
		"top":
			pass  # Haptics only at contact quality (see _haptic_impact).
		"impact":
			pass  # Thump fires at commit from contact tier, not the moment tick.


func _on_tempo_committed(sample: Dictionary) -> void:
	if phase != Phase.ACTIVE:
		return

	var tol_scale := 1.0
	if GameState.debug_tempo_tol != null:
		tol_scale = float(GameState.debug_tempo_tol)
	var bal_tighten := 1.0
	if GameState.debug_balance_tighten != null:
		bal_tighten = float(GameState.debug_balance_tighten)

	var verdict: Dictionary
	if shot_type == "putt" or shot_type == "chip":
		var chip_tol := PuttStroke.CHIP_TOL_SCALE if shot_type == "chip" else 1.0
		var chip_arc := PuttStroke.CHIP_ARC_SCALE if shot_type == "chip" else 1.0
		verdict = PuttStroke.grade(sample, committed_power, tol_scale, bal_tighten, club_max_yards, chip_tol, chip_arc)
	else:
		verdict = TempoGrade.grade(
			sample, shot_type, timing_scale, tol_scale, bal_tighten, club_max_yards
		)
	last_verdict = verdict
	GameState.last_tempo_metrics = verdict

	if GameState.force_perfect:
		if shot_type == "putt" or shot_type == "chip":
			var tf := PuttStroke.marker_frac(committed_power)
			verdict = {
				"ratio": 1.0,
				"target": tf,
				"target_frac": tf,
				"actual_frac": tf,
				"follow_frac": tf,
				"balance": 1.0,
				"contact": ShotResult.ContactQuality.PERFECT,
				"power_mul": 1.0,
				"path_error": 0.0,
				"note": "Putt forced perfect",
				"backswing_ms": 400,
				"downswing_ms": 400,
			}
		else:
			verdict = {
				"ratio": TempoGrade.target_ratio(shot_type),
				"target": TempoGrade.target_ratio(shot_type),
				"balance": 1.0,
				"contact": ShotResult.ContactQuality.PERFECT,
				"power_mul": 1.0,
				"path_error": 0.0,
				"note": "Tempo forced perfect",
				"backswing_ms": 750,
				"downswing_ms": 250,
			}
		last_verdict = verdict
		GameState.last_tempo_metrics = verdict
	elif GameState.force_mishit:
		if shot_type == "putt" or shot_type == "chip":
			var tf2 := PuttStroke.marker_frac(committed_power)
			verdict = {
				"ratio": 0.55,
				"target": tf2,
				"target_frac": tf2,
				"actual_frac": tf2 * 0.55,
				"follow_frac": tf2 * 0.3,
				"balance": 0.25,
				"contact": ShotResult.ContactQuality.FAT,
				"power_mul": 0.55,
				"path_error": 0.55,
				"note": "Putt forced mishit",
				"backswing_ms": 180,
				"downswing_ms": 120,
			}
		else:
			verdict = {
				"ratio": 1.2,
				"target": TempoGrade.target_ratio(shot_type),
				"balance": 0.25,
				"contact": ShotResult.ContactQuality.FAT,
				"power_mul": 0.55,
				"path_error": 0.8,
				"note": "Tempo forced mishit",
				"backswing_ms": 200,
				"downswing_ms": 180,
			}
		last_verdict = verdict
		GameState.last_tempo_metrics = verdict

	var contact: ShotResult.ContactQuality = verdict["contact"]
	var bal: float = float(verdict["balance"])
	var power := clampf(committed_power * float(verdict["power_mul"]), 0.05, 1.0)

	# Direction: putt/chip = PuttStroke path; full family = swipe (+ gated pull) as one signal.
	var shape := suggested_shape
	var swing_shape := 0.0
	var path: float
	if shot_type == "putt" or shot_type == "chip":
		path = float(verdict.get("path_error", 0.0))
		# Putts: slight line emphasis — physics already scales contact/stance.
		if current_lie == "Green":
			path = clampf(path * 1.1, -1.0, 1.0)
	elif GameState.force_mishit:
		# Debug QA: always spray — bypass swipe/pull/unify.
		path = float(verdict.get("path_error", 0.8))
		shape = path
		swing_shape = 0.0
		verdict["swing_shape"] = swing_shape
		verdict["shape_blend"] = shape
		verdict["transition_pull"] = 0.0
		GameState.last_tempo_metrics = verdict
	elif GameState.force_perfect:
		shape = suggested_shape
		swing_shape = 0.0
		path = shape
		verdict["swing_shape"] = 0.0
		verdict["shape_blend"] = shape
		verdict["transition_pull"] = 0.0
		GameState.last_tempo_metrics = verdict
	else:
		var lat := float(sample.get("max_lateral", 0.0))
		# lat→shape: − = in-to-out = draw/left; + = out-to-in = fade/right (see tempo_gesture).
		# ~0.16–0.20 pad half-width saturates intentional shape.
		swing_shape = clampf(lat / 0.18, -1.0, 1.0)
		# pull ≥ 0 = OTT/out-to-in bias (fade side +). Only when rushed past GOOD band.
		var pull := float(verdict.get("transition_pull", 0.0))
		var dispersion := 0.0
		if bal < 0.35:
			dispersion = (
				randf_range(-1.0, 1.0)
				* TempoGrade.BALANCE_DISPERSION_MAX
				* ((0.35 - bal) / 0.35)
			)
		var modulated := clampf(swing_shape + pull + dispersion, -1.0, 1.0)
		var auth := _shape_authority(contact)
		shape = clampf(suggested_shape * 0.45 + modulated * 0.75 * auth, -1.0, 1.0)
		if punch_mode:
			shape *= 0.55  # punch already softens spin in physics
		path = shape  # path_error == intended_shape for full/pitch/punch
		verdict["max_lateral"] = lat
		verdict["swing_shape"] = swing_shape
		verdict["shape_blend"] = shape
		verdict["transition_pull"] = pull
		GameState.last_tempo_metrics = verdict

	_haptic_impact(contact)

	if practice_mode:
		# Meter owns structured coaching; keep hint clear (no triple note dump).
		hint_label.text = ""
		if meter_display:
			meter_display.show_verdict(verdict)
		phase = Phase.DONE
		tempo_gesture.set_enabled(false)
		practice_result.emit(verdict)
		return

	var out := ShotResult.make(power, bal, path, contact, shape)
	out.true_power = true_power_pct
	_emit_result(out)


func _haptic_impact(contact: ShotResult.ContactQuality) -> void:
	## Native impact tiers when plugin is present; duration fallback otherwise.
	## PERFECT = light (pure is clean), mishit = heavy (jarring), MISS = double heavy.
	match contact:
		ShotResult.ContactQuality.PERFECT:
			_haptic_light()
		ShotResult.ContactQuality.GOOD:
			_haptic_medium()
		ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
			_haptic_heavy()
		_:
			_haptic_heavy()
			# Non-blocking second pulse so we never stall practice / _emit_result.
			get_tree().create_timer(0.09).timeout.connect(_haptic_heavy, CONNECT_ONE_SHOT)


func _haptic_light() -> void:
	if Haptics.ready():
		Haptics.light()
	else:
		Input.vibrate_handheld(18)


func _haptic_medium() -> void:
	if Haptics.ready():
		Haptics.medium()
	else:
		Input.vibrate_handheld(12)


func _haptic_heavy() -> void:
	if Haptics.ready():
		Haptics.heavy()
	else:
		Input.vibrate_handheld(6)


func _emit_result(result: ShotResult) -> void:
	phase = Phase.DONE
	tempo_gesture.set_enabled(false)
	set_active(false)
	GameState.record_path_miss(result.path_error)
	GameState.record_shot_form(result.contact_quality, result.stance_stability)
	phase_changed.emit("done")
	if result.is_perfect() and result.stance_stability >= PURE_BALANCE:
		pure_strike.emit(result)
	shot_ready.emit(result)


class_name MeterDisplay
extends Control

## Live tempo ratio strip — or putt amplitude bar. Pad teaches the motion.

var tempo_gesture: TempoGesture
var shot_type: String = "full"
var timing_scale: float = 1.0
var practice_mode: bool = false
var putt_target_frac: float = 0.5
var _verdict: Dictionary = {}
var _guide_alpha: float = 0.0
var _guide_phase: float = 0.0
var _next_tick_at: float = 0.0


func bind(tg: TempoGesture) -> void:
	if tempo_gesture:
		if tempo_gesture.trail_updated.is_connected(_on_trail):
			tempo_gesture.trail_updated.disconnect(_on_trail)
		if tempo_gesture.live_changed.is_connected(_on_live):
			tempo_gesture.live_changed.disconnect(_on_live)
	tempo_gesture = tg
	if tempo_gesture:
		tempo_gesture.trail_updated.connect(_on_trail)
		tempo_gesture.live_changed.connect(_on_live)
	queue_redraw()


func set_shot_context(p_type: String, p_timing: float, p_practice: bool = false) -> void:
	shot_type = p_type
	timing_scale = p_timing
	practice_mode = p_practice
	_verdict.clear()
	_guide_phase = 0.0
	_next_tick_at = 0.15
	_refresh_guide_alpha()
	# Putt: hide dead empty bar until post-stroke reveal (hint owns live instruction).
	visible = p_type != "putt"
	queue_redraw()


func set_putt_target(frac: float) -> void:
	putt_target_frac = frac
	queue_redraw()


func show_verdict(v: Dictionary) -> void:
	_verdict = v
	visible = true
	queue_redraw()


func on_moment(_name: String) -> void:
	queue_redraw()


func _refresh_guide_alpha() -> void:
	if GameState.tempo_guide_forced:
		_guide_alpha = 1.0
		return
	if not GameState.tempo_guide_enabled:
		_guide_alpha = 0.0
		return
	_guide_alpha = clampf(1.0 - GameState.get_form() * 1.35, 0.0, 0.85)


func _on_trail(_pts: PackedVector2Array) -> void:
	queue_redraw()


func _on_live() -> void:
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	if not visible:
		return
	if tempo_gesture and (tempo_gesture.dragging or tempo_gesture.swinging):
		queue_redraw()
	# Putt meter doesn't need metronome ticks — pad marker is the guide.
	if shot_type == "putt":
		return
	if _guide_alpha > 0.02 and tempo_gesture and tempo_gesture.active and tempo_gesture.dragging:
		_guide_phase += delta
		if not tempo_gesture.had_top and _guide_phase >= _next_tick_at:
			AudioBus.play_tick(0.45 * _guide_alpha)
			# Match TempoGesture ghost backswing — chip was 1.125s ticks vs 0.50s disc.
			var back := (
				TempoGesture.GUIDE_BACK_SHORT
				if TempoGrade.target_ratio(shot_type) < 2.5
				else TempoGesture.GUIDE_BACK_FULL
			)
			_next_tick_at = _guide_phase + back


func _draw() -> void:
	if shot_type == "putt":
		_draw_putt_amplitude()
		return
	_draw_tempo_ratio()


func _draw_putt_amplitude() -> void:
	## Live: draw nothing (hint owns the instruction). Verdict: target-vs-actual reveal.
	if _verdict.is_empty():
		return

	var area := Rect2(Vector2.ZERO, size)
	var target := float(_verdict.get("target_frac", putt_target_frac))
	var band := PuttStroke.BAND_HALF
	var title := str(_verdict.get("note", "Stroke"))
	draw_string(
		ThemeDB.fallback_font,
		area.position + Vector2(12.0, 28.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.CAPTION,
		Color(0.7, 0.9, 0.95, 0.95),
	)

	var strip := Rect2(area.position + Vector2(24.0, 40.0), Vector2(area.size.x - 48.0, 28.0))
	draw_rect(strip, Color(0.08, 0.14, 0.18, 0.95), true)
	draw_rect(strip, Color(0.25, 0.45, 0.55, 0.9), false, 2.0)

	var f_min := 0.0
	var f_max := 1.0
	var x_lo := strip.position.x + strip.size.x * clampf((target - band - f_min) / (f_max - f_min), 0.0, 1.0)
	var x_hi := strip.position.x + strip.size.x * clampf((target + band - f_min) / (f_max - f_min), 0.0, 1.0)
	draw_rect(Rect2(x_lo, strip.position.y, maxf(x_hi - x_lo, 2.0), strip.size.y), Color(0.35, 0.7, 0.85, 0.4), true)

	var x_ideal := strip.position.x + strip.size.x * clampf((target - f_min) / (f_max - f_min), 0.0, 1.0)
	draw_line(
		Vector2(x_ideal, strip.position.y - 4.0),
		Vector2(x_ideal, strip.position.y + strip.size.y + 4.0),
		Color(0.7, 0.95, 1.0, 0.95), 3.0, true
	)

	var frac := float(_verdict.get("actual_frac", -1.0))
	if frac >= 0.0:
		var x_n := strip.position.x + strip.size.x * clampf((frac - f_min) / (f_max - f_min), 0.0, 1.0)
		var abs_n := absf(frac - target) / maxf(band, 0.01)
		var needle_c := Color(0.4, 0.85, 0.95)
		if abs_n > PuttStroke.BAND_PERFECT:
			needle_c = Color(0.95, 0.85, 0.35) if abs_n <= PuttStroke.BAND_GOOD else Color(0.95, 0.4, 0.35)
		draw_circle(Vector2(x_n, strip.position.y + strip.size.y * 0.5), 10.0, needle_c)


func _draw_tempo_ratio() -> void:
	var area := Rect2(Vector2.ZERO, size)
	var target := TempoGrade.target_ratio(shot_type)
	var tol := TempoGrade.base_tolerance(shot_type) * maxf(timing_scale, 0.35)

	var title := "Tempo ~%.0f:1%s" % [target, "  PRACTICE" if practice_mode else ""]
	if not _verdict.is_empty():
		title = str(_verdict.get("note", title))
	draw_string(
		ThemeDB.fallback_font,
		area.position + Vector2(12.0, 28.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.CAPTION,
		Color(0.85, 0.92, 0.8, 0.95),
	)

	# Compact ratio strip for short meter height
	var strip := Rect2(area.position + Vector2(24.0, 40.0), Vector2(area.size.x - 48.0, 28.0))
	draw_rect(strip, Color(0.12, 0.18, 0.14, 0.95), true)
	draw_rect(strip, Color(0.25, 0.35, 0.28, 0.9), false, 2.0)

	var r_min := 0.5
	var r_max := 5.5
	var band_lo := target - tol
	var band_hi := target + tol
	var x_lo := strip.position.x + strip.size.x * clampf((band_lo - r_min) / (r_max - r_min), 0.0, 1.0)
	var x_hi := strip.position.x + strip.size.x * clampf((band_hi - r_min) / (r_max - r_min), 0.0, 1.0)
	draw_rect(Rect2(x_lo, strip.position.y, maxf(x_hi - x_lo, 2.0), strip.size.y), Color(0.35, 0.7, 0.4, 0.45), true)

	var x_ideal := strip.position.x + strip.size.x * clampf((target - r_min) / (r_max - r_min), 0.0, 1.0)
	draw_line(
		Vector2(x_ideal, strip.position.y - 4.0),
		Vector2(x_ideal, strip.position.y + strip.size.y + 4.0),
		Color(1.0, 1.0, 1.0, 0.95), 3.0, true
	)

	var ratio := -1.0
	if not _verdict.is_empty():
		ratio = float(_verdict.get("ratio", -1.0))
	elif tempo_gesture:
		ratio = tempo_gesture.live_ratio()

	if ratio >= 0.0:
		var x_n := strip.position.x + strip.size.x * clampf((ratio - r_min) / (r_max - r_min), 0.0, 1.0)
		var needle_c := Color(0.95, 0.9, 0.35)
		if tempo_gesture:
			needle_c = tempo_gesture.trail_color()
		elif not _verdict.is_empty():
			var abs_n := absf(ratio - target) / maxf(tol, 0.01)
			if abs_n <= TempoGrade.BAND_PERFECT:
				needle_c = Color(0.35, 0.92, 0.45)
			elif abs_n <= TempoGrade.BAND_GOOD:
				needle_c = Color(0.95, 0.85, 0.25)
			else:
				needle_c = Color(0.95, 0.35, 0.3)
		draw_circle(Vector2(x_n, strip.position.y + strip.size.y * 0.5), 10.0, needle_c)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(x_n - 24.0, strip.position.y - 8.0),
			"%.1f:1" % ratio,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			UiScale.CAPTION,
			needle_c,
		)

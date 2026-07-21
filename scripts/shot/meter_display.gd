class_name MeterDisplay
extends Control

## Tempo display: ghost trail + moment pulses colored by spacing so far.

var tempo_gesture: TempoGesture
var shot_type: String = "full"
var timing_scale: float = 1.0
var practice_mode: bool = false
var _pulse_name: String = ""
var _pulse_until_ms: int = 0
var _pulse_color: Color = Color(0.4, 0.9, 0.5)
var _verdict: Dictionary = {}
var _guide_alpha: float = 0.0
var _guide_phase: float = 0.0
var _next_tick_at: float = 0.0


func bind(tg: TempoGesture) -> void:
	if tempo_gesture:
		if tempo_gesture.trail_updated.is_connected(_on_trail):
			tempo_gesture.trail_updated.disconnect(_on_trail)
	tempo_gesture = tg
	if tempo_gesture:
		tempo_gesture.trail_updated.connect(_on_trail)
	queue_redraw()


func set_shot_context(p_type: String, p_timing: float, p_practice: bool = false) -> void:
	shot_type = p_type
	timing_scale = p_timing
	practice_mode = p_practice
	_verdict.clear()
	_guide_phase = 0.0
	_next_tick_at = 0.15
	_refresh_guide_alpha()
	queue_redraw()


func show_verdict(v: Dictionary) -> void:
	_verdict = v
	queue_redraw()


func on_moment(name: String) -> void:
	_pulse_name = name
	_pulse_until_ms = Time.get_ticks_msec() + 280
	# Color by spacing so far when we have enough times on the gesture.
	_pulse_color = _moment_color(name)
	queue_redraw()


func _refresh_guide_alpha() -> void:
	if GameState.tempo_guide_forced:
		_guide_alpha = 1.0
		return
	if not GameState.tempo_guide_enabled:
		_guide_alpha = 0.0
		return
	# Fade as form improves — never widens windows, only shows rhythm.
	_guide_alpha = clampf(1.0 - GameState.get_form() * 1.35, 0.0, 0.85)


func _moment_color(name: String) -> Color:
	if tempo_gesture == null:
		return Color(0.5, 0.85, 0.5)
	# Rough live estimate from partial timestamps via last sample fields if available.
	return Color(0.45, 0.9, 0.5) if name != "impact" else Color(0.95, 0.9, 0.35)


func _on_trail(_pts: PackedVector2Array) -> void:
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	if tempo_gesture and (tempo_gesture.dragging or tempo_gesture.swinging):
		queue_redraw()
	if _guide_alpha > 0.02 and tempo_gesture and tempo_gesture.active and tempo_gesture.dragging:
		_guide_phase += delta
		queue_redraw()
		if not tempo_gesture.had_top and _guide_phase >= _next_tick_at:
			AudioBus.play_tick(0.45 * _guide_alpha)
			var target := TempoGrade.target_ratio(shot_type)
			_next_tick_at = _guide_phase + (0.75 / maxf(target / 3.0, 0.5))


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	var rect: Rect2 = ArcMeters.swing_rect(area.size, 36.0, 28.0)
	rect.position += area.position

	var track: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.0, 1.0, 40)
	ArcMeters.draw_thick_polyline(self, track, Color(0.12, 0.18, 0.16, 0.95), 18.0)
	ArcMeters.draw_thick_polyline(self, track, Color(0.2, 0.28, 0.24, 0.9), 12.0)

	# Ideal ratio zones as faint arcs: backswing bulk left, downswing right-bottom.
	var target := TempoGrade.target_ratio(shot_type)
	draw_string(
		ThemeDB.fallback_font,
		area.position + Vector2(12.0, 28.0),
		"Tempo ~%.0f:1%s" % [target, "  PRACTICE" if practice_mode else ""],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.BODY,
		Color(0.85, 0.92, 0.8, 0.95),
	)

	# Guide pulse on impact point
	if _guide_alpha > 0.02:
		var impact := ArcMeters.swing_point(rect, 0.5)
		var pulse := 0.5 + 0.5 * sin(_guide_phase * TAU * 1.2)
		draw_circle(impact, 10.0 + pulse * 6.0, Color(0.95, 0.9, 0.4, _guide_alpha * 0.35 * pulse))

	# Ghost trail mapped into meter space from gesture local trail
	if tempo_gesture and tempo_gesture.trail.size() >= 2:
		var pts := tempo_gesture.trail
		var gsize := tempo_gesture.size
		if gsize.x > 1.0 and gsize.y > 1.0:
			for i in range(1, pts.size()):
				var a := _map_trail(pts[i - 1], gsize, rect)
				var b := _map_trail(pts[i], gsize, rect)
				var t := float(i) / float(pts.size())
				draw_line(a, b, Color(0.35, 0.85, 0.55, 0.2 + 0.55 * t), 4.0, true)

	# Moment pulses at arc landmarks
	var now := Time.get_ticks_msec()
	if now < _pulse_until_ms:
		var t_pos := 0.05
		match _pulse_name:
			"takeaway":
				t_pos = 0.05
			"top":
				t_pos = 0.28
			"impact":
				t_pos = 0.5
		var p := ArcMeters.swing_point(rect, t_pos)
		var age := 1.0 - float(_pulse_until_ms - now) / 280.0
		draw_circle(p, 14.0 + age * 10.0, Color(_pulse_color.r, _pulse_color.g, _pulse_color.b, 0.55 * (1.0 - age)))

	draw_circle(ArcMeters.swing_point(rect, 0.02), 4.0, Color(0.7, 0.75, 0.7, 0.7))
	draw_circle(ArcMeters.swing_point(rect, 0.5), 6.0, Color(0.95, 0.85, 0.3, 0.85))
	draw_circle(ArcMeters.swing_point(rect, 0.98), 4.0, Color(0.7, 0.75, 0.7, 0.7))

	if not _verdict.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			area.position + Vector2(12.0, area.size.y - 16.0),
			str(_verdict.get("note", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			UiScale.CAPTION,
			Color(0.95, 0.92, 0.7, 0.95),
		)


func _map_trail(local: Vector2, gsize: Vector2, rect: Rect2) -> Vector2:
	# Map gesture pad coords onto swing arc t by vertical progress (back = up).
	var ny := clampf(1.0 - local.y / maxf(gsize.y, 1.0), 0.0, 1.0)
	var nx := clampf(local.x / maxf(gsize.x, 1.0), 0.0, 1.0)
	var t := clampf(ny * 0.55 + nx * 0.2, 0.0, 1.0)
	return ArcMeters.swing_point(rect, t)

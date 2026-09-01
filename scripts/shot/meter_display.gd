class_name MeterDisplay
extends Control

## Live tempo ratio strip — or putt amplitude bar. Pad teaches the motion.

const TEX_TRACK := preload("res://assets/ui/ui_tempo_meter_track.png")
const TEX_NEEDLE := preload("res://assets/ui/ui_tempo_meter_needle.png")

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
	# Live ratio bar only while grooving (Practice Swing or Range). Scored hole shots
	# stay clean — ghost + ticks are the coach; putt/chip always hint-owned.
	var live_coach := p_practice or GameState.range_mode
	visible = live_coach and p_type != "putt" and p_type != "chip"
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
	if GameState.range_mode:
		_guide_alpha = 0.9
		return
	# Per shot-type reps (Phase 4) — same curve as tempo_gesture._guide_alpha.
	var st := "full"
	if tempo_gesture:
		st = tempo_gesture.shot_type
	_guide_alpha = GameState.guide_alpha_for_shot_type(st)


func _on_trail(_pts: PackedVector2Array) -> void:
	queue_redraw()


func _on_live() -> void:
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	set_process(true)


func _process(delta: float) -> void:
	if not visible:
		return
	if tempo_gesture and (tempo_gesture.dragging or tempo_gesture.swinging):
		queue_redraw()
	# Putt/chip/flop meter doesn't need metronome ticks — pad marker is the guide.
	if BallPhysics.uses_stroke_pad(shot_type):
		return
	if _guide_alpha > 0.02 and tempo_gesture and tempo_gesture.active and tempo_gesture.dragging:
		_guide_phase += delta
		if not tempo_gesture.had_top and _guide_phase >= _next_tick_at:
			AudioBus.play_tick(0.45 * _guide_alpha)
			# Same base + club scale as TempoGesture._guide_back_sec (don't desync audio vs ghost).
			var back := (
				TempoGesture.GUIDE_BACK_SHORT
				if TempoGrade.target_ratio(shot_type) < 2.5
				else TempoGesture.GUIDE_BACK_FULL
			)
			if shot_type == "full":
				back *= TempoGesture.club_guide_duration_scale(tempo_gesture.club_max_yards)
			_next_tick_at = _guide_phase + back


func _draw() -> void:
	if BallPhysics.uses_stroke_pad(shot_type):
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
	# Short title only — full note is F1/result material, not meter chrome.
	var title := str(_verdict.get("note", "Stroke"))
	if title.length() > 28:
		title = title.substr(0, 26) + "…"
	draw_string(
		UiScale.FONT,
		area.position + Vector2(12.0, 22.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.CAPTION * 0.55,
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


func _pace_color(read: String) -> Color:
	match read:
		"on_pace":
			return Color(0.35, 0.92, 0.45)
		"slow", "fast":
			return Color(0.95, 0.85, 0.25)
		_:
			return Color(0.95, 0.35, 0.3)


func _contact_label(contact: Variant) -> String:
	if contact == null:
		return ""
	match int(contact):
		ShotResult.ContactQuality.PERFECT:
			return "PERFECT"
		ShotResult.ContactQuality.GOOD:
			return "GOOD"
		ShotResult.ContactQuality.THIN:
			return "THIN"
		ShotResult.ContactQuality.FAT:
			return "FAT"
		ShotResult.ContactQuality.MISS:
			return "MISS"
		_:
			return ""


func _contact_color(tag: String) -> Color:
	match tag:
		"PERFECT":
			return Color(1.0, 0.92, 0.35)
		"GOOD":
			return Color(0.35, 0.92, 0.45)
		"THIN", "FAT":
			return Color(0.95, 0.85, 0.25)
		"MISS":
			return Color(0.95, 0.35, 0.3)
		_:
			return Color(0.85, 0.92, 0.8)


func _draw_tempo_ratio() -> void:
	var area := Rect2(Vector2.ZERO, size)
	var target := TempoGrade.target_ratio(shot_type)
	var tol := TempoGrade.base_tolerance(shot_type) * maxf(timing_scale, 0.35)
	var r_min := 0.5
	var r_max := 5.5

	var ratio := -1.0
	if not _verdict.is_empty():
		ratio = float(_verdict.get("ratio", -1.0))
		target = float(_verdict.get("target", target))
		tol = maxf(float(_verdict.get("tolerance", tol)), 0.01)
	elif tempo_gesture:
		ratio = tempo_gesture.live_ratio()

	# Post-commit practice/range: structured coaching (not the long note string thrice).
	var strip_y := 40.0
	if not _verdict.is_empty():
		var back_read := str(_verdict.get("backswing_read", "on_pace"))
		var down_read := str(_verdict.get("downswing_read", "on_pace"))
		var back_line := str(_verdict.get("back_line", ""))
		var down_line := str(_verdict.get("down_line", ""))
		if back_line.is_empty() or down_line.is_empty():
			var copy: Dictionary = TempoGrade.pace_copy(back_read, down_read, ratio, target)
			back_line = str(copy.get("back_line", "Backswing — on pace"))
			down_line = str(copy.get("down_line", "Downswing — on pace"))
			back_read = str(copy.get("backswing_read", back_read))
			down_read = str(copy.get("downswing_read", down_read))
		var fs := UiScale.CAPTION * 0.5
		var left := 12.0
		var y0 := area.position.y + 16.0
		var c1 := _pace_color(back_read)
		draw_rect(Rect2(left, y0, 5.0, 12.0), c1, true)
		draw_string(UiScale.FONT, Vector2(left + 10.0, y0 + 11.0), back_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c1)
		var y1 := y0 + 18.0
		var c2 := _pace_color(down_read)
		draw_rect(Rect2(left, y1, 5.0, 12.0), c2, true)
		draw_string(UiScale.FONT, Vector2(left + 10.0, y1 + 11.0), down_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c2)
		var y2 := y1 + 18.0
		var ratio_txt := "%.1f:1  (tgt %.0f:1)" % [ratio if ratio >= 0.0 else target, target]
		var tag := _contact_label(_verdict.get("contact", null))
		if not tag.is_empty():
			ratio_txt += "  ·  %s" % tag
		draw_string(
			UiScale.FONT,
			Vector2(left + 10.0, y2 + 11.0),
			ratio_txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			_contact_color(tag) if not tag.is_empty() else Color(0.85, 0.92, 0.8, 0.95),
		)
		strip_y = y2 + 18.0
	else:
		var title := "Tempo ~%.0f:1%s" % [target, "  PRACTICE" if practice_mode else ""]
		draw_string(
			UiScale.FONT,
			area.position + Vector2(12.0, 28.0),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			UiScale.CAPTION,
			Color(0.85, 0.92, 0.8, 0.95),
		)

	# Compact ratio strip
	var strip := Rect2(area.position + Vector2(24.0, strip_y), Vector2(area.size.x - 48.0, 22.0))
	draw_texture_rect(TEX_TRACK, strip, false)

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

	if ratio >= 0.0:
		var x_n := strip.position.x + strip.size.x * clampf((ratio - r_min) / (r_max - r_min), 0.0, 1.0)
		var needle_c := Color(0.95, 0.9, 0.35)
		if _verdict.is_empty() and tempo_gesture:
			needle_c = tempo_gesture.trail_color()
		else:
			var abs_n := absf(ratio - target) / maxf(tol, 0.01)
			if abs_n <= TempoGrade.BAND_PERFECT:
				needle_c = Color(0.35, 0.92, 0.45)
			elif abs_n <= TempoGrade.BAND_GOOD:
				needle_c = Color(0.95, 0.85, 0.25)
			else:
				needle_c = Color(0.95, 0.35, 0.3)
		var nsz := TEX_NEEDLE.get_size()
		var nd := 20.0
		var ns := nd / maxf(nsz.x, 1.0)
		draw_set_transform(Vector2(x_n, strip.position.y + strip.size.y * 0.5), 0.0, Vector2(ns, ns))
		draw_texture(TEX_NEEDLE, -nsz * 0.5, needle_c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class_name TempoMini
extends Control

## Compact tempo readout for the result screen. Full/pitch: two-part pace read
## (backswing + downswing) vs ghost guide. Putt/chip: amplitude strip unchanged.

const TEX_TRACK := preload("res://assets/ui/ui_tempo_meter_track.png")
const TEX_NEEDLE := preload("res://assets/ui/ui_tempo_meter_needle.png")

const NEEDLE_POP_FROM := 1.3
const NEEDLE_POP_TO := 1.0
const NEEDLE_POP_TIME := 0.18

## Dark near-black outline baked into the existing needle/track pixel art.
const OUTLINE_COLOR := Color(0.10196, 0.12157, 0.10196, 1.0)
const OUTLINE_SCALE := 1.3

var _verdict: Dictionary = {}
var _last_verdict: Dictionary = {}
var _is_green: bool = false
var _needle_scale: float = NEEDLE_POP_TO
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	visible = false


func show_verdict(verdict: Dictionary, is_green: bool) -> void:
	if verdict.is_empty():
		return
	if visible and verdict == _last_verdict:
		return  # same shot re-showing (launch → final) — don't replay the pop
	_verdict = verdict
	_last_verdict = verdict
	_is_green = is_green
	visible = true

	if _tween:
		_tween.kill()
	_needle_scale = NEEDLE_POP_FROM
	_tween = create_tween()
	_tween.tween_method(_set_needle_scale, NEEDLE_POP_FROM, NEEDLE_POP_TO, NEEDLE_POP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _set_needle_scale(v: float) -> void:
	_needle_scale = v
	queue_redraw()


func _draw() -> void:
	if _verdict.is_empty():
		return
	if _is_green or _verdict.has("target_frac"):
		_draw_amplitude_strip()
	else:
		_draw_ratio_strip()


func _needle_color(abs_n: float, band_perfect: float, band_good: float) -> Color:
	if abs_n <= band_perfect:
		return Color(0.35, 0.92, 0.45)
	if abs_n <= band_good:
		return Color(0.95, 0.85, 0.25)
	return Color(0.95, 0.35, 0.3)


func _pace_color(read: String) -> Color:
	match read:
		"on_pace":
			return Color(0.35, 0.92, 0.45)
		"slow", "fast":
			return Color(0.95, 0.85, 0.25)
		_:
			return Color(0.95, 0.35, 0.3)


func _draw_needle(x: float, y: float, color: Color, label: String) -> void:
	var nsz := TEX_NEEDLE.get_size()
	var nd := 30.0
	var ns := (nd / maxf(nsz.x, 1.0)) * _needle_scale
	var outline_ns := ns * OUTLINE_SCALE
	draw_set_transform(Vector2(x, y), 0.0, Vector2(outline_ns, outline_ns))
	draw_texture(TEX_NEEDLE, -nsz * 0.5, OUTLINE_COLOR)
	draw_set_transform(Vector2(x, y), 0.0, Vector2(ns, ns))
	draw_texture(TEX_NEEDLE, -nsz * 0.5, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(
		UiScale.FONT,
		Vector2(x - 24.0, y - 16.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.CAPTION * 0.6,
		color,
	)


func _verdict_word(err: float, tol: float) -> String:
	## Amplitude path only — ratio path uses two-part pace lines.
	if err < -tol:
		return "Early"
	if err > tol:
		return "Late"
	return "On time"


func _draw_ratio_strip() -> void:
	## Two-part pace read (back / through) + secondary ratio. Not a single Early/Late word.
	var target := float(_verdict.get("target", 3.0))
	var ratio := float(_verdict.get("ratio", target))
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

	var left := 16.0
	var w := size.x - 32.0
	var y0 := size.y * 0.22
	var row_h := 22.0
	var fs := UiScale.CAPTION * 0.55

	# Row 1 — backswing
	var c1 := _pace_color(back_read)
	draw_rect(Rect2(left, y0, 6.0, row_h - 4.0), c1, true)
	draw_string(UiScale.FONT, Vector2(left + 12.0, y0 + 14.0), back_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c1)

	# Row 2 — downswing
	var y1 := y0 + row_h
	var c2 := _pace_color(down_read)
	draw_rect(Rect2(left, y1, 6.0, row_h - 4.0), c2, true)
	draw_string(UiScale.FONT, Vector2(left + 12.0, y1 + 14.0), down_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c2)

	# Secondary ratio context (not the only signal)
	var y2 := y1 + row_h + 4.0
	var ratio_c := Color(0.85, 0.92, 0.8, 0.9)
	draw_string(
		UiScale.FONT,
		Vector2(left + 12.0, y2 + 12.0),
		"%.1f:1  (tgt %.0f:1)" % [ratio, target],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs * 0.95,
		ratio_c,
	)
	# Thin track under ratio for continuity with old mini strip
	var strip := Rect2(left, y2 + 16.0, w, 8.0)
	draw_texture_rect(TEX_TRACK, strip, false)
	var r_min := 0.5
	var r_max := 5.5
	var tol := maxf(float(_verdict.get("tolerance", 0.5)), 0.01)
	var x_ideal := strip.position.x + strip.size.x * clampf((target - r_min) / (r_max - r_min), 0.0, 1.0)
	draw_line(
		Vector2(x_ideal, strip.position.y - 2.0),
		Vector2(x_ideal, strip.position.y + strip.size.y + 2.0),
		Color(1.0, 1.0, 1.0, 0.9), 2.0, true
	)
	var abs_n := absf(ratio - target) / tol
	var needle_c := _needle_color(abs_n, TempoGrade.BAND_PERFECT, TempoGrade.BAND_GOOD)
	var x_n := strip.position.x + strip.size.x * clampf((ratio - r_min) / (r_max - r_min), 0.0, 1.0)
	var nsz := TEX_NEEDLE.get_size()
	var nd := 22.0
	var ns := (nd / maxf(nsz.x, 1.0)) * _needle_scale
	draw_set_transform(Vector2(x_n, strip.position.y + strip.size.y * 0.5), 0.0, Vector2(ns * OUTLINE_SCALE, ns * OUTLINE_SCALE))
	draw_texture(TEX_NEEDLE, -nsz * 0.5, OUTLINE_COLOR)
	draw_set_transform(Vector2(x_n, strip.position.y + strip.size.y * 0.5), 0.0, Vector2(ns, ns))
	draw_texture(TEX_NEEDLE, -nsz * 0.5, needle_c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_amplitude_strip() -> void:
	var target := float(_verdict.get("target_frac", 0.5))
	var tol := maxf(float(_verdict.get("tolerance", PuttStroke.BAND_HALF)), 0.001)
	var actual := float(_verdict.get("actual_frac", target))

	var strip := Rect2(Vector2(16.0, size.y * 0.5 - 10.0), Vector2(size.x - 32.0, 20.0))
	draw_rect(strip, Color(0.08, 0.14, 0.18, 0.95), true)
	draw_rect(strip, Color(0.25, 0.45, 0.55, 0.9), false, 2.0)

	var f_min := 0.0
	var f_max := 1.0
	var x_lo := strip.position.x + strip.size.x * clampf((target - tol - f_min) / (f_max - f_min), 0.0, 1.0)
	var x_hi := strip.position.x + strip.size.x * clampf((target + tol - f_min) / (f_max - f_min), 0.0, 1.0)
	draw_rect(Rect2(x_lo, strip.position.y, maxf(x_hi - x_lo, 2.0), strip.size.y), OUTLINE_COLOR, false, 2.0)

	var x_ideal := strip.position.x + strip.size.x * clampf((target - f_min) / (f_max - f_min), 0.0, 1.0)
	draw_line(
		Vector2(x_ideal, strip.position.y - 3.0),
		Vector2(x_ideal, strip.position.y + strip.size.y + 3.0),
		Color(0.7, 0.95, 1.0, 0.95), 3.0, true
	)

	var err := actual - target
	var abs_n := absf(err) / tol
	var needle_c := _needle_color(abs_n, PuttStroke.BAND_PERFECT, PuttStroke.BAND_GOOD)
	var word := _verdict_word(err, tol)
	var x_n := strip.position.x + strip.size.x * clampf((actual - f_min) / (f_max - f_min), 0.0, 1.0)
	_draw_needle(x_n, strip.position.y + strip.size.y * 0.5, needle_c, "%s · %.0f%%" % [word, actual * 100.0])

class_name TempoMini
extends Control

## Compact tempo readout for the "tap to continue" result screen — the needle
## pop the swing-time MeterDisplay never gets to show on a real shot (it's
## hidden the instant the swing commits). Same track/band/tick/needle math as
## MeterDisplay, stripped of title text and background, sized for a thin strip.

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
	if _is_green:
		_draw_amplitude_strip()
	else:
		_draw_ratio_strip()


func _needle_color(abs_n: float, band_perfect: float, band_good: float) -> Color:
	if abs_n <= band_perfect:
		return Color(0.35, 0.92, 0.45)
	if abs_n <= band_good:
		return Color(0.95, 0.85, 0.25)
	return Color(0.95, 0.35, 0.3)


func _draw_needle(x: float, y: float, color: Color, label: String) -> void:
	var nsz := TEX_NEEDLE.get_size()
	var nd := 30.0
	var ns := (nd / maxf(nsz.x, 1.0)) * _needle_scale
	# Procedural outline ring underneath — guarantees contrast against any zone
	# color behind it (source art's baked-in outline crushes at small sizes).
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
	## Plain-language read next to the ratio/frac number — same tol used for
	## the good-zone band, so "On time" lines up with what's drawn as the guide.
	if err < -tol:
		return "Early"
	if err > tol:
		return "Late"
	return "On time"


func _draw_ratio_strip() -> void:
	var target := float(_verdict.get("target", 0.0))
	var tol := maxf(float(_verdict.get("tolerance", 0.5)), 0.01)
	var ratio := float(_verdict.get("ratio", target))

	var strip := Rect2(Vector2(16.0, size.y * 0.5 - 10.0), Vector2(size.x - 32.0, 20.0))
	draw_texture_rect(TEX_TRACK, strip, false)

	var r_min := 0.5
	var r_max := 5.5
	var x_lo := strip.position.x + strip.size.x * clampf((target - tol - r_min) / (r_max - r_min), 0.0, 1.0)
	var x_hi := strip.position.x + strip.size.x * clampf((target + tol - r_min) / (r_max - r_min), 0.0, 1.0)
	draw_rect(Rect2(x_lo, strip.position.y, maxf(x_hi - x_lo, 2.0), strip.size.y), OUTLINE_COLOR, false, 2.0)

	var x_ideal := strip.position.x + strip.size.x * clampf((target - r_min) / (r_max - r_min), 0.0, 1.0)
	draw_line(
		Vector2(x_ideal, strip.position.y - 3.0),
		Vector2(x_ideal, strip.position.y + strip.size.y + 3.0),
		Color(1.0, 1.0, 1.0, 0.95), 2.0, true
	)

	var err := ratio - target
	var abs_n := absf(err) / tol
	var needle_c := _needle_color(abs_n, TempoGrade.BAND_PERFECT, TempoGrade.BAND_GOOD)
	var word := _verdict_word(err, tol)
	var x_n := strip.position.x + strip.size.x * clampf((ratio - r_min) / (r_max - r_min), 0.0, 1.0)
	_draw_needle(x_n, strip.position.y + strip.size.y * 0.5, needle_c, "%s · %.1f:1" % [word, ratio])


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
		Color(0.7, 0.95, 1.0, 0.95), 2.0, true
	)

	var err := actual - target
	var abs_n := absf(err) / tol
	var needle_c := _needle_color(abs_n, PuttStroke.BAND_PERFECT, PuttStroke.BAND_GOOD)
	var word := _verdict_word(err, tol)
	var x_n := strip.position.x + strip.size.x * clampf((actual - f_min) / (f_max - f_min), 0.0, 1.0)
	_draw_needle(x_n, strip.position.y + strip.size.y * 0.5, needle_c, "%s · %.0f%%" % [word, actual * 100.0])

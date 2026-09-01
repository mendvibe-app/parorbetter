class_name CoursePinFlag
extends Node2D

## On-course pin at the cup. All sizes in screen px / zoom (true-scale safe).

const COLOR_POLE := Color(0.95, 0.95, 0.97)
const COLOR_FLAG := Color(0.886, 0.294, 0.290)
## Whole stick height on screen; flag sits at the TOP (not the foot).
const POLE_H_SCREEN := 36.0  ## PLAYTEST
const POLE_W_SCREEN := 2.75
const FLAG_W_SCREEN := 13.0
const FLAG_H_SCREEN := 10.0
## Flag attaches this far below the tip (screen px).
const FLAG_TIP_INSET_SCREEN := 2.0

## Kept for controller API (screen height hint); draw uses POLE_H_SCREEN.
var height_px: float = 36.0
var camera_zoom: float = 1.0
var _wind: Vector2 = Vector2.ZERO
var _t: float = 0.0


func _ready() -> void:
	z_index = 7  ## above book wash / cup disc so the stick reads during aim
	set_process(true)


func set_wind(wind: Vector2) -> void:
	_wind = wind
	queue_redraw()


func set_camera_zoom(z: float) -> void:
	camera_zoom = maxf(z, 0.35)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var z := camera_zoom
	var cam := get_viewport().get_camera_2d()
	if cam:
		z = maxf(cam.zoom.x, 0.35)
	var pole_h := POLE_H_SCREEN / z
	var pole_w := POLE_W_SCREEN / z
	var foot := Vector2.ZERO
	var top := Vector2(0.0, -pole_h)
	draw_line(foot, top, COLOR_POLE, pole_w, true)

	# Pennant at the TOP of the stick (bug: was -h*0.12 → near the foot).
	var side := 1.0
	if absf(_wind.x) > 0.5:
		side = signf(_wind.x)
	var fw := FLAG_W_SCREEN / z
	var fh := FLAG_H_SCREEN / z
	var inset := FLAG_TIP_INSET_SCREEN / z
	var attach := Vector2(0.0, -pole_h + inset)
	var tip := attach + Vector2(side * fw, fh * 0.15)
	var bot := attach + Vector2(0.0, fh)
	var flutter := sin(_t * 4.0) * (1.0 / z) * side
	tip.x += flutter
	draw_colored_polygon(PackedVector2Array([attach, tip, bot]), COLOR_FLAG)

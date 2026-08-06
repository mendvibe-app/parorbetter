class_name CoursePinFlag
extends Node2D

## On-course pin: same cloth language as HUD WindFlag (paint_flag). Origin = pole foot on cup.

const _WindFlagScr := preload("res://scripts/ui/wind_flag.gd")

var height_px: float = 32.0
var _wind: Vector2 = Vector2.ZERO
var _t: float = 0.0


func _ready() -> void:
	z_index = 3
	set_process(true)


func set_wind(wind: Vector2) -> void:
	_wind = wind
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	_WindFlagScr.paint_flag(self, Vector2.ZERO, _wind, _t, height_px)

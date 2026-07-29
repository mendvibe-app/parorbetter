class_name LiePreview
extends Control

## Side-on lie diorama: ground strip + ball height (severity read).
## Hosted top-right on the swing pad (TempoGesture) and on club select.
## No text — Buried / Average / SittingUp are pure ball Y vs the grass line.

const TEX_FAIRWAY := preload("res://assets/ui/lie_widget_fairway.png")
const TEX_ROUGH := preload("res://assets/ui/lie_widget_rough.png")
const TEX_SAND := preload("res://assets/ui/lie_widget_sand.png")
const TEX_GREEN := preload("res://assets/ui/lie_widget_green.png")
const TEX_TEE := preload("res://assets/ui/lie_widget_tee.png")
const TEX_BALL := preload("res://assets/ui/lie_widget_ball.png")
const TEX_PEG := preload("res://assets/ui/lie_widget_tee_peg.png")

const WIDGET_W := 96.0
const WIDGET_H := 40.0

var _lie: String = "Tee"
var _severity: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(WIDGET_W, WIDGET_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_state("Tee", "")


func set_state(lie: String, severity: String = "") -> void:
	_lie = lie
	_severity = severity
	queue_redraw()


func _ground_tex() -> Texture2D:
	match _lie:
		"Rough", "Trees":
			return TEX_ROUGH  # ponytail: dedicated tree widget later
		"Sand":
			return TEX_SAND
		"Green":
			return TEX_GREEN
		"Tee":
			return TEX_TEE
		_:
			return TEX_FAIRWAY


## Ball center Y as fraction of widget height (0 = top). Higher = lower on screen.
func _ball_y_frac() -> float:
	# Grass line sits ~mid-lower; ball rides relative to it.
	if _lie == "Tee":
		return 0.38
	if _lie == "Rough" and GameState.rough_severity_enabled and _severity != "":
		match _severity:
			BallPhysics.ROUGH_SEV_BURIED:
				return 0.72  # mostly in the grass
			BallPhysics.ROUGH_SEV_SITTING:
				return 0.40  # perched up
			_:
				return 0.58  # Average — on the line
	# Fairway / Sand / Green / Rough-off: resting on the surface.
	return 0.58


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Ground strip fills the widget; transparent top of the PNG keeps sky empty.
	var gtex := _ground_tex()
	draw_texture_rect(gtex, r, false)

	var cx := size.x * 0.5
	var by := size.y * _ball_y_frac()
	var ball_s := 14.0
	if _lie == "Tee":
		# Peg under the elevated ball.
		var peg_s := Vector2(8.0, 12.0)
		var peg_pos := Vector2(cx - peg_s.x * 0.5, by + ball_s * 0.15)
		draw_texture_rect(TEX_PEG, Rect2(peg_pos, peg_s), false)
	var ball_pos := Vector2(cx - ball_s * 0.5, by - ball_s * 0.5)
	draw_texture_rect(TEX_BALL, Rect2(ball_pos, Vector2(ball_s, ball_s)), false)

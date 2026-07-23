extends Control

const LIFE_FULL := preload("res://assets/ui/life_full.png")
const LIFE_EMPTY := preload("res://assets/ui/life_empty.png")

@onready var hole_label: Label = $HoleLabel
@onready var score_label: Label = $ScoreLabel
@onready var lives_row: HBoxContainer = $LivesRow
@onready var adapt_label: Label = $AdaptLabel

var _strokes: int = 0


func _ready() -> void:
	GameState.lives_changed.connect(_on_lives)
	GameState.pure_strikes_changed.connect(_on_pure_strikes)
	# Form/bias live in the aim circle + F1 — AdaptLabel is retired (HUD cleanup).
	if adapt_label:
		adapt_label.visible = false
		adapt_label.text = ""
	_on_lives(GameState.lives)
	_on_pure_strikes(GameState.pure_strikes)


func refresh(hole: HoleData, strokes: int) -> void:
	if hole == null:
		return
	_strokes = strokes
	hole_label.text = "HOLE %d · PAR %d · %d YDS" % [
		hole.hole_number, hole.par, int(hole.yardage)
	]
	_refresh_score()
	lives_row.visible = true


func refresh_range(swings: int) -> void:
	_strokes = swings
	hole_label.text = "DRIVING RANGE"
	score_label.text = "Swings %d · F1 Exit" % swings
	lives_row.visible = false


func _refresh_score() -> void:
	var pure_bit := ""
	if GameState.pure_strikes > 0:
		pure_bit = " · %d pure" % GameState.pure_strikes
	score_label.text = "Strokes %d%s" % [_strokes, pure_bit]


func _on_lives(lives: int) -> void:
	for c in lives_row.get_children():
		c.queue_free()
	for i in GameState.MAX_LIVES:
		var icon := TextureRect.new()
		icon.texture = LIFE_FULL if i < lives else LIFE_EMPTY
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i >= lives:
			icon.modulate.a = 0.55
		lives_row.add_child(icon)


func _on_pure_strikes(_count: int) -> void:
	if GameState.range_mode:
		return
	_refresh_score()

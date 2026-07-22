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
	GameState.adaptation_changed.connect(_on_adapt)
	GameState.form_changed.connect(_on_form)
	GameState.pure_strikes_changed.connect(_on_pure_strikes)
	_on_lives(GameState.lives)
	_on_adapt(GameState.get_adaptation_bias())
	_on_form(GameState.get_form())
	_on_pure_strikes(GameState.pure_strikes)


func refresh(hole: HoleData, strokes: int) -> void:
	if hole == null:
		return
	_strokes = strokes
	hole_label.text = "HOLE %d/%d  ·  %s" % [hole.hole_number, GameState.HOLE_COUNT, hole.name_label]
	_refresh_score(hole.par)
	_on_form(GameState.get_form())
	lives_row.visible = true


func refresh_range(swings: int) -> void:
	_strokes = swings
	hole_label.text = "DRIVING RANGE"
	score_label.text = "Swings %d  ·  no lives  ·  F1 Exit Range" % swings
	lives_row.visible = false
	_on_form(GameState.get_form())


func _refresh_score(par: int) -> void:
	var pure_bit := ""
	if GameState.pure_strikes > 0:
		pure_bit = "   ·  %d pure" % GameState.pure_strikes
	score_label.text = "Par %d   Strokes %d%s" % [par, _strokes, pure_bit]


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


func _on_adapt(_bias: float) -> void:
	_refresh_adapt_form()


func _on_form(_form: float) -> void:
	_refresh_adapt_form()


func _on_pure_strikes(_count: int) -> void:
	var hole := GameState.get_hole(GameState.current_hole)
	if hole:
		_refresh_score(hole.par)


func _refresh_adapt_form() -> void:
	adapt_label.text = "%s · ○%dyd %s" % [
		GameState.bias_label(),
		int(GameState.get_aim_radius_yards(false)),
		GameState.form_label(),
	]

extends Control

signal menu_pressed

const LIFE_FULL := preload("res://assets/ui/life_full.png")
const LIFE_EMPTY := preload("res://assets/ui/life_empty.png")

@onready var hole_label: Label = $HoleLabel
@onready var score_label: Label = $ScoreLabel
@onready var lives_row: HBoxContainer = $LivesRow
@onready var adapt_label: Label = $AdaptLabel

var _strokes: int = 0
var menu_btn: Button


func _ready() -> void:
	GameState.lives_changed.connect(_on_lives)
	GameState.pure_strikes_changed.connect(_on_pure_strikes)
	# Form/bias live in the aim circle + F1 — AdaptLabel is retired (HUD cleanup).
	if adapt_label:
		adapt_label.visible = false
		adapt_label.text = ""
	_setup_menu_btn()
	_on_lives(GameState.lives)
	_on_pure_strikes(GameState.pure_strikes)


func _setup_menu_btn() -> void:
	## Practice modes only — leave range/green without F1.
	menu_btn = Button.new()
	menu_btn.name = "MenuButton"
	menu_btn.text = "Menu"
	menu_btn.visible = false
	menu_btn.custom_minimum_size = Vector2(120, 52)
	menu_btn.add_theme_font_size_override("font_size", UiScale.CAPTION)
	menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_btn.offset_left = -160.0
	menu_btn.offset_top = 84.0
	menu_btn.offset_right = -24.0
	menu_btn.offset_bottom = 136.0
	menu_btn.pressed.connect(func() -> void:
		AudioBus.play_ui()
		menu_pressed.emit()
	)
	add_child(menu_btn)


func refresh(hole: HoleData, strokes: int) -> void:
	if hole == null:
		return
	_strokes = strokes
	var tee := GameState.active_tee_set_for_hole(hole.hole_number)
	var yds := int(hole.tee_yards(tee))
	var stroke_bit := ""
	if GameState.is_stroke_play() and GameState.hole_gets_stroke(hole.hole_number):
		stroke_bit = " · ★"  # handicap stroke on this hole
	hole_label.text = "HOLE %d · PAR %d · %s · %d YDS%s" % [
		hole.hole_number, hole.par, HoleData.tee_set_label(tee), yds, stroke_bit
	]
	_refresh_score()
	lives_row.visible = GameState.is_survival()
	if menu_btn:
		menu_btn.visible = false


func refresh_range(swings: int) -> void:
	_strokes = swings
	hole_label.text = "DRIVING RANGE"
	score_label.text = "Swings %d" % swings
	lives_row.visible = false
	if menu_btn:
		menu_btn.visible = true


func refresh_practice_green(putts: int) -> void:
	_strokes = putts
	hole_label.text = "PRACTICE GREEN"
	score_label.text = "Putts %d" % putts
	lives_row.visible = false
	if menu_btn:
		menu_btn.visible = true


func _refresh_score() -> void:
	if GameState.is_stroke_play():
		var card := GameState.format_score_to_par(GameState.score_to_par)
		score_label.text = "Strokes %d · %s" % [_strokes, card]
		return
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
	if GameState.in_practice():
		return
	_refresh_score()

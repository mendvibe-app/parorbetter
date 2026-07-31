extends Control

signal restart_pressed

@onready var title: Label = $Panel/Title
@onready var detail: Label = $Panel/Detail
@onready var restart_btn: Button = $Panel/RestartButton


func _ready() -> void:
	visible = false
	restart_btn.pressed.connect(func():
		AudioBus.play_ui()
		restart_pressed.emit()
	)


func show_result(deepest: int, reason: String) -> void:
	visible = true
	if GameState.is_stroke_play() or (reason == "course_complete" and GameState.stroke_play_mode):
		_show_stroke_complete()
		return
	if reason == "course_complete":
		title.text = "COURSE CLEAR"
		detail.text = "Survival — finished all %d holes.\nScore %s · Deepest: %d" % [
			GameState.HOLE_COUNT,
			GameState.format_score_to_par(GameState.score_to_par),
			deepest,
		]
	else:
		title.text = "GAME OVER"
		detail.text = "Survival — keep the card alive.\nDeepest hole reached: %d / %d" % [
			deepest, GameState.HOLE_COUNT
		]


func _show_stroke_complete() -> void:
	title.text = "ROUND COMPLETE"
	var gross := GameState.format_score_to_par(GameState.score_to_par)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("18 Hole Round")
	lines.append("Gross  %s" % gross)
	if GameState.handicap_index() != null:
		lines.append("Net  %s" % GameState.format_score_to_par(GameState.net_score_to_par))
		lines.append(GameState.handicap_label())
	var card := _hole_card_line()
	if not card.is_empty():
		lines.append("")
		lines.append(card)
	detail.text = "\n".join(lines)


func _hole_card_line() -> String:
	## Compact hole-by-hole score-to-par (e.g. +1 E -1 …).
	if GameState.hole_scores.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for d in GameState.hole_scores:
		parts.append(GameState.format_score_to_par(int(d)))
	# Break into lines of 6 for readability on mobile.
	var rows: PackedStringArray = PackedStringArray()
	var i := 0
	while i < parts.size():
		var chunk: PackedStringArray = PackedStringArray()
		for j in mini(6, parts.size() - i):
			chunk.append(parts[i + j])
		rows.append(" ".join(chunk))
		i += 6
	return "\n".join(rows)


func hide_panel() -> void:
	AudioBus.stop_water_hazard()
	visible = false

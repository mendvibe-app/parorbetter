extends Control

## Shot breakdown stays until the player clicks / taps / presses a key.

signal dismissed

@onready var body: Label = $Panel/Margin/VBox/Body
@onready var strike_map: StrikeMap = $Panel/Margin/VBox/StrikeMap
@onready var hint: Label = $Hint
@onready var tempo_mini: TempoMini = $TempoMini

var _waiting: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(false)
	if hint == null:
		# Created in scene; tolerate missing node during reload
		hint = get_node_or_null("Hint") as Label
	if tempo_mini == null:
		tempo_mini = get_node_or_null("TempoMini") as TempoMini


func show_launch(report: ShotReport) -> void:
	_waiting = false
	set_process_input(false)
	body.text = report.glance_text()
	strike_map.show_strike(report)
	if hint:
		hint.text = ""
	if tempo_mini and not GameState.last_tempo_metrics.is_empty():
		tempo_mini.show_verdict(GameState.last_tempo_metrics, report.lie == "Green")
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_final(report: ShotReport) -> void:
	body.text = report.glance_text()
	strike_map.show_strike(report)
	if hint:
		hint.text = "Tap to continue"
	if tempo_mini and not GameState.last_tempo_metrics.is_empty():
		tempo_mini.show_verdict(GameState.last_tempo_metrics, report.lie == "Green")
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_waiting = true
	set_process_input(true)


func hide_now() -> void:
	_waiting = false
	set_process_input(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _accept_mouse() -> bool:
	return not DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not _waiting:
		return
	var go := false
	if event is InputEventScreenTouch and event.pressed:
		go = true
	elif event is InputEventMouseButton and event.pressed and _accept_mouse():
		go = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			go = true
	if not go:
		return
	_waiting = false
	set_process_input(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().set_input_as_handled()
	AudioBus.play_ui()
	dismissed.emit()

extends Node

## Lightweight procedural SFX via AudioStreamGenerator — no asset pack required.

var _players: Dictionary = {}


func _ready() -> void:
	for sfx_id in ["contact", "perfect", "birdie", "splash", "putt", "ui"]:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%s" % sfx_id
		p.bus = "Master"
		add_child(p)
		_players[sfx_id] = p


func play_tone(kind: String, freq: float = 440.0, duration: float = 0.12, volume_db: float = -8.0) -> void:
	var player: AudioStreamPlayer = _players.get(kind, _players["ui"])
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	player.stream = gen
	player.volume_db = volume_db
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var sample_rate := 22050.0
	var frames := int(duration * sample_rate)
	var phase := 0.0
	for i in frames:
		var t := float(i) / float(frames)
		var env := sin(PI * t)  # simple bell envelope
		var sample := sin(phase * TAU) * env * 0.35
		playback.push_frame(Vector2(sample, sample))
		phase += freq / sample_rate
		if phase >= 1.0:
			phase -= 1.0


func play_contact(quality: String) -> void:
	match quality:
		"perfect":
			# Short clean hit; full PURE chord comes from play_pure() on earned strikes
			play_tone("contact", 480.0, 0.08, -8.0)
			play_tone("perfect", 720.0, 0.1, -10.0)
		"thin":
			play_tone("contact", 720.0, 0.08, -10.0)
		"fat":
			play_tone("contact", 180.0, 0.14, -6.0)
		_:
			play_tone("contact", 320.0, 0.1, -10.0)


## Big rewarding chord for earned pure strikes.
func play_pure() -> void:
	play_tone("perfect", 523.25, 0.1, -3.0)
	await get_tree().create_timer(0.04).timeout
	play_tone("perfect", 783.99, 0.12, -2.0)
	await get_tree().create_timer(0.05).timeout
	play_tone("perfect", 1046.5, 0.18, -1.0)


func play_putt_drop() -> void:
	play_tone("putt", 220.0, 0.08, -6.0)
	await get_tree().create_timer(0.06).timeout
	play_tone("putt", 140.0, 0.16, -4.0)


func play_birdie() -> void:
	play_tone("birdie", 523.25, 0.12, -4.0)
	await get_tree().create_timer(0.1).timeout
	play_tone("birdie", 659.25, 0.12, -4.0)
	await get_tree().create_timer(0.1).timeout
	play_tone("birdie", 783.99, 0.18, -3.0)


func play_splash() -> void:
	play_tone("splash", 90.0, 0.22, -8.0)


func play_ui() -> void:
	play_tone("ui", 660.0, 0.06, -12.0)

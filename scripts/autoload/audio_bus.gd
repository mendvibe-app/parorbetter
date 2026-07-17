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
	var playback := _begin_playback(kind, volume_db, maxf(0.1, duration + 0.05))
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


## Band-passed noise burst with a fast decay — hollow plastic knocks, not UI beeps.
func play_noise(kind: String, duration: float = 0.02, volume_db: float = -10.0, lp_alpha: float = 0.28) -> void:
	var playback := _begin_playback(kind, volume_db, maxf(0.1, duration + 0.05))
	if playback == null:
		return
	_push_filtered_noise(playback, 22050.0, duration, 0.55, lp_alpha)


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


## Ball clips the cup liner, then bottoms out — one continuous clip on the putt bus.
func play_putt_drop() -> void:
	var sample_rate := 22050.0
	var playback := _begin_playback("putt", -5.0, 0.4)
	if playback == null:
		return

	# Rattle first (~120ms of short muffled noise pulses with gaps)
	var t := 0.0
	while t < 0.12:
		var burst := randf_range(0.012, 0.028)
		_push_filtered_noise(playback, sample_rate, burst, 0.55)
		t += burst
		if t >= 0.12:
			break
		var gap := randf_range(0.006, 0.018)
		_push_silence(playback, sample_rate, gap)
		t += gap

	# Bottom-out thud: short pitch sweep, solid plastic cup floor
	_push_pitch_sweep(playback, sample_rate, 200.0, 55.0, 0.045, 0.7)


func _begin_playback(kind: String, volume_db: float, buffer_length: float) -> AudioStreamGeneratorPlayback:
	var player: AudioStreamPlayer = _players.get(kind, _players["ui"])
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = buffer_length
	player.stream = gen
	player.volume_db = volume_db
	player.play()
	return player.get_stream_playback() as AudioStreamGeneratorPlayback


func _push_filtered_noise(
	playback: AudioStreamGeneratorPlayback,
	sample_rate: float,
	duration: float,
	amp: float,
	lp_alpha: float = 0.28
) -> void:
	var frames := int(duration * sample_rate)
	var lp_fast := 0.0
	var lp_slow := 0.0
	var a_fast := lp_alpha
	var a_slow := lp_alpha * 0.25
	for i in frames:
		var u := float(i) / float(maxi(frames - 1, 1))
		var env := (1.0 - u) * (1.0 - u)
		var n := randf_range(-1.0, 1.0)
		lp_fast += a_fast * (n - lp_fast)
		lp_slow += a_slow * (n - lp_slow)
		var sample := (lp_fast - lp_slow) * env * amp
		playback.push_frame(Vector2(sample, sample))


func _push_silence(playback: AudioStreamGeneratorPlayback, sample_rate: float, duration: float) -> void:
	for i in int(duration * sample_rate):
		playback.push_frame(Vector2.ZERO)


func _push_pitch_sweep(
	playback: AudioStreamGeneratorPlayback,
	sample_rate: float,
	freq_start: float,
	freq_end: float,
	duration: float,
	amp: float
) -> void:
	var frames := int(duration * sample_rate)
	var phase := 0.0
	for i in frames:
		var u := float(i) / float(maxi(frames - 1, 1))
		var freq := lerpf(freq_start, freq_end, u)
		var env := exp(-u * 5.0) * minf(1.0, u * 40.0)
		var sample := sin(phase * TAU) * env * amp
		playback.push_frame(Vector2(sample, sample))
		phase += freq / sample_rate
		if phase >= 1.0:
			phase -= 1.0


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

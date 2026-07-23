extends Node

## Sample contact/pure/putt + procedural splash/birdie/ui/tick.

const _CONTACT := {
	"perfect": preload("res://assets/sfx/contact_perfect.wav"),
	"good": preload("res://assets/sfx/contact_good.wav"),
	"thin": preload("res://assets/sfx/contact_thin.wav"),
	"fat": preload("res://assets/sfx/contact_fat.wav"),
	"miss": preload("res://assets/sfx/contact_fat.wav"),  # no miss clip; reuse fat
}
const _PURE: AudioStream = preload("res://assets/sfx/contact_pure.wav")
## Loaded in _ready — avoids parse-time preload race before Godot imports new WAVs.
var _PUTT: AudioStream
var _PUTT_DROP: AudioStream

var _players: Dictionary = {}


func _ready() -> void:
	_PUTT = load("res://assets/sfx/putt.wav") as AudioStream
	_PUTT_DROP = load("res://assets/sfx/putt_drop.wav") as AudioStream
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
	var stream: AudioStream = _CONTACT.get(quality, _CONTACT["good"])
	_play_stream("contact", stream, -6.0)


## Earned pure sting — layered on top of play_contact("perfect").
func play_pure() -> void:
	_play_stream("perfect", _PURE, -4.0)


func _play_stream(kind: String, stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _players.get(kind, _players["ui"])
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Putter face → ball.
func play_putt() -> void:
	_play_stream("putt", _PUTT, -6.0)


## Ball drops in the cup.
func play_putt_drop() -> void:
	_play_stream("putt", _PUTT_DROP, -5.0)


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


## Soft metronome tick for fadeable tempo guide — golf-leaning, not arcade beep.
func play_tick(volume_scale: float = 1.0) -> void:
	play_tone("ui", 520.0, 0.035, lerpf(-22.0, -14.0, clampf(volume_scale, 0.0, 1.0)))


## Soft putt-pad ticks (takeaway / marker cross) — cooler + quieter than swing metronome.
func play_putt_tick(volume_scale: float = 1.0) -> void:
	play_tone("ui", 380.0, 0.028, lerpf(-24.0, -16.0, clampf(volume_scale, 0.0, 1.0)))


## Gentle pure-putt chime — replaces the full-swing compression crack on greens.
func play_putt_pure() -> void:
	play_tone("perfect", 660.0, 0.08, -10.0)
	get_tree().create_timer(0.06).timeout.connect(
		func(): play_tone("perfect", 880.0, 0.12, -8.0), CONNECT_ONE_SHOT
	)

class_name Sfx
extends Node
## The prototype's synthesised tones, rebuilt as short AudioStreamWAV clips at start-up and
## played from a small pool of players (Star Breaker found AudioStreamPolyphonic and looping
## WAVs unreliable on Android). Placeholder sounds until the real SFX set (vertical slice).

const RATE := 22050
const POOL := 6

var enabled := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _clips := {}


func _ready() -> void:
	for i in POOL:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		_players.append(pl)
	_clips.launch = tone(300, 160, 0.18, "triangle", 0.08)
	_clips.revisit = tone(330, 440, 0.1, "sine", 0.06)
	_clips.spark = tone(990, 1480, 0.1, "square", 0.04)
	_clips.die = tone(220, 60, 0.45, "sawtooth", 0.07)
	_clips.toggle = tone(520, 780, 0.12, "sine", 0.12)
	_clips.perigee = chime([880.0, 1318.5], 0.09, 0.1) # a bright rising fifth
	_clips.leap = chime([660.0, 880.0, 1100.0], 0.07, 0.09)
	_clips.graze = tone(620, 520, 0.08, "triangle", 0.05)
	# a new moon rises in pitch with each hop, wrapping every 12
	for i in 12:
		var f := 440.0 * pow(1.06, i)
		_clips["catch%d" % i] = tone(f, f * 2.0, 0.16, "sine", 0.1)


func play(name: String) -> void:
	if not enabled or not _clips.has(name):
		return
	var pl := _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = _clips[name]
	pl.play()


func catch_sound(hops: int) -> String:
	return "catch%d" % (mini(hops, 24) % 12)


## Short notes one after another, mixed into one clip.
static func chime(freqs: Array, note: float, vol: float) -> AudioStreamWAV:
	var parts: Array[PackedByteArray] = []
	for f in freqs:
		parts.append(tone(f, f * 1.01, note * 1.6, "sine", vol).data)
	var total := int(note * RATE) * (freqs.size() - 1) * 2 + parts[-1].size()
	var mix := PackedFloat32Array()
	mix.resize(total / 2)
	for i in parts.size():
		var off := int(note * RATE) * i
		for j in parts[i].size() / 2:
			mix[off + j] += parts[i].decode_s16(j * 2) / 32767.0
	var bytes := PackedByteArray()
	bytes.resize(mix.size() * 2)
	for i in mix.size():
		bytes.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w


## A tone sweeping exponentially from f1 to f2 Hz with an exponential fade, like the web
## prototype's oscillator + gain ramp.
static func tone(f1: float, f2: float, dur: float, wave: String, vol: float) -> AudioStreamWAV:
	var n := int((dur + 0.02) * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var tt := float(i) / RATE
		var k := minf(tt / dur, 1.0)
		var f := f1 * pow(f2 / f1, k)
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"sine":
				s = sin(phase * TAU)
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			_:
				s = 2.0 * phase - 1.0
		var g := vol * pow(0.0001 / vol, k) if tt < dur else 0.0
		bytes.encode_s16(i * 2, int(clampf(s * g * 2.5, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

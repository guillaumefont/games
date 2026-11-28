class_name Sound
extends Node
## Music and sound effects. All audio is original, synthesised by tools/audio/compose.py:
## a looping track per world theme, one for the mid-bosses and one for the fortresses (loop=true in
## their .import files) that crossfade, and short effects
## played from a small pool of players, each with its own level and a minimum gap so rapid
## fire doesn't stack into noise. Music plays on the "Music" bus, effects on "Sfx".

## Track name -> file. The world tracks are named after `Campaign.WORLDS[].theme`.
const TRACKS := {
	"coast": "res://audio/music/sortie.ogg", "dunes": "res://audio/music/dunes.ogg",
	"city": "res://audio/music/city.ogg", "ice": "res://audio/music/ice.ogg",
	"volcano": "res://audio/music/volcano.ogg", "boss": "res://audio/music/carrier.ogg",
	"fortress": "res://audio/music/fortress.ogg"}
## Effect: [volume dB, minimum seconds between two plays, pitch jitter].
const FX := {
	"shot": [-16.0, 0.07, 0.06], "missile": [-11.0, 0.12, 0.05], "hit": [-15.0, 0.05, 0.12],
	"shield": [-12.0, 0.1, 0.05], "pop": [-8.0, 0.04, 0.12], "boom": [-5.0, 0.08, 0.06],
	"crash": [-2.0, 0.2, 0.0], "hurt": [-3.0, 0.2, 0.0], "scrap": [-12.0, 0.06, 0.08],
	"buy": [-6.0, 0.1, 0.0], "launch": [-6.0, 0.3, 0.0], "swoop": [-5.0, 0.3, 0.0],
	"warning": [-6.0, 0.5, 0.0], "clear": [-4.0, 0.5, 0.0], "down": [-4.0, 0.5, 0.0],
	"tap": [-10.0, 0.05, 0.0]}
## Callout: [priority, cooldown seconds]. Priority 1 cuts in as soon as no line is playing, 2 waits its turn
## (one line waits at most), 3 is dropped when the radio is busy or just spoke.
const VOICE := {
	"down": [1, 0.0], "critical": [1, 8.0], "victory": [1, 0.0],
	"launch": [2, 0.0], "warning": [2, 0.0], "fortress": [2, 0.0], "intercept": [2, 0.0],
	"boss_down": [2, 0.0], "reactor": [2, 0.0], "clear": [2, 0.0], "world_clear": [2, 0.0],
	"new_foe": [3, 4.0], "section": [3, 0.0], "power": [3, 6.0], "power_max": [3, 10.0]}
const VOICE_DB := -1.0
## How far the music dips while the radio speaks.
const VOICE_DUCK := -7.0
## Quiet time after a line before the next (priority 1 doesn't wait for it).
const VOICE_GAP := 2.0
## A waiting line older than this is no longer worth saying.
const VOICE_STALE := 4.0
const MUSIC_DB := -9.0
const DUCK_DB := -8.0
const SILENT := -60.0
const FADE := 1.2
const VOICES := 12

var track := ""
var ducked := false
## Effects played, for tests.
var played: Array[String] = []
var _music: Array[AudioStreamPlayer] = []
var _cur := 0
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _streams := {}
var _tweens: Array[Tween] = [null, null]
var _clock := 0.0
## Callouts on (the hangar's switch).
var voice_on := true
## Callouts started, for tests.
var said: Array[String] = []
var _radio: AudioStreamPlayer
var _said_t := {}
var _busy_until := -100.0
var _pending := ""
var _pending_t := 0.0
var _duck := 0.0


static func ensure_buses() -> void:
	for b in ["Music", "Sfx", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT
		add_child(p)
		_music.append(p)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_voices.append(p)
	_radio = AudioStreamPlayer.new()
	_radio.bus = "Voice"
	_radio.volume_db = VOICE_DB
	add_child(_radio)


func _process(dt: float) -> void:
	_clock += dt
	if _pending != "":
		if _clock - _pending_t > VOICE_STALE:
			_pending = ""
		elif _clock >= _busy_until + (0.0 if int(VOICE[_pending][0]) == 1 else VOICE_GAP):
			var k := _pending
			_pending = ""
			_say(k)
	# the music dips under the voice and comes back up once it ends
	var want := VOICE_DUCK if talking() else 0.0
	_duck = move_toward(_duck, want, dt * 30.0)
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, _duck)


## Whether a callout is playing.
func talking() -> bool:
	return _clock < _busy_until


## Asks for callout `key`. Returns "play" (started now), "wait" (it goes once the current line and the
## gap are over) or "" (dropped: switched off, on cooldown, or not worth waiting for).
func speak(key: String) -> String:
	if not voice_on or not VOICE.has(key):
		return ""
	var pri: int = VOICE[key][0]
	var cd: float = VOICE[key][1]
	if _said_t.has(key) and _clock - float(_said_t[key]) < cd:
		return ""
	var hushed := _clock < _busy_until + VOICE_GAP
	if not hushed or (pri == 1 and not talking()):
		_said_t[key] = _clock
		_say(key)
		return "play"
	if pri == 3:
		return ""
	if _pending != "" and not (pri == 1 and int(VOICE[_pending][0]) > 1):
		return ""
	_said_t[key] = _clock
	_pending = key
	_pending_t = _clock
	return "wait"


## Drops any waiting callout and cuts the current one (back to the hangar).
func hush() -> void:
	_pending = ""
	_busy_until = -100.0
	if _radio:
		_radio.stop()


func _say(key: String) -> void:
	var picks := variants(key)
	var file: String = picks[randi() % picks.size()]
	if not _streams.has(file):
		_streams[file] = load(file)
	var st: AudioStream = _streams[file]
	said.append(key)
	_busy_until = _clock + st.get_length()
	_radio.stream = st
	_radio.play()


## The clips of callout `key`: audio/voice/key.ogg, then key_2.ogg, key_3.ogg... as far as they go.
static func variants(key: String) -> Array[String]:
	var out: Array[String] = ["res://audio/voice/%s.ogg" % key]
	var n := 2
	while ResourceLoader.exists("res://audio/voice/%s_%d.ogg" % [key, n]):
		out.append("res://audio/voice/%s_%d.ogg" % [key, n])
		n += 1
	return out


## Crossfades to `name` ("" for silence); `duck` lowers it (hangar, results).
func music(name: String, duck := false) -> void:
	if name == track and duck == ducked:
		return
	var want := SILENT if name == "" else MUSIC_DB + (DUCK_DB if duck else 0.0)
	if name == track:
		ducked = duck
		_fade(_cur, want)
		return
	track = name
	ducked = duck
	_fade(_cur, SILENT)
	if name == "":
		return
	_cur = 1 - _cur
	var p := _music[_cur]
	p.stream = load(TRACKS[name])
	p.volume_db = SILENT
	p.play()
	_fade(_cur, want)


func _fade(i: int, db: float) -> void:
	if _tweens[i]:
		_tweens[i].kill()
	var p := _music[i]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, FADE)
	if db <= SILENT:
		tw.tween_callback(p.stop)
	_tweens[i] = tw


## Plays effect `name`, unless it played less than its minimum gap ago.
func play(name: String, gain_db := 0.0) -> void:
	var cfg: Array = FX[name]
	if _clock - float(_last.get(name, -10.0)) < float(cfg[1]):
		return
	_last[name] = _clock
	played.append(name)
	if not _streams.has(name):
		_streams[name] = load("res://audio/sfx/%s.ogg" % name)
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.volume_db = float(cfg[0]) + gain_db
	p.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * float(cfg[2])
	p.play()

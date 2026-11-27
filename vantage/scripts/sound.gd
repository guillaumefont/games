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


static func ensure_buses() -> void:
	for b in ["Music", "Sfx"]:
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


func _process(dt: float) -> void:
	_clock += dt


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

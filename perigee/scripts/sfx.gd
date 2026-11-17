class_name Sfx
extends Node
## Sound effects: short Ogg clips in audio/sfx/, made by tools/audio/compose.py (all in D major
## pentatonic, the music's key), played from a small pool of players on the "Sfx" bus.
## Star Breaker found AudioStreamPolyphonic and looping WAVs unreliable on Android, hence the pool.

const POOL := 8
const NAMES := ["launch", "revisit", "spark", "die", "toggle", "perigee", "leap", "graze", "clear", "star"]

var enabled := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _clips := {}


## The "Music" and "Sfx" buses, so the settings screen can set their volumes.
static func ensure_buses() -> void:
	for bus in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	ensure_buses()
	for i in POOL:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Sfx"
		add_child(pl)
		_players.append(pl)
	var names: Array = NAMES.duplicate()
	for i in 12:
		names.append("catch%d" % i)
	for n in names:
		_clips[n] = load("res://audio/sfx/%s.ogg" % n)


func has_clip(name: String) -> bool:
	return _clips.get(name) != null


func play(name: String, delay := 0.0) -> void:
	if not enabled or not _clips.has(name):
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(play.bind(name))
		return
	var pl := _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = _clips[name]
	pl.play()


## A new moon rings one pentatonic step higher with each hop, wrapping every 12.
func catch_sound(hops: int) -> String:
	return "catch%d" % (mini(hops, 24) % 12)

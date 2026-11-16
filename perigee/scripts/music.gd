class_name Music
extends Node
## Background music: one looping Ogg track (audio/music/, made by tools/audio/compose.py, loop=true
## in its .import file), faded in and out, and lowered while the game is paused. Plays on the
## "Music" bus.

const TRACKS := {"drift": "res://audio/music/drift.ogg"}
const VOLUME_DB := -8.0
const DUCK_DB := -10.0
const SILENT := -60.0
const FADE := 1.0

var enabled := false:
	set(v):
		enabled = v
		_apply()
var ducked := false:
	set(v):
		if v != ducked:
			ducked = v
			_apply()
var current := ""
var player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	Sfx.ensure_buses()
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.volume_db = SILENT
	add_child(player)
	_apply()


func play(track: String) -> void:
	current = track
	_apply()


## The volume the player is heading for (SILENT when off).
func target_db() -> float:
	if not enabled or current == "":
		return SILENT
	return VOLUME_DB + (DUCK_DB if ducked else 0.0)


func _apply() -> void:
	if player == null:
		return
	var want := target_db()
	if want > SILENT:
		var stream: AudioStream = load(TRACKS[current])
		if player.stream != stream:
			player.stream = stream
		if not player.playing:
			player.play()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", want, FADE)
	if want <= SILENT:
		_tween.tween_callback(player.stop)

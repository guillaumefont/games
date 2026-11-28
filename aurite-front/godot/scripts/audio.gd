class_name GameAudio
extends Node
## Pre-rendered synth effects (with reverb baked in) and a two-layer march that follows the fighting.

const MINGAP := {"gun": .06, "snipe": .1, "small": .07, "shell": .08, "heavy": .1, "mortar": .12, "rocket": .09, "flak": .1, "flame": .12, "arc": .1, "boom": .1, "bigboom": .15, "click": .03, "ack": .12, "ready": .3, "alert": 1.0, "place": .2, "siren": 2.0, "shard": .06, "geode": .12, "burrow": .15}
const NAMES := ["gun", "snipe", "shell", "heavy", "mortar", "rocket", "flak", "flame", "arc", "small", "boom", "bigboom", "click", "ack", "ack_ashen", "ready", "alert", "place", "siren", "shard", "geode", "burrow", "ack_choir"]

var streams := {}
var pool: Array = []
var pi := 0
var last := {}
var muted := false
var music_on := true
var calm: AudioStreamPlayer
var combat: AudioStreamPlayer
var music_level := 0.0
var music_target := 0.0
var intensity := 0.0
var mood := 0   # story mood of the mission being played (Campaign.mood): picks the theme once the staged music lands
var pan_bus := ["SfxL", "SfxC", "SfxR"]
# Announcer (voice alerts, 2026-11-28): one voice per faction, rules in scripts/voice.gd, clips in res://voice/<fac>/.
const Announcer := preload("res://scripts/voice.gd")
const VOICE_DB := -6.0     # overall voice level; the clips are all rendered to the same loudness
var voice_on := true
var ann = Announcer.new()
var voice: AudioStreamPlayer
var clips := {}            # key -> stream, for the faction being played
var voice_fac := ""

func _ready() -> void:
	# Mix (2026-11-16): effects share one "Sfx" bus with a gentle glue compressor, and the music ducks under
	# busy fighting through a compressor keyed on that bus. Nothing is made louder (Guillaume, PR #4).
	var si := AudioServer.bus_count
	AudioServer.add_bus(si); AudioServer.set_bus_name(si, "Sfx"); AudioServer.set_bus_send(si, "Master")
	var glue := AudioEffectCompressor.new(); glue.threshold = -14.0; glue.ratio = 2.5; glue.attack_us = 8000.0; glue.release_ms = 180.0
	AudioServer.add_bus_effect(si, glue)
	for i in 3:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx); AudioServer.set_bus_name(idx, pan_bus[i]); AudioServer.set_bus_send(idx, "Sfx")
		var p := AudioEffectPanner.new(); p.pan = [-0.55, 0.0, 0.55][i]
		AudioServer.add_bus_effect(idx, p)
	var mi := AudioServer.bus_count
	AudioServer.add_bus(mi); AudioServer.set_bus_name(mi, "Music"); AudioServer.set_bus_send(mi, "Master")
	var duck := AudioEffectCompressor.new(); duck.sidechain = &"Sfx"; duck.threshold = -24.0; duck.ratio = 3.0
	duck.attack_us = 15000.0; duck.release_ms = 600.0
	AudioServer.add_bus_effect(mi, duck)
	var vi := AudioServer.bus_count
	AudioServer.add_bus(vi); AudioServer.set_bus_name(vi, "Voice"); AudioServer.set_bus_send(vi, "Master")
	var lim := AudioEffectLimiter.new(); AudioServer.add_bus_effect(0, lim)
	for n in NAMES:
		var path := "res://sfx/%s.wav" % n
		if ResourceLoader.exists(path): streams[n] = load(path)
	for i in 18:
		var p := AudioStreamPlayer.new(); add_child(p); pool.append(p)
	calm = AudioStreamPlayer.new(); calm.bus = "Music"; add_child(calm)
	combat = AudioStreamPlayer.new(); combat.bus = "Music"; add_child(combat)
	if ResourceLoader.exists("res://music/march_calm.ogg"):
		calm.stream = load("res://music/march_calm.ogg"); combat.stream = load("res://music/march_combat.ogg")
		calm.stream.loop = true; combat.stream.loop = true
	calm.volume_db = -80; combat.volume_db = -80
	voice = AudioStreamPlayer.new(); voice.bus = "Voice"; voice.volume_db = VOICE_DB; add_child(voice)

func play(n: String, pan := 0.0, vol := 1.0) -> void:
	if muted: return
	var now := Time.get_ticks_msec() / 1000.0
	if last.has(n) and now - last[n] < MINGAP.get(n, .05): return
	last[n] = now
	if not streams.has(n): return
	var p: AudioStreamPlayer = pool[pi]; pi = (pi + 1) % pool.size()
	p.stream = streams[n]
	p.bus = pan_bus[0] if pan < -0.33 else (pan_bus[2] if pan > 0.33 else pan_bus[1])
	p.volume_db = linear_to_db(max(0.001, vol * 0.75))
	p.play()

## A new match: the announcer speaks for the player's faction and forgets the last match's cooldowns.
func voice_start(fac: String) -> void:
	ann.reset(); voice.stop()
	if fac == voice_fac: return
	voice_fac = fac; clips.clear()
	for k in Announcer.EV:
		var path := "res://voice/%s/%s.ogg" % [fac, k]
		if ResourceLoader.exists(path): clips[k] = load(path)

## A game event for the announcer (pos: where it happens, for the "under attack" lines).
func say(key: String, pos = null) -> void:
	if muted or not voice_on or not clips.has(key): return
	if ann.request(key, _now(), pos) == "play": _speak(key)

func _speak(key: String) -> void:
	voice.stream = clips[key]; voice.play()
	ann.started(_now(), clips[key].get_length())

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func music_start() -> void:
	if not music_on or calm.stream == null: return
	if not calm.playing:
		calm.play(); combat.play()
	music_target = 1.0

func music_stop() -> void:
	music_target = 0.0

func _process(dt: float) -> void:
	var nk: String = ann.poll(_now())
	if nk != "" and clips.has(nk) and not muted and voice_on: _speak(nk)
	# the music dips a little while the announcer speaks
	var dip := 0.6 if voice.playing else 1.0
	music_level = move_toward(music_level, music_target, dt * (0.6 if music_target > music_level else 1.5))
	if calm.playing:
		var w := clampf(intensity * 1.6 - 0.15, 0.0, 1.0)
		calm.volume_db = linear_to_db(max(0.0001, music_level * dip * 0.8 * (1.0 - w * 0.6)))
		combat.volume_db = linear_to_db(max(0.0001, music_level * dip * 0.85 * w))
		# keep the two layers locked together
		if abs(combat.get_playback_position() - calm.get_playback_position()) > 0.08 and calm.get_playback_position() > 0.2:
			combat.seek(calm.get_playback_position())
		if music_level <= 0.0 and music_target <= 0.0:
			calm.stop(); combat.stop()

func set_paused(p: bool) -> void:
	calm.stream_paused = p; combat.stream_paused = p; voice.stream_paused = p

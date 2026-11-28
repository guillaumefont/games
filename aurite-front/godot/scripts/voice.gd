extends RefCounted
## The announcer's rules: who may speak, when, and what waits. No audio here (GameAudio plays the clips), so the
## anti-spam rules can be tested headless. Lines: tools/voice_lines.tsv, rendered by tools/voice.py to
## res://voice/<faction>/<key>.ogg. Plan approved by Guillaume 2026-11-28 ("Great, implement audio").
## No class_name: an installed shell would not know a new global class (preload it).

## key: [priority, cooldown in seconds]. Priority 1 cuts in front of anything, 2 waits its turn, 3 is dropped when
## the announcer has spoken in the last few seconds. Cooldown -1 = once per match.
const EV := {
	"base_attack": [1, 30.0], "bld_lost": [1, 10.0], "sw_enemy_armed": [1, 20.0], "sw_enemy_launch": [1, 0.0],
	"won": [1, -1.0], "lost": [1, -1.0],
	"units_attack": [2, 25.0], "harv_attack": [2, 25.0], "no_aurite": [2, 15.0], "cap": [2, 20.0],
	"low_power": [2, 30.0], "signal_lost": [2, 20.0], "wave": [2, 20.0], "new_enemy": [2, 20.0], "bld_stolen": [2, 15.0],
	"built": [3, 4.0], "unit_ready": [3, 4.0], "landed": [3, 6.0], "upgraded": [3, 6.0], "sw_ready": [3, 20.0],
	"objective": [3, 6.0], "captured": [3, 6.0], "repaired": [3, 10.0], "muster": [3, -1.0], "fusion": [3, 10.0],
}
const GAP := 2.5          # quiet time after any line (priority 1 ignores it)
const STALE := 6.0        # a waiting line older than this is no longer worth saying
const NEAR := 12.0 * 32.0 # "under attack" again within this many world units of the last warning = the same fight
const SIEGE := ["base_attack", "units_attack", "harv_attack"]

var last := {}            # key -> time it was last said (or queued)
var spot := {}            # key -> Vector2 where an "under attack" line was last about
var busy_until := -100.0  # the current line ends
var pending := ""         # at most one line waits
var pending_t := 0.0

func reset() -> void:
	last.clear(); spot.clear(); busy_until = -100.0; pending = ""

func pri(key: String) -> int:
	return EV[key][0] if EV.has(key) else 9

## A game event asks to be announced. Returns "play" (start it now), "wait" (queued) or "" (dropped).
func request(key: String, now: float, pos = null) -> String:
	if not EV.has(key): return ""
	var p: int = EV[key][0]; var cd: float = EV[key][1]
	if last.has(key):
		if cd < 0: return ""
		if now - last[key] < cd:
			# the same fight keeps going: stay quiet and keep the cooldown running; a new spot gets its warning
			if key in SIEGE and pos != null and spot.has(key) and (pos as Vector2).distance_to(spot[key]) < NEAR:
				last[key] = now; spot[key] = pos
				return ""
			if not (key in SIEGE and pos != null and spot.has(key)): return ""
	var talking := now < busy_until
	var hushed := now < busy_until + GAP
	var out := ""
	if not hushed or (p == 1 and not talking): out = "play"
	elif p == 3: return ""
	elif pending == "" or (p == 1 and pri(pending) > 1): out = "wait"
	else: return ""
	last[key] = now
	if pos != null: spot[key] = pos
	if out == "wait": pending = key; pending_t = now
	return out

## The line that should start now, if any (call every frame).
func poll(now: float) -> String:
	if pending == "": return ""
	if now - pending_t > STALE: pending = ""; return ""
	if now < busy_until + (0.0 if pri(pending) == 1 else GAP): return ""
	var k := pending; pending = ""
	return k

## A line started and lasts dur seconds.
func started(now: float, dur: float) -> void:
	busy_until = now + dur

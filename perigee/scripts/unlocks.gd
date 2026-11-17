class_name Unlocks
extends RefCounted
## The spark unlock track (Guillaume's pick of 2026-11-16): every spark collected, in any mode,
## moves the player along one fixed track, and cosmetics unlock in order as it fills. No capsules,
## no random rewards. Cosmetics only change how things look, never the game. Later, a purchase
## will fill the track faster; it will never buy anything that changes a score.
##
## `at` is the all-time spark count (save.data.sparks) that unlocks an item.

const TRACK: Array[Dictionary] = [
	{"id": "ship_pebble", "kind": "ship", "name": "Pebble", "at": 0},
	{"id": "trail_stardust", "kind": "trail", "name": "Stardust", "at": 0},
	{"id": "palette_pastel", "kind": "palette", "name": "Pastel", "at": 0},
	{"id": "trail_comet", "kind": "trail", "name": "Comet", "at": 15},
	{"id": "ship_dart", "kind": "ship", "name": "Dart", "at": 40},
	{"id": "palette_aurora", "kind": "palette", "name": "Aurora", "at": 80},
	{"id": "trail_ribbon", "kind": "trail", "name": "Ribbon", "at": 130},
	{"id": "ship_halo", "kind": "ship", "name": "Halo", "at": 200},
	{"id": "palette_ember", "kind": "palette", "name": "Ember", "at": 300},
	{"id": "trail_sparkle", "kind": "trail", "name": "Sparkle", "at": 420},
]

## Cosmetics that are not on the track: each is the reward for a feat (see Medals.rewards), with
## `reward` the id of that reward. Never sold.
const REWARD_ITEMS: Array[Dictionary] = [
	{"id": "ship_laurel", "kind": "ship", "name": "Laurel", "reward": "Cradle:stars", "how": "All Cradle stars"},
]

const KINDS := ["ship", "trail", "palette"]
const DEFAULT_EQUIPPED := {"ship": "ship_pebble", "trail": "trail_stardust", "palette": "palette_pastel"}

## Moon colours by palette: four colours each, told apart by lightness as well as hue.
const PALETTES := {
	"palette_pastel": [Color("ff8a6b"), Color("6fd6c5"), Color("f2c879"), Color("b49cff")],
	"palette_aurora": [Color("5ee6a8"), Color("4fb3ff"), Color("c4f27a"), Color("9a7dff")],
	"palette_ember": [Color("ff6b5a"), Color("ffb347"), Color("ffe08a"), Color("e0688f")],
}


static func item(id: String) -> Dictionary:
	for it in TRACK + REWARD_ITEMS:
		if it.id == id:
			return it
	return {}


## Unlocked at `sparks` all-time, or for a reward item, once its reward is in `claimed`
## (save.data.rewards).
static func is_unlocked(id: String, sparks: int, claimed: Array = []) -> bool:
	var it := item(id)
	if it.has("reward"):
		return claimed.has(it.reward)
	return not it.is_empty() and sparks >= int(it.at)


## The reward item a reward id unlocks, or {}.
static func reward_item(reward_id: String) -> Dictionary:
	for it in REWARD_ITEMS:
		if it.reward == reward_id:
			return it
	return {}


## Items unlocked by going from `before` to `after` sparks, in track order.
static func newly_unlocked(before: int, after: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in TRACK:
		if before < int(it.at) and after >= int(it.at):
			out.append(it)
	return out


## The next item still locked at `sparks`, or {} when the track is full.
static func next_item(sparks: int) -> Dictionary:
	for it in TRACK:
		if sparks < int(it.at):
			return it
	return {}


## How far along the step to the next item, 0..1 (1 when the track is full).
static func progress(sparks: int) -> float:
	var nxt := next_item(sparks)
	if nxt.is_empty():
		return 1.0
	var prev := 0
	for it in TRACK:
		if int(it.at) <= sparks:
			prev = maxi(prev, int(it.at))
	return clampf(float(sparks - prev) / float(int(nxt.at) - prev), 0.0, 1.0)


static func palette(id: String) -> Array:
	return PALETTES.get(id, PALETTES.palette_pastel)


static func label(it: Dictionary) -> String:
	return "%s %s" % [it.name, it.kind]

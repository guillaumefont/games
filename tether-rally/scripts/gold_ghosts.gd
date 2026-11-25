# The Gold medal ghost (docs/monetization.md): for each track and lap variant (Standard,
# Reverse, Obstacles; Collect has none, its medal is a whole-run score) a lap of the AI,
# slowed to finish exactly at the Gold time, made by tools/gen_gold_ghosts.gd into
# res://ghosts/gold.res (rerun it after changing a layout, like tools/gen_medals.gd).
# Samples are 30 a second, like the player's own ghost (Records): x, y, heading, and
# whether the rope is hooked (for the ideal line).
# The Gold ghost and the ideal line (the Gold lap drawn on the road) are consumables
# (Guillaume, 2026-11-25): off by default, each rewarded video (free with "No ads") adds one
# run, runs stack, and one is used at GO of a Time trial run on a track + variant without
# Gold yet (given back if that run is left during its first lap). Counts live in
# user://wallet.cfg (section "perks"), so Reset progress clears them.
extends RefCounted

const Wallet = preload("res://scripts/wallet.gd")
const Medals = preload("res://scripts/medals.gd")

const PATH := "res://ghosts/gold.res"
const VARIANTS := ["standard", "reverse", "obstacles"]
const RATE := 30.0

static var _data: Dictionary   # key -> PackedFloat32Array (x, y, h, hooked) * samples

static func key(track_name: String, variant: String) -> String:
	return "%s|%s" % [track_name, variant]

static func _all() -> Dictionary:
	if _data.is_empty() and ResourceLoader.exists(PATH):
		var r: Resource = load(PATH)
		if r and r.has_meta("traces"):
			_data = r.get_meta("traces")
	return _data

static func has(track_name: String, variant: String) -> bool:
	return VARIANTS.has(variant) and _all().has(key(track_name, variant))

static func _flat(track_name: String, variant: String) -> PackedFloat32Array:
	return _all().get(key(track_name, variant), PackedFloat32Array())

# the lap as Records ghosts are: Vector3(x, y, heading) at 30 a second
static func trace(track_name: String, variant: String) -> Array:
	var f := _flat(track_name, variant)
	var out: Array = []
	for i in range(0, f.size() - 3, 4):
		out.append(Vector3(f[i], f[i + 1], f[i + 2]))
	return out

# is the rope hooked at each sample
static func hooked(track_name: String, variant: String) -> Array:
	var f := _flat(track_name, variant)
	var out: Array = []
	for i in range(3, f.size(), 4):
		out.append(f[i] > 0.5)
	return out

static func lap_time(track_name: String, variant: String) -> float:
	return _flat(track_name, variant).size() / 4.0 / RATE

# ---------------------------------------------------------------- consumable runs
const PERKS := ["gold_ghost", "ideal_line"]

static func charges(perk: String) -> int:
	return int(Wallet.get_v("perks", perk, 0))

static func add_charge(perk: String, n := 1) -> void:
	Wallet.set_v("perks", perk, maxi(0, charges(perk) + n))

# use one run; false when there is none left
static func use_charge(perk: String) -> bool:
	if charges(perk) <= 0:
		return false
	add_charge(perk, -1)
	return true

# which perks a run starts with: those with a run left, on a single-player Time trial of a
# track + variant that has a Gold lap and where the player has no Gold yet (a Special Stage has
# no medal, so it takes the ideal line but not the ghost)
static func perks_for(track_name: String, variant: String, held_tier: int, stage: bool) -> Array:
	var out: Array = []
	if not has(track_name, variant) or (held_tier >= 3 and not stage):
		return out
	for p in PERKS:
		if charges(p) > 0 and not (stage and p == "gold_ghost"):
			out.append(p)
	return out

# offer them on these results: a Time trial run that finished without Gold, where the player
# has no Gold yet
static func offer(track_name: String, variant: String, finished: bool, run_tier: int, held_tier: int) -> bool:
	return finished and run_tier < 3 and held_tier < 3 and has(track_name, variant)

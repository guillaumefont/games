class_name ShipKit
extends RefCounted
## A ship's own mechanic, for every ship but Lance (whose charge beam and Storm live in vgame.gd).
## One thumb plays them all: drag flies the ship 1:1 and fires `fire()` while the thumb is
## down, `hold()` runs every tick the thumb stays down, `lift()` runs when it comes up. Each ship
## loads its ultimate meter (`meter`, 0 to 1) its own way through `gain()`; once full, the next
## lift fires `ult()` instead of `lift()` (Guillaume, 2026-11-21: no pod, no detached thing to
## steer; every ship has its own design and mechanic). Subclasses live in scripts/kits/.

var g: Node3D          ## the game (vgame.gd)
var meter := 0.0       ## the ultimate meter, 0 to 1
var held := 0          ## ticks the thumb has been down since the last lift
var flash := 0         ## ticks left of the HUD bar's flash after a gain
var last_gain := 0.0
var nodes: Array = []  ## 3D nodes the kit made (freed by clear())


func _init(game: Node3D) -> void:
	g = game


## Called at the start of a stage, after the ship model is in the world.
func start() -> void:
	pass


## The thumb is down this tick (not while flying in or in the canyon run).
func hold() -> void:
	pass


## The thumb came up after `held` ticks (and the ultimate isn't ready).
func lift() -> void:
	pass


## Every tick of play, after the player moved.
func update() -> void:
	pass


## The ultimate. The meter is emptied by the caller.
func ult() -> void:
	pass


## The main gun, fired every `fire_every` ticks while the thumb is down.
func fire() -> void:
	var sp: float = VShips.KITS[g.G.ship].shot_speed
	g.shot(g.P.x - 2.4, g.P.y + 8, 0, sp, Models.M.shot, 1)
	g.shot(g.P.x + 2.4, g.P.y + 8, 0, sp, Models.M.shot, 1)


## How often the main gun fires (ticks); kits may slow it while holding.
func fire_every() -> int:
	return int(VShips.KITS[g.G.ship].fire_every)


## An enemy bullet is about to hit the play plane near the ship: true eats it.
func eats(_b: Dictionary) -> bool:
	return false


## The ship blew up (or a new one is flying in).
func reset() -> void:
	held = 0


## One line under the HUD meter.
func hint() -> String:
	return "FULL: LIFT FOR %s" % String(VShips.KITS[g.G.ship].ult_name).to_upper() if ready() else String(VShips.KITS[g.G.ship].loads).to_upper()


## Places the kit's 3D nodes (every frame).
func sync() -> void:
	pass


func ready() -> bool:
	return meter >= 1.0 and g.G.ult_t == 0


## Adds to the ultimate meter (not while an ultimate is going).
func gain(x: float) -> void:
	if g.G.ult_t > 0 or not g.P.alive or meter >= 1.0:
		return
	meter = minf(1.0, meter + x)
	flash = 14
	last_gain = x
	if meter >= 1.0:
		g.audio.play("ready", 4)
		g.shake = maxf(g.shake, 3.0)


func tick_hud() -> void:
	if flash > 0:
		flash -= 1


## Adds a node to the world and keeps it for clear().
func own(n: Node3D) -> Node3D:
	g.world.add_child(n)
	nodes.append(n)
	return n


func clear() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes = []

class_name VShips
extends RefCounted
## Ship kits for the portrait game (the vertical slice). Each ship has a main weapon that fires
## on its own while the thumb is down, a release (what happens when the thumb lifts) and an
## ultimate, loaded each ship's own way: Lance's Storm is the last stage of its charge bar (hold
## ULT_AT ticks, lift). Every other ship has a ShipKit (`kit`, scripts/kits/) with its own hold,
## lift and ultimate meter (`loads` says what fills it). No ship has a detached thing to steer:
## Guillaume dropped Warden's pod on 2026-11-21.

## `unlock`: how many stages must be cleared on Normal before the ship opens (0: from the start).
## `sub` is what hold and lift do, `loads` what fills the ultimate; both show in the hangar.
const KITS := {
	lance = {name = "Lance", sub = "Hold to charge the beam, lift to fire", release = "beam", ult = "storm", ult_name = "Storm",
		fire_every = 6, shot_speed = 6.5, unlock = 0, loads = "Keep holding past the Nova"},
	warden = {name = "Warden", sub = "Hold to raise a shield that eats bullets, lift to throw them back", release = "shield", ult = "shatter", ult_name = "Shatter",
		fire_every = 8, shot_speed = 5.5, kit = "warden", loads = "Bullets eaten load Shatter", unlock = 0},
	hornet = {name = "Hornet", sub = "Hold and fly under enemies to lock them, lift to fire a missile per lock", ult = "hive", ult_name = "Hive",
		fire_every = 7, shot_speed = 7.0, kit = "hornet", loads = "Missile hits load the Hive", unlock = 2},
	weaver = {name = "Weaver", sub = "Hold to trail a burning thread, close a loop and lift to cut what's inside", ult = "loom", ult_name = "Loom",
		fire_every = 6, shot_speed = 6.0, kit = "weaver", loads = "Loop cuts load the Loom", unlock = 4},
	anvil = {name = "Anvil", sub = "Hold to run the reticle up the screen, lift to drop a bomb on it", ult = "barrage", ult_name = "Barrage",
		fire_every = 11, shot_speed = 5.0, kit = "anvil", loads = "Bombed ground targets load the Barrage", unlock = 6},
}
const ORDER := ["lance", "warden", "hornet", "weaver", "anvil"]


## Turns a model built for the side-scroller (nose along +X, top along +Y) so that, seen by the
## portrait camera, its nose points up the screen and its top faces the camera.
static func top_down() -> Basis:
	return Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))


## Wraps a side-view model in a pivot that shows it from above, nose up.
static func upright(model: Node3D) -> Node3D:
	var piv := Node3D.new()
	model.transform.basis = top_down()
	piv.add_child(model)
	piv.set_meta("model", model)
	return piv


## Lance: a slimmer, longer hull than Warden's gunship, with a long cyan lance along its spine
## and narrow swept wings. Built with the same loft builder as `Models.ship()`.
static func lance() -> Node3D:
	var M := Models.M
	var g := Node3D.new()
	var body := Node3D.new()
	g.add_child(body)
	body.add_child(Models.mesh(Geo.cached("lHull", func(): return Geo.build_wound(Geo.loft([
			[-8.0, 1.0, 1.2, 0.1], [-6.6, 1.5, 1.7, 0.1], [-3.0, 1.8, 2.0, 0.15], [1.0, 1.7, 1.8, 0.1],
			[4.6, 1.3, 1.4, -0.05], [7.4, 0.8, 0.9, -0.2], [9.4, 0.3, 0.35, -0.3]], 8))), M.hull))
	var canopy := Models.mesh(Geo.cached("lCan", func(): return Geo.build(Geo.hemi(1.0, 8, 3), Vector3.ZERO)), M.lance, Vector3(2.6, 1.2, 0))
	canopy.scale = Vector3(2.6, 1.1, 1.1)
	body.add_child(canopy)
	# the lance: a thin glowing rod down the spine, past the nose
	var rod := Models.mesh(Models.geo("lRod", func(): return Geo.box(9.0, 0.35, 0.35)), M.lance, Vector3(6.4, 0.9, 0))
	body.add_child(rod)
	var wing := Geo.xf(Geo.prism([[-6.8, 0], [-0.6, 0], [-4.2, 6.4], [-6.4, 6.6]], 0.45), Geo.rot(Vector3.RIGHT, PI / 2))
	body.add_child(Models.mesh(Geo.cached("lWingA", func(): return Geo.build(wing)), M.hull_dark, Vector3(0, -0.4, 1.3)))
	body.add_child(Models.mesh(Geo.cached("lWingB", func(): return Geo.build(Geo.xf(wing, Transform3D(Basis().scaled(Vector3(1, 1, -1)), Vector3.ZERO)))),
			M.hull_dark, Vector3(0, -0.4, -1.3)))
	body.add_child(Models.mesh(Models.geo("lFin", func(): return Geo.prism([[-7.8, 0], [-4.4, 0], [-6.2, 2.0], [-7.6, 2.2]], 0.5)), M.hull_dark, Vector3(0, 1.3, 0)))
	var en := Models.mesh(Models.geo("lEng", func(): return Geo.cyl(1.0, 1.3, 1.2, 8)), M.hull_dark, Vector3(-8.4, 0.1, 0))
	en.rotation.z = PI / 2
	body.add_child(en)
	var core := Models.mesh(Models.geo("lEngC", func(): return Geo.cyl(0.95, 0.95, 0.3, 8)), M.nozzle, Vector3(-9.05, 0.1, 0))
	core.rotation.z = PI / 2
	body.add_child(core)
	var fl := Models.mesh(Models.geo("flame", func(): return Geo.xf(Geo.xf(Geo.cone(1.2, 6, 8), Geo.rot(Vector3.BACK, PI / 2)), Geo.move(-3, 0, 0))), M.engine, Vector3(-9.1, 0.1, 0))
	fl.set_meta("nf", true)
	body.add_child(fl)
	g.set_meta("body", body)
	g.set_meta("flame", fl)
	return g


## The ship's mechanic (null for Lance, whose beam lives in vgame.gd).
static func make_kit(kind: String, game: Node3D) -> ShipKit:
	var k: String = KITS[kind].get("kit", "")
	if k == "":
		return null
	return load("res://scripts/kits/%s.gd" % k).new(game)


static func model(kind: String) -> Node3D:
	match kind:
		"lance":
			return lance()
		"warden":
			return Models.ship()
		"hornet":
			return hornet()
		"weaver":
			return weaver()
		"anvil":
			return anvil()
	return Models.ship()


# ---------- the ship builder ----------

## Builds a ship from a spec, side view (nose along +X, top along +Y, wings along Z), the way
## `lance()` and `Models.ship()` are made, so paints, the banking and the exhaust all work:
## `id` (mesh cache prefix), `hull` (loft sections [x, half height, half depth, centre y], tail
## first), `canopy` [x, y, sx, sy, sz], `wings` (a list of {pts = [[x, span], ...], th, y, z,
## droop, mat}, mirrored to both sides), `fin` (points [[x, y], ...]) and `engines` (a list of
## [tail x, y, z, radius]).
static func craft(o: Dictionary) -> Node3D:
	var M := Models.M
	var id: String = o.id
	var g := Node3D.new()
	var body := Node3D.new()
	g.add_child(body)
	body.add_child(Models.mesh(Geo.cached(id + "Hull", func(): return Geo.build_wound(Geo.loft(o.hull, int(o.get("seg", 8))))), M.hull))
	if o.has("canopy"):
		var c: Array = o.canopy
		var canopy := Models.mesh(Geo.cached("lCan", func(): return Geo.build(Geo.hemi(1.0, 8, 3), Vector3.ZERO)), M.lance, Vector3(c[0], c[1], 0))
		canopy.scale = Vector3(c[2], c[3], c[4])
		body.add_child(canopy)
	var wi := 0
	for w: Dictionary in o.get("wings", []):
		var tris := Geo.xf(Geo.prism(w.pts, float(w.get("th", 0.5))), Geo.rot(Vector3.RIGHT, PI / 2))
		tris = Geo.xf(tris, Geo.rot(Vector3.RIGHT, float(w.get("droop", 0.0))))
		var mat: Material = M[w.get("mat", "hull_dark")]
		var y := float(w.get("y", -0.4))
		var z := float(w.get("z", 1.2))
		var key := "%sWing%d" % [id, wi]
		body.add_child(Models.mesh(Geo.cached(key + "A", func(): return Geo.build(tris)), mat, Vector3(0, y, z)))
		body.add_child(Models.mesh(Geo.cached(key + "B", func(): return Geo.build(Geo.xf(tris, Transform3D(Basis().scaled(Vector3(1, 1, -1)), Vector3.ZERO)))),
				mat, Vector3(0, y, -z)))
		wi += 1
	if o.has("fin"):
		body.add_child(Models.mesh(Models.geo(id + "Fin", func(): return Geo.prism(o.fin, 0.5)), M.hull_dark, Vector3(0, float(o.get("fin_y", 1.3)), 0)))
	# engines: a dark bell, a bright core and a flame each; the flames share one node so the
	# game can flicker them (and the hangar hide them) together
	var flames := Node3D.new()
	flames.set_meta("nf", true)
	var tail := 0.0
	for e: Array in o.engines:
		tail = minf(tail, e[0])
	flames.position = Vector3(tail, 0, 0)
	for e: Array in o.engines:
		var r: float = e[3]
		var en := Models.mesh(Models.geo("%sEng%d" % [id, int(r * 10)], func(): return Geo.cyl(r, r * 1.3, 1.2, 8)), M.hull_dark, Vector3(e[0] + 0.6, e[1], e[2]))
		en.rotation.z = PI / 2
		body.add_child(en)
		var core := Models.mesh(Models.geo("%sEngC%d" % [id, int(r * 10)], func(): return Geo.cyl(r * 0.95, r * 0.95, 0.3, 8)), M.nozzle, Vector3(e[0], e[1], e[2]))
		core.rotation.z = PI / 2
		body.add_child(core)
		var fl := Models.mesh(Models.geo("flame", func(): return Geo.xf(Geo.xf(Geo.cone(1.2, 6, 8), Geo.rot(Vector3.BACK, PI / 2)), Geo.move(-3, 0, 0))), M.engine,
				Vector3(e[0] - tail, e[1], e[2]))
		fl.scale = Vector3(r, r, r)
		fl.set_meta("nf", true)
		flames.add_child(fl)
	body.add_child(flames)
	g.set_meta("body", body)
	g.set_meta("flame", flames)
	return g


## A box on the model (rails, bays, plates), in the given material.
static func _box(body: Node3D, key: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	body.add_child(Models.mesh(Models.geo(key, func(): return Geo.box(size.x, size.y, size.z)), mat, pos))


## Hornet: short and wasp-waisted, small forward-swept wings, an amber missile rail under each.
static func hornet() -> Node3D:
	var M := Models.M
	var g := craft({id = "hor", hull = [[-6.0, 0.7, 0.9, 0.0], [-4.6, 1.5, 1.8, 0.1], [-2.6, 0.9, 1.0, 0.0], [-0.6, 1.6, 1.9, 0.1],
			[2.6, 1.5, 1.7, 0.0], [5.0, 0.9, 1.0, -0.2], [6.6, 0.3, 0.35, -0.3]],
		canopy = [2.4, 1.1, 2.0, 1.1, 1.1],
		wings = [{pts = [[-3.6, 0], [-0.4, 0], [2.4, 5.4], [0.6, 5.6]], th = 0.4, y = -0.2, z = 1.4},
			{pts = [[-6.2, 0], [-4.4, 0], [-5.4, 2.6], [-6.4, 2.7]], th = 0.3, y = 0.2, z = 0.8}],
		engines = [[-6.4, 0.0, 0.0, 0.9]]})
	var body: Node3D = g.get_meta("body")
	for z in [3.6, -3.6]:
		_box(body, "horRail", Vector3(5.0, 0.6, 0.6), Vector3(1.4, -0.9, z), M.pod)
		_box(body, "horTip", Vector3(0.8, 0.5, 0.5), Vector3(4.2, -0.9, z), M.pod_spike)
	for x in [-1.2, 0.6]:
		_box(body, "horStripe", Vector3(0.5, 0.3, 3.4), Vector3(x, 1.5, 0), M.pod)
	return g


## Weaver: a needle of a hull between very long, thin, straight wings with a glowing spool at
## each tip (where the thread comes from).
static func weaver() -> Node3D:
	var M := Models.M
	var g := craft({id = "wea", hull = [[-7.0, 0.5, 0.6, 0.0], [-5.0, 1.0, 1.1, 0.1], [-1.0, 1.2, 1.3, 0.1], [3.0, 1.0, 1.1, 0.0],
			[6.4, 0.5, 0.6, -0.1], [8.6, 0.15, 0.2, -0.2]],
		canopy = [1.6, 0.9, 2.2, 0.9, 0.9],
		wings = [{pts = [[-2.4, 0], [0.8, 0], [-0.2, 9.4], [-1.6, 9.4]], th = 0.3, y = 0.0, z = 0.9},
			{pts = [[-7.0, 0], [-5.4, 0], [-6.0, 3.4], [-7.0, 3.4]], th = 0.25, y = 0.3, z = 0.5}],
		engines = [[-7.4, 0.0, 0.0, 0.7]]})
	var body: Node3D = g.get_meta("body")
	for z in [10.2, -10.2]:
		var sp := Models.mesh(Models.geo("weaSpool", func(): return Geo.octa(1.0)), M.lance, Vector3(-0.9, 0.0, z))
		sp.scale = Vector3(1.6, 0.8, 0.8)
		body.add_child(sp)
	return g


## Anvil: a wide flat flying wing, two engines far apart, a dark bomb bay under the belly and
## an amber bomb showing in it.
static func anvil() -> Node3D:
	var M := Models.M
	var g := craft({id = "anv", hull = [[-6.6, 1.2, 3.0, 0.0], [-4.0, 1.7, 3.6, 0.1], [0.0, 1.8, 3.4, 0.1], [3.4, 1.4, 2.6, 0.0],
			[5.6, 0.9, 1.6, -0.2], [6.8, 0.4, 0.8, -0.3]],
		canopy = [3.2, 1.2, 1.8, 1.0, 1.4],
		wings = [{pts = [[-6.4, 0], [3.6, 0], [-1.6, 7.0], [-6.0, 7.4]], th = 0.9, y = -0.3, z = 2.6, droop = 0.1}],
		fin = [[-6.6, 0], [-3.4, 0], [-5.6, 2.2], [-6.6, 2.4]], fin_y = 1.6,
		engines = [[-7.0, 0.0, 2.6, 1.1], [-7.0, 0.0, -2.6, 1.1]]})
	var body: Node3D = g.get_meta("body")
	_box(body, "anvBay", Vector3(6.0, 0.8, 3.6), Vector3(-0.6, -1.7, 0), M.hull_dark)
	var bomb := Models.mesh(Models.geo("anvBomb", func(): return Geo.octa(1.0)), M.pod, Vector3(-0.6, -2.2, 0))
	bomb.scale = Vector3(2.2, 0.8, 1.1)
	body.add_child(bomb)
	for z in [7.6, -7.6]:
		_box(body, "anvTip", Vector3(3.0, 0.5, 0.5), Vector3(-4.0, -0.4, z), M.pod)
	return g

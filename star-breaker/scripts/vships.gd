class_name VShips
extends RefCounted
## Ship kits for the portrait game (the vertical slice). Each ship has a main weapon that fires
## on its own while the thumb is down, a release (what happens when the thumb lifts) and an
## ultimate (second finger). Lance and Warden are in the slice; the other seven come later.

const KITS := {
	lance = {name = "Lance", sub = "Hold to charge the beam, lift to fire", release = "beam", ult = "starbreak", ult_name = "Starbreak",
		fire_every = 6, shot_speed = 6.5},
	warden = {name = "Warden", sub = "Lift to fling the pod, lift again to call it back", release = "pod", ult = "shatter", ult_name = "Shatter",
		fire_every = 8, shot_speed = 5.5},
}
const ORDER := ["lance", "warden"]


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


static func model(kind: String) -> Node3D:
	return lance() if kind == "lance" else Models.ship()

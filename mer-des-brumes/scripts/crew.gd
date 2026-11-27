class_name Crew
extends RefCounted
## The men on deck: each kind has its own figure (clothes, hat, weapon) and its own moves.
## A sailor is a node (feet at its origin, facing +z) holding a body mesh and a right arm on a
## shoulder pivot; the arm carries the weapon, so raising it aims, brandishes or throws.

const KINDS := ["sabre", "pistolet", "fusil", "grenade", "capitaine"]
## Seen from far away the men would vanish: they are a little bigger than life.
const SIZE := 1.15
const SHOULDER := Vector3(0.2, 0.7, 0)
const FAR := 120.0

static var _meshes := {}


static func _body(kind: String, L: Dictionary) -> ArrayMesh:
	var b := Models.Builder.new()
	var cl: Array = L.crew[kind]
	var main: Color = cl[0]
	var acc: Color = cl[1]
	var skin: Color = L.skin
	var capt := kind == "capitaine"
	# legs and boots
	for sx in [-1, 1]:
		b.prim(Models.box(0.12, 0.34, 0.13), Models.at(sx * 0.075, 0.25, 0), L.pants)
		b.prim(Models.box(0.13, 0.1, 0.17), Models.at(sx * 0.075, 0.05, 0.02), L.boots)
	# the torso (a long coat for the captain, the riflemen and the grenadiers)
	b.prim(Models.cyl(0.15, 0.13, 0.4, 6), Models.at(0, 0.6, 0, Vector3(0, PI / 6, 0)), main)
	if capt or kind == "fusil" or kind == "grenade":
		b.prim(Models.cyl(0.14, 0.19, 0.3, 6), Models.at(0, 0.32, -0.01, Vector3(0, PI / 6, 0)), main)
	b.prim(Models.box(0.3, 0.05, 0.24), Models.at(0, 0.43, 0), acc if kind == "sabre" else L.boots)
	# left arm, hanging, and its hand
	b.prim(Models.box(0.09, 0.32, 0.1), Models.at(-0.2, 0.55, 0, Vector3(0, 0, -0.12)), main)
	b.prim(Models.box(0.08, 0.08, 0.08), Models.at(-0.23, 0.37, 0), skin)
	# head
	b.prim(Models.ball(0.12, 6, 4), Models.at(0, 0.92, 0), skin)
	b.prim(Models.box(0.025, 0.025, 0.025), Models.at(-0.045, 0.94, 0.11), Color8(0x1a, 0x18, 0x18))
	b.prim(Models.box(0.025, 0.025, 0.025), Models.at(0.045, 0.94, 0.11), Color8(0x1a, 0x18, 0x18))
	var hat: String = L.hat
	if capt:
		hat = "tricorn_big"
	elif hat == "":
		hat = {"sabre": "bandana", "pistolet": "tricorn", "fusil": "brim", "grenade": "mitre"}[kind]
	match hat:
		"bandana":
			b.prim(Models.ball(0.13, 6, 3), Models.at(0, 0.97, -0.01, Vector3.ZERO, Vector3(1, 0.6, 1)), acc)
			b.prim(Models.box(0.04, 0.12, 0.04), Models.at(0.03, 0.9, -0.13, Vector3(0.5, 0, 0)), acc)
		"tricorn":
			b.prim(Models.cyl(0.21, 0.21, 0.05, 3), Models.at(0, 1.02, 0, Vector3(0, PI, 0)), acc)
			b.prim(Models.cyl(0.09, 0.11, 0.1, 6), Models.at(0, 1.07, 0), acc)
		"brim":
			b.prim(Models.cyl(0.21, 0.21, 0.03, 8), Models.at(0, 1.01, 0), acc)
			b.prim(Models.cyl(0.1, 0.11, 0.14, 8), Models.at(0, 1.09, 0), acc)
		"mitre":
			b.prim(Models.cyl(0.05, 0.12, 0.32, 4), Models.at(0, 1.13, 0, Vector3(0, PI / 4, 0)), acc)
			b.prim(Models.box(0.12, 0.2, 0.02), Models.at(0, 1.1, 0.07), Color8(0xd8, 0xb0, 0x4a))
		"tricorn_big":
			b.prim(Models.cyl(0.3, 0.3, 0.06, 3), Models.at(0, 1.03, 0, Vector3(0, PI, 0)), acc)
			b.prim(Models.cyl(0.11, 0.13, 0.13, 6), Models.at(0, 1.1, 0), acc)
			b.prim(Models.box(0.04, 0.26, 0.03), Models.at(-0.12, 1.2, -0.03, Vector3(0, 0, 0.5)), Color8(0xf4, 0xf0, 0xe6))
			b.prim(Models.box(0.32, 0.025, 0.025), Models.at(0, 1.06, 0.13), Color8(0xd8, 0xb0, 0x4a))
		"fur":
			b.prim(Models.ball(0.15, 7, 4), Models.at(0, 1.0, -0.01, Vector3.ZERO, Vector3(1, 0.75, 1)), acc)
			b.prim(Models.ball(0.05, 5, 3), Models.at(0, 1.13, 0), main)
		"hood":
			b.prim(Models.cyl(0.0, 0.16, 0.32, 6), Models.at(0, 1.06, -0.03, Vector3(-0.25, 0, 0)), acc)
		"wizard":
			b.prim(Models.cyl(0.2, 0.2, 0.03, 8), Models.at(0, 1.0, 0), acc)
			b.prim(Models.cyl(0.0, 0.12, 0.42, 6), Models.at(0, 1.2, -0.03, Vector3(-0.2, 0, 0)), acc)
	# kind details
	match kind:
		"sabre":
			b.prim(Models.box(0.31, 0.06, 0.25), Models.at(0, 0.5, 0, Vector3(0, 0, 0.2)), acc)
		"pistolet":
			b.prim(Models.box(0.04, 0.16, 0.06), Models.at(-0.12, 0.4, 0.13, Vector3(0, 0, 0.4)), L.pistol)
		"fusil":
			b.prim(Models.cyl(0.03, 0.06, 0.16, 5), Models.at(0.1, 0.5, -0.14, Vector3(0, 0, 1.0)), Color8(0xd8, 0xc8, 0xa0))
		"grenade":
			# a bandolier and a bag of bombs
			b.prim(Models.box(0.05, 0.46, 0.25), Models.at(0, 0.62, 0, Vector3(0, 0, 0.7)), Color8(0xe8, 0xdc, 0xc0))
			b.prim(Models.box(0.14, 0.14, 0.1), Models.at(-0.16, 0.42, -0.08), Color8(0x6a, 0x52, 0x38))
			b.prim(Models.ball(0.06, 5, 3), Models.at(-0.16, 0.5, -0.08), L.bomb)
		"capitaine":
			for i in 3:
				b.prim(Models.box(0.03, 0.03, 0.03), Models.at(0, 0.7 - i * 0.12, 0.15), Color8(0xd8, 0xb0, 0x4a))
			b.prim(Models.box(0.36, 0.06, 0.2), Models.at(0, 0.82, 0), Color8(0xd8, 0xb0, 0x4a))
	return b.commit()


## The right arm and its weapon, hanging from the shoulder (the weapon carries on along the arm).
static func _arm(kind: String, L: Dictionary) -> ArrayMesh:
	var b := Models.Builder.new()
	var cl: Array = L.crew[kind]
	b.prim(Models.box(0.09, 0.32, 0.1), Models.at(0, -0.15, 0), cl[0])
	b.prim(Models.box(0.08, 0.08, 0.08), Models.at(0, -0.33, 0), L.skin)
	match kind:
		"sabre", "capitaine":
			var bc: Color = L.blade
			match L.blade_shape if kind == "sabre" else "steel":
				"shard":
					b.prim(Models.cyl(0.0, 0.07, 0.6, 4), Models.at(0, -0.68, 0, Vector3(PI, 0, 0)), bc)
					b.prim(Models.cyl(0.0, 0.04, 0.3, 4), Models.at(0.05, -0.55, 0.03, Vector3(PI + 0.4, 0, 0.3)), bc.lightened(0.3))
				"thorn":
					b.prim(Models.cyl(0.0, 0.06, 0.55, 5), Models.at(0, -0.65, 0, Vector3(PI, 0, 0)), bc)
					b.prim(Models.ball(0.06, 5, 3), Models.at(0, -0.4, 0.04), Color8(0x6f, 0x9a, 0x44))
				"wand":
					b.prim(Models.cyl(0.015, 0.025, 0.45, 5), Models.at(0, -0.58, 0), L.wood if L.has("wood") else bc)
					b.prim(Models.ball(0.07, 6, 3), Models.at(0, -0.82, 0), bc)
				"coral":
					b.prim(Models.cyl(0.02, 0.04, 0.55, 5), Models.at(0, -0.63, 0), bc)
					b.prim(Models.cyl(0.0, 0.03, 0.22, 4), Models.at(0.06, -0.7, 0, Vector3(0, 0, 0.6)), bc)
					b.prim(Models.cyl(0.0, 0.03, 0.22, 4), Models.at(-0.06, -0.78, 0, Vector3(0, 0, -0.6)), bc)
				_:
					b.prim(Models.box(0.025, 0.55, 0.07), Models.at(0, -0.66, 0.02, Vector3(0.12, 0, 0)), bc)
					b.prim(Models.box(0.14, 0.03, 0.06), Models.at(0, -0.38, 0), Color8(0xd8, 0xb0, 0x4a))
		"pistolet":
			b.prim(Models.box(0.05, 0.24, 0.05), Models.at(0, -0.47, 0.02), L.pistol)
			b.prim(Models.box(0.05, 0.08, 0.1), Models.at(0, -0.36, -0.03), L.musket)
		"fusil":
			b.prim(Models.box(0.05, 0.85, 0.05), Models.at(0, -0.6, 0.03), L.musket)
			b.prim(Models.box(0.035, 0.5, 0.035), Models.at(0, -0.95, 0.03), L.pistol)
			b.prim(Models.box(0.07, 0.2, 0.08), Models.at(0, -0.15, 0.04), L.musket)
		"grenade":
			b.prim(Models.ball(0.1, 6, 4), Models.at(0, -0.42, 0.02), L.bomb)
			b.prim(Models.box(0.02, 0.08, 0.02), Models.at(0, -0.53, 0.02), Color8(0x6a, 0x52, 0x38))
			b.prim(Models.box(0.05, 0.05, 0.05), Models.at(0, -0.58, 0.02), L.spark)
	return b.commit()


static func meshes(kind: String, skin: String) -> Array:
	var key := kind + skin
	if not _meshes.has(key):
		var L := Looks.of(skin)
		_meshes[key] = [_body(kind, L), _arm(kind, L)]
	return _meshes[key]


## One man of `kind` in the ship's `skin`. `fi` is his place in the boarding's fighters list.
static func sailor(kind: String, skin: String, fi: int, ph: float) -> Node3D:
	var m := meshes(kind, skin)
	var n := Node3D.new()
	var body := Models.instance(m[0], null, false)
	body.visibility_range_end = FAR
	n.add_child(body)
	var piv := Node3D.new()
	piv.name = "Arm"
	piv.position = SHOULDER
	var arm := Models.instance(m[1], null, false)
	arm.visibility_range_end = FAR
	piv.add_child(arm)
	n.add_child(piv)
	n.set_meta("kind", kind)
	n.set_meta("fi", fi)
	n.set_meta("ph", ph)
	n.set_meta("walk", kind == "sabre" or kind == "pistolet")
	return n


## Places on deck (in the hull's frame), front to back, clear of the masts.
static func slots(masts: Array, qd: bool) -> Array:
	var out := []
	for z in [2.05, 1.45, 0.85, 0.25, -0.35, -0.95, -1.5]:
		for x in [-0.55, 0.55, 0.0]:
			var clear := true
			for mz in masts:
				if absf(z - mz) < 0.4 and absf(x) < 0.3:
					clear = false
			if x == 0.0 and absf(z) > 1.6:
				clear = false
			if qd and z < -1.45:
				clear = false
			if clear:
				out.append(Vector3(x, Models.deck_y(z), z))
	return out


## The crew on a ship body: every kind gets a place before a second man of a kind does, so
## each kind is seen. `crew` lists kinds in Rules.CREW order (their index is their fighter
## index); the captain stands at the wheel.
static func man_ship(body: Node3D, crew: Array, skin: String, masts: Array, qd: bool, sc: Vector3) -> Array:
	var places := slots(masts, qd)
	var by_kind := {}
	for i in crew.size():
		if not by_kind.has(crew[i]):
			by_kind[crew[i]] = []
		by_kind[crew[i]].append(i)
	var order := []
	var more := true
	var r := 0
	while more and order.size() < places.size():
		more = false
		for k in KINDS:
			if by_kind.has(k) and by_kind[k].size() > r:
				more = true
				if order.size() < places.size():
					order.append(by_kind[k][r])
		r += 1
	var men := []
	var inv := Vector3(1.0 / sc.x, 1.0 / sc.y, 1.0 / sc.z) * SIZE
	# spread the men out: fill alternate places first
	var pick := []
	for i in range(0, places.size(), 2):
		pick.append(i)
	for i in range(1, places.size(), 2):
		pick.append(i)
	for j in order.size():
		var fi: int = order[j]
		var n := sailor(crew[fi], skin, fi, Models.hash3(fi, j, 3.7) * TAU)
		var p: Vector3 = places[pick[j]]
		n.position = p
		n.scale = inv
		n.rotation.y = 0.0 if p.x == 0.0 else signf(p.x) * 0.5
		n.set_meta("home", p)
		n.set_meta("yaw", n.rotation.y)
		body.add_child(n)
		men.append(n)
	var cz := -2.25
	var cap := sailor("capitaine", skin, crew.size(), 1.3)
	cap.position = Vector3(0, Models.deck_y(cz) + (Models.QD_H if qd else 0.0), cz)
	cap.scale = inv
	cap.set_meta("home", cap.position)
	cap.set_meta("yaw", 0.0)
	cap.set_meta("walk", false)
	body.add_child(cap)
	men.append(cap)
	return men


## Moves the men. mode: "sail" (going about their work), "fight" (guns: facing the foe at
## bearing `look`, aiming, throwing), "board" (melee). `fighters` (boarding) lays the fallen down.
static func animate(men: Array, t: float, mode: String, look: float, fighters := [], moving := 0.0) -> void:
	for n: Node3D in men:
		var k: String = n.get_meta("kind")
		var ph: float = n.get_meta("ph")
		var home: Vector3 = n.get_meta("home")
		var yaw0: float = n.get_meta("yaw")
		var arm: Node3D = n.get_child(1)
		var fi: int = n.get_meta("fi")
		var tt := t + ph
		if fi < fighters.size() and fighters[fi].hp <= 0:
			n.position = home + Vector3(0, 0.05, 0)
			n.rotation = Vector3(-PI / 2 * 0.92, yaw0 + ph, 0)
			arm.rotation = Vector3(-0.4, 0, 0)
			continue
		var p := home
		var yaw := yaw0
		var a := 0.0          # the arm's raise (negative = forward / up)
		var lean := 0.0
		var capt := k == "capitaine"
		if mode == "sail":
			if capt:
				a = -1.15 + sin(tt * 0.9) * 0.08
				yaw = sin(tt * 0.3) * 0.15
			elif n.get_meta("walk") and sin(tt * 0.23) > -0.2:
				var dz := sin(tt * 0.55) * 0.32
				p.z += dz
				yaw = 0.0 if cos(tt * 0.55) > 0 else PI
				p.y += absf(sin(tt * 6.0)) * 0.035
				a = sin(tt * 6.0) * 0.35
			else:
				yaw = yaw0 + sin(tt * 0.4) * 0.7
				match k:
					"fusil":
						a = -0.25 + sin(tt * 0.7) * 0.05
					"grenade":
						# tosses his bomb and catches it
						var c := fmod(tt * 0.6, 1.0)
						a = -0.7 - (sin(c * PI) * 0.7 if c < 0.5 else 0.0)
					"pistolet":
						a = -1.3 + sin(tt * 1.3) * 0.2 if sin(tt * 0.31) > 0.4 else sin(tt * 1.1) * 0.15
					_:
						a = sin(tt * 1.2) * 0.25
			lean = sin(t * 1.3 + ph) * 0.03
		else:
			var fierce := 1.0 if mode == "fight" else 1.8
			yaw = look if not capt else (sin(tt * 0.5) * 0.2 if mode == "fight" else look)
			# step to the rail on the foe's side
			if not capt:
				p.x += clampf(sin(look), -1.0, 1.0) * 0.12
			match k:
				"sabre", "capitaine":
					if mode == "board":
						a = -2.9 + (sin(tt * 9.0) * 0.5 + 0.5) * 2.3
						p.y += absf(sin(tt * 4.5)) * 0.12
						p += Vector3(sin(look), 0, cos(look)) * (sin(tt * 2.0) * 0.12)
					elif capt:
						a = -1.15
					else:
						a = -2.7 + sin(tt * 5.0) * 0.35
						p.y += absf(sin(tt * 4.0)) * 0.06
				"pistolet", "fusil":
					var kick := pow(maxf(0.0, sin(tt * (1.6 * fierce))), 10.0)
					a = -PI / 2 + kick * 0.6
					lean = -kick * 0.15
				"grenade":
					var c := fmod(tt * 0.55 * fierce, 1.0)
					a = lerpf(0.9, -2.6, smoothstep(0.55, 0.75, c)) if c > 0.3 else lerpf(-0.3, 0.9, c / 0.3)
		n.position = p
		n.rotation = Vector3(lean, yaw, 0)
		arm.rotation = Vector3(a, 0, 0)


## The crew lined up on the quay, one of each kind, for the port's crew tab.
static func lineup(skin: String) -> Node3D:
	var g := Node3D.new()
	var b := Models.Builder.new()
	for i in 9:
		b.prim(Models.box(0.6, 0.12, 2.6), Models.at(-2.4 + i * 0.6, -0.06, 0), Color8(0x8c, 0x6a, 0x48).darkened(0.06 * (i % 2)))
	b.prim(Models.cyl(0.14, 0.14, 0.8, 6), Models.at(-2.6, 0.2, -1.1), Color8(0x5e, 0x45, 0x32))
	b.prim(Models.cyl(0.14, 0.14, 0.8, 6), Models.at(2.6, 0.2, -1.1), Color8(0x5e, 0x45, 0x32))
	b.prim(Models.cyl(0.2, 0.2, 0.42, 7), Models.at(2.5, 0.21, 0.9), Color8(0x7a, 0x52, 0x34))
	g.add_child(Models.instance(b.commit()))
	var men := []
	for i in KINDS.size():
		var n := sailor(KINDS[i], skin, i, i * 1.7)
		n.position = Vector3(-2.0 + i * 1.0, 0, 0)
		n.scale = Vector3.ONE * 1.6
		n.set_meta("home", n.position)
		n.set_meta("yaw", 0.0)
		n.set_meta("walk", false)
		g.add_child(n)
		men.append(n)
	g.set_meta("men", men)
	return g

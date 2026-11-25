class_name Blasts
extends Node3D
## Explosions, in a polished low poly style: a white-hot flash, a billowing fireball of faceted
## puffs that cools from yellow through orange and red into smoke, glowing embers, tumbling hull
## chunks (the big ones trail smoke), a shockwave ring, a burst of light on the scene around it,
## and water spouts when something hits the sea. Everything is opaque or additive and shrinks
## away instead of fading, and the nodes are pooled, so it stays cheap on phones; past
## `CAP` live pieces, new blasts get sparser.
## Each blast can be carried along (`carry`, a world velocity) so it keeps up with what blew up:
## the scroll frame in the vertical stage, the rail speed in the chase.
## Game.step() calls step(dt), so tests drive it like the rest of the game.

## Live pieces towards which new blasts thin out; past it a blast is just its flash.
const CAP := 260
## Lights at most at once (each light costs a pass on the Compatibility renderer).
const LIGHTS := 3
const GRAVITY := 16.0

const AMBER := Models.AMBER
## The fireball's palette, hottest first: unshaded fire, then lit smoke.
const FIRE: Array[Color] = [Color(1.0, 0.97, 0.86), Color(1.0, 0.86, 0.38), Color(1.0, 0.6, 0.17),
	Color(0.93, 0.32, 0.1)]
const SMOKE: Array[Color] = [Color(0.5, 0.2, 0.12), Color(0.36, 0.33, 0.33), Color(0.55, 0.54, 0.55),
	Color(0.72, 0.72, 0.74)]
const FOAM := Color(0.93, 0.97, 1.0)


class Part:
	## fire, smoke, ember, chunk, flash, ring, spout
	var kind := ""
	var node: MeshInstance3D
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var carry := Vector3.ZERO
	var spin := Vector3.ZERO
	var t := 0.0
	var life := 1.0
	var size := 1.0
	## Non-uniform scale so no two puffs look alike.
	var shape := Vector3.ONE
	var col := Color.WHITE
	var trail := 0.0
	## How far ahead of the others a fire puff runs through the palette.
	var heat := 0.0
	## A ring that stands up to face the camera (in the chase).
	var face := false


class Light:
	var node: OmniLight3D
	var t := 0.0
	var life := 0.0
	var energy := 0.0
	var carry := Vector3.ZERO


var parts: Array[Part] = []
## Civilians getting away from their downed craft (`escape`): {kind, node, t, at, carry, side, life}.
var chutes: Array[Dictionary] = []
## How long a parachute stays in sight (s) before it shrinks away.
const CHUTE_LIFE := 4.0
## How long the others' getaways last (`Civilians`).
const ESCAPE_LIFE := {"caravan": 3.0, "sled": 3.0, "blimp": 2.6, "balloon": 4.0}
## The ground's height at (x, z) (Game.ground_y), for getaways on the ground.
var ground_at := Callable()
var lights: Array[Light] = []
## Blasts waiting to go off: {t, at, size, col, carry}.
var pending: Array[Dictionary] = []
var pool: Array[MeshInstance3D] = []
var rng := RandomNumberGenerator.new()
## The camera, so rings face it in the chase (set by Game).
var cam: Camera3D
## Set by the last big blast (0..1): Game brightens the picture for a moment.
var bright := 0.0

static var _cache := {}


func _ready() -> void:
	for i in LIGHTS:
		var l := Light.new()
		l.node = OmniLight3D.new()
		l.node.visible = false
		l.node.shadow_enabled = false
		l.node.light_color = Color(1.0, 0.66, 0.3)
		l.node.omni_attenuation = 1.6
		l.node.light_specular = 0.3
		add_child(l.node)
		lights.append(l)


## A blast of `size` (about 0.4 for a spark, 1 for a light foe, 3 to 4 for boss parts, 9 for the
## fortress hitting the sea) at `at`. Amber gives fire; any other colour an energy burst in it.
func explode(at: Vector3, size: float, col: Color = AMBER, carry := Vector3.ZERO) -> void:
	var d := detail()
	var fire := col.is_equal_approx(AMBER)
	var root := sqrt(size)
	# the white-hot flash
	var fl := add("flash", at, mesh_ball(), 0.1 + 0.025 * size)
	fl.size = size * (0.42 if fire else 0.36)
	fl.col = Color(1.0, 0.95, 0.8) if fire else col.lightened(0.5)
	fl.carry = carry
	# embers: hot sparks thrown out fast that arc down
	for k in int(clampf(3.0 + size * 2.2, 3, 16) * d):
		var e := add("ember", at, mesh_shard(), rng.randf_range(0.28, 0.55) + 0.03 * size)
		e.vel = rand_dir(0.25) * rng.randf_range(6.0, 12.0) * clampf(root, 0.6, 2.2)
		e.size = rng.randf_range(0.11, 0.2) * clampf(root, 0.7, 1.8)
		e.col = Color(1.0, 0.92, 0.55) if fire else col.lightened(0.25 * (k % 2))
		e.carry = carry
	if not fire:
		if size >= 0.9 and d > 0.0:
			ring(at, size * 0.9, col.lightened(0.3), carry)
		return
	# the fireball: overlapping puffs, a few a beat late so it billows
	for k in maxi(1 if d > 0.0 else 0, int(clampf(2.0 + size * 1.4, 3, 11) * d)):
		var off := rand_dir(0.0) * rng.randf_range(0.0, 0.42) * size
		off.y = absf(off.y) * 0.6
		var p := add("fire", at + off * 0.5, mesh_ball(), rng.randf_range(0.5, 0.8) + 0.05 * size)
		p.vel = off.normalized() * rng.randf_range(1.0, 2.4) * root + Vector3(0, rng.randf_range(0.4, 1.4), 0)
		p.size = rng.randf_range(0.38, 0.62) * pow(size, 0.82)
		p.t = -rng.randf_range(0.0, 0.12) * (1.0 if k > 1 else 0.0) * clampf(root, 1.0, 2.0)
		# the first puffs are the hot heart; the rest cool sooner
		p.heat = 0.0 if k < 2 else rng.randf_range(0.4, 1.6)
		p.carry = carry
	# smoke rising from the fireball once it has cooled
	if size >= 1.2:
		for k in int(clampf(size * 1.1, 1, 7) * d):
			var off := rand_dir(0.0) * rng.randf_range(0.1, 0.4) * size
			off.y = absf(off.y)
			var p := add("smoke", at + off, mesh_ball(), rng.randf_range(1.1, 1.7) + 0.06 * size)
			p.vel = Vector3(off.x, 0, off.z).normalized() * rng.randf_range(0.3, 1.0) + Vector3(0, rng.randf_range(1.2, 2.4), 0)
			p.size = rng.randf_range(0.32, 0.5) * pow(size, 0.8)
			p.t = -rng.randf_range(0.18, 0.32)
			p.carry = carry
	# hull chunks: dark, tumbling, falling; the big ones trail smoke
	if size >= 0.9:
		for k in int(clampf(size * 1.3, 1, 9) * d):
			var c := add("chunk", at, mesh_chunk(), rng.randf_range(0.8, 1.3))
			c.vel = rand_dir(0.35) * rng.randf_range(4.0, 8.0) * clampf(root, 0.8, 2.0) + Vector3(0, 3.0, 0)
			c.size = rng.randf_range(0.16, 0.3) * clampf(root, 0.8, 2.2)
			c.col = Color8(0x4a, 0x46, 0x48) if k % 3 else Color8(0x8a, 0x5a, 0x2c)
			c.trail = 0.0 if size >= 2.4 and k % 2 == 0 else -1.0
			c.carry = carry
	if size >= 1.8 and d > 0.0:
		ring(at, size, Color(1.0, 0.82, 0.5), carry)
		light(at, size, carry)
	if size >= 5.0:
		bright = maxf(bright, clampf(size / 9.0, 0.0, 1.0))


## Water thrown up where something heavy hits the sea: white spouts, spray and a foam ring.
func splash(at: Vector3, size: float, carry := Vector3.ZERO) -> void:
	var d := detail()
	for k in maxi(1, int(clampf(size * 0.9, 3, 9) * d)):
		var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * size * 0.3
		var p := add("spout", at + off, mesh_ball(), rng.randf_range(0.9, 1.4))
		p.vel = Vector3(off.x * 0.6, rng.randf_range(7.0, 12.0) * sqrt(size) * 0.45, off.z * 0.6)
		p.size = rng.randf_range(0.5, 0.8) * pow(size, 0.7)
		p.t = -rng.randf_range(0.0, 0.2)
		p.col = FOAM
		p.carry = carry
	for k in int(clampf(size * 1.6, 4, 14) * d):
		var e := add("ember", at, mesh_shard(), rng.randf_range(0.5, 0.9))
		e.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(1.2, 2.0), rng.randf_range(-1, 1)).normalized() * rng.randf_range(8.0, 14.0)
		e.size = rng.randf_range(0.16, 0.28)
		e.col = FOAM
		e.carry = carry
	ring(at, size * 1.2, FOAM, carry, true)


## One puff of a fire that keeps burning (call it every few frames): it flares, cools and
## leaves a trail of smoke behind whatever is burning.
func burn(at: Vector3, size: float, carry := Vector3.ZERO) -> void:
	if parts.size() >= CAP:
		return
	var p := add("fire", at + rand_dir(0.0) * size * 0.2, mesh_ball(), rng.randf_range(0.9, 1.3))
	p.vel = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(1.0, 2.0), rng.randf_range(-0.5, 0.5))
	p.size = size * rng.randf_range(0.7, 1.0)
	p.heat = rng.randf_range(0.6, 1.4)
	p.carry = carry


## A blast that goes off after `delay` seconds (for chains of blasts across a boss).
func later(delay: float, at: Vector3, size: float, col: Color = AMBER, carry := Vector3.ZERO) -> void:
	pending.append({"t": delay, "at": at, "size": size, "col": col, "carry": carry})


## Blasts going off one after another over `spread` seconds at `points`, then a bigger one at
## their middle if `finale` is above zero.
func chain(points: Array, size: float, spread: float, carry := Vector3.ZERO, finale := 0.0) -> void:
	var mid := Vector3.ZERO
	for i in points.size():
		var at: Vector3 = points[i]
		mid += at
		var dly := spread * float(i) / maxf(1.0, points.size() - 1.0) + rng.randf_range(0.0, 0.05)
		later(dly, at, size * rng.randf_range(0.8, 1.15), AMBER, carry)
	if finale > 0.0 and not points.is_empty():
		mid /= points.size()
		later(spread + 0.15, mid, finale, AMBER, carry)


func ring(at: Vector3, size: float, col: Color, carry: Vector3, flat := false) -> void:
	var r := add("ring", at, mesh_ring(), 0.32 + 0.03 * size)
	r.size = size
	r.col = col
	r.carry = carry
	# flat on the ground or sea from above; in the chase it stands up to face the camera
	r.face = not flat and cam != null and cam.global_basis.z.y < 0.6


func light(at: Vector3, size: float, carry: Vector3) -> void:
	var best: Light = null
	for l in lights:
		if not l.node.visible:
			best = l
			break
		if best == null or l.t / l.life > best.t / best.life:
			best = l
	best.t = 0.0
	best.life = 0.28 + 0.04 * size
	best.energy = clampf(1.4 + size * 0.5, 1.5, 6.0)
	best.carry = carry
	best.node.position = at + Vector3(0, 0.6 + size * 0.2, 0)
	best.node.omni_range = 4.0 + size * 2.6
	best.node.light_energy = best.energy
	best.node.visible = true


func step(dt: float) -> void:
	bright = maxf(0.0, bright - dt * 3.0)
	step_chutes(dt)
	for i in range(pending.size() - 1, -1, -1):
		var b := pending[i]
		b.t -= dt
		b.at += b.carry * dt
		if b.t <= 0.0:
			pending.remove_at(i)
			explode(b.at, b.size, b.col, b.carry)
	for l in lights:
		if not l.node.visible:
			continue
		l.t += dt
		var k := l.t / l.life
		if k >= 1.0:
			l.node.visible = false
			continue
		l.node.position += l.carry * dt
		l.node.light_energy = l.energy * (1.0 - k) * (1.0 - k)
	var i := parts.size() - 1
	while i >= 0:
		var p := parts[i]
		i -= 1
		p.t += dt
		if p.t < 0.0:
			p.pos += p.carry * dt
			continue
		var k := p.t / p.life
		if k >= 1.0:
			free_part(p)
			continue
		p.node.visible = true
		match p.kind:
			"flash":
				var sc := p.size * (0.5 + 0.9 * sqrt(k))
				p.node.scale = Vector3.ONE * sc
				look(p, add_mat(p.col, snappedf(0.85 * (1.0 - k), 0.125)))
			"ring":
				var sc := p.size * (0.4 + 2.0 * (1.0 - (1.0 - k) * (1.0 - k)))
				p.node.scale = Vector3(sc, sc, sc)
				if p.face:
					p.node.basis = Basis.looking_at(cam.global_position - p.pos) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * sc)
				look(p, add_mat(p.col, snappedf((1.0 - k) * 0.55, 0.1)))
			"fire":
				p.vel *= 1.0 - dt * 3.2
				p.vel.y += dt * 1.6
				# swells fast, then cools and shrinks away
				var g := minf(1.0, k / 0.16)
				var sc := p.size * (0.35 + 0.65 * g) * (1.0 - smoothstep(0.55, 1.0, k))
				p.node.scale = p.shape * sc
				var c := int(k * 6.0 + p.heat)
				look(p, fire_mat(c) if c < FIRE.size() else smoke_mat(c - FIRE.size()))
			"smoke":
				p.vel *= 1.0 - dt * 1.2
				var sc := p.size * minf(1.0, 0.4 + k * 2.4) * (1.0 - smoothstep(0.6, 1.0, k))
				p.node.scale = p.shape * sc
				look(p, smoke_mat(1 + int(k * 2.5)))
			"spout":
				p.vel.y -= GRAVITY * 0.9 * dt
				p.vel *= 1.0 - dt * 0.8
				var sc := p.size * minf(1.0, 0.3 + k * 4.0) * (1.0 - smoothstep(0.55, 1.0, k))
				p.node.scale = p.shape * sc * Vector3(1, 1.6, 1)
				look(p, lit_mat(p.col))
			"ember":
				p.vel.y -= GRAVITY * 0.6 * dt
				p.vel *= 1.0 - dt * 1.5
				var sc := p.size * (1.0 - k * k)
				var v := p.vel + p.carry
				if v.length_squared() > 0.01:
					p.node.basis = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT) \
						* Basis.from_scale(Vector3(sc, sc, sc * clampf(v.length() * 0.35, 1.0, 4.0)))
				look(p, add_mat(p.col, 1.0))
			"chunk":
				p.vel.y -= GRAVITY * dt
				p.vel *= 1.0 - dt * 0.6
				p.node.rotation += p.spin * dt
				p.node.scale = Vector3.ONE * p.size * (1.0 - smoothstep(0.7, 1.0, k))
				look(p, lit_mat(p.col))
				if p.trail >= 0.0:
					p.trail -= dt
					if p.trail < 0.0 and parts.size() < CAP:
						p.trail = 0.05
						var s := add("smoke", p.pos, mesh_ball(), rng.randf_range(0.5, 0.8))
						s.size = p.size * rng.randf_range(2.2, 3.2)
						s.vel = Vector3(0, 0.8, 0)
						s.carry = p.carry
		p.pos += (p.vel + p.carry) * dt
		p.node.position = p.pos


## How full the effects are: 1 when quiet, thinning out towards CAP, and nothing but the
## flash past it.
func detail() -> float:
	var n := float(parts.size())
	if n >= CAP:
		return 0.0
	return clampf(1.0 - n / CAP, 0.3, 1.0)


func busy() -> bool:
	return not parts.is_empty() or not pending.is_empty()


## A civilian gets away from its downed craft (Guillaume, 2026-11-25: "a fun little animation... a
## parachute getting out of the plane"), each world its own way (`Civilians`), off to `side` (-1 or
## 1) and carried like the blasts, then shrinks away:
## - gull: the pilot pops up, the canopy snaps open, then sways down and drifts off;
## - caravan: the lead camel rears and bolts off at a gallop, its rider clinging on, kicking up dust;
## - sled: the dogs bolt in a spray of snow, towing the musher on their belly, fishtailing;
## - blimp: punctured, it whizzes round in loops like a let-go party balloon, hissing puffs, shrivelling;
## - balloon: the crew rise out of the basket under a bunch of party balloons and float away.
func escape(kind: String, at: Vector3, carry: Vector3, side: float) -> void:
	var n := Models.instance(Civilians.escape_mesh(kind))
	add_child(n)
	n.position = at
	n.scale = Vector3.ONE * 0.2
	chutes.append({"kind": kind, "node": n, "t": 0.0, "at": at, "carry": carry, "side": side,
		"life": ESCAPE_LIFE.get(kind, CHUTE_LIFE), "puff": 0.0})


## The seaplane pilot's parachute (the coast's `escape`).
func chute(at: Vector3, carry: Vector3, side: float) -> void:
	escape("gull", at, carry, side)


func step_chutes(dt: float) -> void:
	for i in range(chutes.size() - 1, -1, -1):
		var c := chutes[i]
		c.t += dt
		var t: float = c.t
		var life: float = c.life
		if t >= life:
			(c.node as Node3D).queue_free()
			chutes.remove_at(i)
			continue
		c.at += c.carry * dt
		var n := c.node as Node3D
		var side: float = c.side
		var gone := clampf((life - t) / 0.5, 0.0, 1.0)
		var pop := minf(t / 0.15, 1.0)   # springs out of the blast
		match str(c.kind):
			"caravan", "sled":
				var camel: bool = c.kind == "caravan"
				# a beat to take fright (the camel rears), then off at a run, up the land a little
				var go := maxf(0.0, t - (0.3 if camel else 0.1))
				var v := (5.5 if camel else 7.5) * minf(go / 0.4, 1.0)
				var d := Vector3(side, 0, -0.35).normalized()
				c.at += d * v * dt
				var y: float = c.at.y if not ground_at.is_valid() else ground_at.call(c.at.x, c.at.z)
				var k := 13.0 if camel else 18.0
				var hop := absf(sin(go * k)) * (0.22 if camel else 0.08) if go > 0.0 else 0.0
				n.position = Vector3(c.at.x, y + hop, c.at.z)
				var rear := sin(clampf(t / 0.3, 0.0, 1.0) * PI) * 0.45 if camel else 0.0
				var fish := 0.0 if camel else sin(go * 6.0) * 0.3
				n.rotation = Vector3(-rear + sin(go * k) * 0.06, atan2(d.x, d.z) + fish, 0)
				n.scale = Vector3.ONE * lerpf(0.4, 1.0, pop) * gone * Civilians.BIG
				c.puff -= dt
				if go > 0.0 and c.puff <= 0.0 and parts.size() < CAP:
					c.puff = 0.07
					var s := add("smoke", n.position - d * (0.8 if camel else 2.2) * Civilians.BIG + Vector3(0, 0.15, 0), mesh_ball(),
						rng.randf_range(0.5, 0.7))
					s.size = rng.randf_range(0.35, 0.55)
					s.vel = Vector3(rng.randf_range(-0.4, 0.4), 0.9, rng.randf_range(-0.4, 0.4))
			"blimp":
				# loops and zigzags off as the gas rushes out, hissing puffs
				var a := side * (PI / 2) + sin(t * 7.0) * 1.3 + t * 2.4 * side
				var d := Vector3(sin(a), 0, cos(a))
				c.at += d * 7.5 * dt + Vector3(0, -0.5 * dt, 0)
				n.position = c.at
				var shrivel := lerpf(1.0, 0.45, clampf(t / life, 0.0, 1.0))
				n.rotation = Vector3(sin(t * 11.0) * 0.25, atan2(d.x, d.z), sin(t * 9.0) * 0.35)
				n.scale = Vector3(shrivel, shrivel * (0.9 + sin(t * 23.0) * 0.1), 1.0 - (1.0 - shrivel) * 0.5) \
					* lerpf(0.5, 0.9, pop) * gone
				c.puff -= dt
				if c.puff <= 0.0 and parts.size() < CAP:
					c.puff = 0.05
					var s := add("smoke", c.at - d * 1.8 * shrivel, mesh_ball(), rng.randf_range(0.4, 0.6))
					s.size = rng.randf_range(0.3, 0.5)
					s.carry = c.carry
			"balloon":
				# the crew rise out of the basket under their balloons and float off, swaying
				var up := 1.0 - pow(1.0 - minf(t / 0.6, 1.0), 2.0)
				n.position = c.at + Vector3(side * minf(t, 3.0) * 0.8 + sin(t * 1.5) * 0.3, -1.7 + up * 1.4 + t * 0.25, 0)
				n.rotation = Vector3(sin(t * 2.0 + 0.6) * 0.1, t * 0.6, sin(t * 2.0) * 0.18)
				n.scale = Vector3.ONE * lerpf(0.5, 1.6, minf(t / 0.4, 1.0)) * gone
			_:
				var up := 1.0 - pow(1.0 - minf(t / 0.35, 1.0), 2.0)   # pops up out of the plane
				var open := clampf((t - 0.15) / 0.35, 0.0, 1.0)
				var bounce := 1.0 + sin(open * PI) * 0.18          # the canopy snaps open, overshoots
				n.position = c.at + Vector3(side * minf(t, 2.5) * 0.7 + sin(t * 1.7) * 0.25, up * 1.0 - t * 0.9, 0)
				n.scale = Vector3.ONE * lerpf(0.25, 1.0, open) * bounce * gone
				n.rotation = Vector3(sin(t * 2.4 + 0.6) * 0.12, t * 0.4, sin(t * 2.4) * 0.28 * open)


func clear() -> void:
	for c in chutes:
		(c.node as Node3D).queue_free()
	chutes.clear()
	for p in parts:
		p.node.visible = false
		pool.append(p.node)
	parts.clear()
	pending.clear()
	for l in lights:
		l.node.visible = false
	bright = 0.0


func add(kind: String, at: Vector3, m: Mesh, life: float) -> Part:
	var p := Part.new()
	p.kind = kind
	p.pos = at
	p.life = life
	p.node = pool.pop_back() if not pool.is_empty() else null
	if p.node == null:
		p.node = MeshInstance3D.new()
		p.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p.node)
	p.node.mesh = m
	p.node.visible = false
	p.node.position = at
	p.node.basis = Basis.from_euler(Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)))
	p.node.scale = Vector3.ZERO
	p.shape = Vector3(rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.15))
	p.spin = Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9))
	p.face = false
	p.trail = -1.0
	if kind == "ring":
		p.node.basis = Basis()
	parts.append(p)
	return p


func free_part(p: Part) -> void:
	p.node.visible = false
	pool.append(p.node)
	parts.erase(p)


func look(p: Part, m: Material) -> void:
	if p.node.material_override != m:
		p.node.material_override = m


static func rand_dir_static(r: RandomNumberGenerator, up: float) -> Vector3:
	var v := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1) + up, r.randf_range(-1, 1))
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.UP


func rand_dir(up: float) -> Vector3:
	return rand_dir_static(rng, up)


# ---------------------------------------------------------------- meshes and materials

## A faceted ball (an icosahedron): the puffs of fire, smoke and water.
static func mesh_ball() -> Mesh:
	if not _cache.has("ball"):
		var t := (1.0 + sqrt(5.0)) * 0.5
		var v: Array[Vector3] = []
		for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
				[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
			v.append(Vector3(p[0], p[1], p[2]).normalized())
		var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
		_cache["ball"] = faces(v, f)
	return _cache["ball"]


## A hull fragment: a wedge, flat shaded.
static func mesh_chunk() -> Mesh:
	if not _cache.has("chunk"):
		var v: Array[Vector3] = [Vector3(-1, -0.4, -0.7), Vector3(1, -0.4, -0.5), Vector3(0.2, -0.4, 0.9),
			Vector3(-0.6, 0.5, -0.3), Vector3(0.7, 0.4, 0.0)]
		var f := [[0, 2, 1], [0, 1, 3], [1, 4, 3], [1, 2, 4], [2, 0, 3], [2, 3, 4]]
		_cache["chunk"] = faces(v, f)
	return _cache["chunk"]


## An ember: a thin diamond along z, stretched along its flight.
static func mesh_shard() -> Mesh:
	if not _cache.has("shard"):
		var v: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0),
			Vector3(0, 0.4, 0), Vector3(0, -0.4, 0)]
		var f := [[0, 4, 2], [0, 3, 4], [0, 5, 3], [0, 2, 5], [1, 2, 4], [1, 4, 3], [1, 3, 5], [1, 5, 2]]
		_cache["shard"] = faces(v, f)
	return _cache["shard"]


## A thin flat ring of radius 1 in the xz plane (the shockwave).
static func mesh_ring() -> Mesh:
	if not _cache.has("ring"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 28
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var o0 := Vector3(cos(a0), 0, sin(a0))
			var o1 := Vector3(cos(a1), 0, sin(a1))
			var i0 := o0 * 0.88
			var i1 := o1 * 0.88
			for q in [o0, o1, i1, o0, i1, i0]:
				st.set_normal(Vector3.UP)
				st.add_vertex(q)
		_cache["ring"] = st.commit()
	return _cache["ring"]


static func faces(v: Array[Vector3], f: Array) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in f:
		var a := v[tri[0]]
		var b := v[tri[1]]
		var c := v[tri[2]]
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.dot(a + b + c) < 0.0:
			nrm = -nrm
			var s := b
			b = c
			c = s
		for p in [a, c, b]:
			st.set_normal(nrm)
			st.add_vertex(p)
	return st.commit()


## Unshaded fire, hottest at 0.
static func fire_mat(i: int) -> Material:
	var key := "fire%d" % i
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = FIRE[clampi(i, 0, FIRE.size() - 1)]
		_cache[key] = m
	return _cache[key]


## Lit smoke, from the dark red of cooling fire (0) to pale grey.
static func smoke_mat(i: int) -> Material:
	return lit_mat(SMOKE[clampi(i, 0, SMOKE.size() - 1)])


## A plain lit material (smoke, hull chunks, water).
static func lit_mat(c: Color) -> Material:
	var key := "lit%s" % c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		m.metallic_specular = 0.2
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.5
		_cache[key] = m
	return _cache[key]


## Additive glow (flashes, rings, embers) at strength `a`.
static func add_mat(c: Color, a: float) -> Material:
	var key := "add%s%s" % [c.to_html(), a]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c, a)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]

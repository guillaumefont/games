extends ShipKit
## Warden, the guardian (2026-11-21, replacing the pod): holding raises a crystal shield arc in
## front of the ship that eats enemy bullets. It holds STORE of them, then it is full and lets
## bullets through until a lift throws them all back up the screen as pink shards: eat, throw,
## eat again. Shatter loads from bullets eaten and shard hits, and bursts homing shards all
## round the ship.

const RAISE := 8         ## ticks for the shield to come up
const R := 13.0          ## shield radius from the ship
const ARC := 1.25        ## half the arc's angle (radians) either side of straight up
const STORE := 12        ## bullets it holds before it must be emptied by a lift
const EAT_GAIN := 1.0 / 24.0
const HIT_GAIN := 1.0 / 80.0
const THROW_DMG := 2

var stored := 0
var up := 0.0            ## 0 down, 1 fully raised
var arc_m: Node3D
var glow_m: Node3D


func start() -> void:
	arc_m = own(Node3D.new())
	var mesh := Models.geo("wardenArc", func(): return Geo.xf(Geo.octa(1.0), Transform3D(Basis().scaled(Vector3(1.6, 0.6, 0.5)), Vector3.ZERO)))
	for k in 9:
		var a := lerpf(-ARC, ARC, k / 8.0)
		var m := Models.mesh(mesh, Models.M.crystal_m, Vector3(sin(a) * R, cos(a) * R, 0))
		m.rotation.z = -a
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arc_m.add_child(m)
	glow_m = Models.glow("ff5fd2", 26)
	glow_m.position = Vector3(0, R * 0.7, -0.5)
	arc_m.add_child(glow_m)
	arc_m.visible = false


func hold() -> void:
	up = minf(1.0, up + 1.0 / RAISE)


func update() -> void:
	if not g.inp.hold or not g.P.alive or g.G.has("run"):
		up = maxf(0.0, up - 0.25)


func fire() -> void:
	var sp: float = VShips.KITS.warden.shot_speed
	var n := 3 + 2 * mini(g.P.laser, 2)
	for j in n:
		var a := (j - (n - 1) / 2.0) * 0.16
		g.shot(g.P.x, g.P.y + 7, sin(a) * sp, cos(a) * sp, Models.M.pod_shot, 1)


func eats(b: Dictionary) -> bool:
	if up < 1.0 or not g.P.alive or stored >= STORE:
		return false
	var d := Vector2(b.x - g.P.x, b.y - g.P.y)
	var l := d.length()
	if l > R + 2.5 or l < R - 6.0:
		return false
	if absf(atan2(d.x, d.y)) > ARC + 0.1:
		return false
	stored += 1
	gain(EAT_GAIN)
	if stored >= STORE:
		g.audio.play("alarm")
	g.glow_fx("ff5fd2", b.x, b.y, 5, 4.0, 8)
	g.audio.play("tink")
	Diag.once("warden eat")
	return true


func lift() -> void:
	if stored == 0:
		return
	var n := stored
	stored = 0
	g.audio.play("pod")
	for j in n:
		var a := (j - (n - 1) / 2.0) * minf(0.09, 1.4 / maxf(1.0, n - 1.0))
		g.shot(g.P.x + sin(a) * R, g.P.y + cos(a) * R, sin(a) * 6.0, cos(a) * 6.0, Models.M.crystal_m, THROW_DMG)
		g.G.pb.back().kit = true
	Diag.once("warden throw")


## Shard hits from a throw load Shatter too.
func on_hit(_b: Dictionary) -> void:
	gain(HIT_GAIN)


func ult() -> void:
	g.shatter()


func reset() -> void:
	super.reset()
	stored = 0
	up = 0.0


func hint() -> String:
	if g.G.ult_t > 0:
		return "SHATTERING"
	if ready():
		return "FULL: LIFT TO SHATTER"
	if stored >= STORE:
		return "SHIELD FULL: LIFT TO THROW"
	if stored > 0:
		return "%d OF %d HELD: LIFT TO THROW" % [stored, STORE]
	return "HOLD: SHIELD EATS BULLETS"


func sync() -> void:
	# full, the shield flickers: it stops nothing until it is emptied
	arc_m.visible = up > 0.05 and g.P.alive and (stored < STORE or (g.tt >> 2) % 2 == 0)
	if arc_m.visible:
		arc_m.position = Vector3(g.X(g.P.x), g.Y(g.P.y), 3.0 + g.P.get("z", 0.0))
		var s := 0.4 + 0.6 * up
		arc_m.scale = Vector3(s, s, 1)
		glow_m.scale = Vector3(26, 14, 1) * (0.7 + 0.04 * stored)

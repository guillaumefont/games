extends ShipKit
## Forge, the heat ship: its gun speeds up and fans out the longer the thumb stays down, and
## heats as it goes. Lifting vents the heat as a ring of fire round the ship, bigger and harder
## the hotter it was. Let the heat reach the top and the gun jams for JAM ticks instead: the
## skill is lifting late, but not too late. Vent hits load the Meltdown: full fire rate with
## no heat at all.

const HEAT := 0.0085      ## heat gained a tick while holding (full in about 2 s)
const COOL := 0.02
const SLOW_EVERY := 9
const FAST_EVERY := 2
const JAM := 110
const VENT_MIN := 0.25
const VENT_R := 34.0
const VENT_DMG := 16.0
const HIT_GAIN := 1.0 / 14.0
const MELT_T := 330

var heat := 0.0
var jam := 0
var vent_m: MeshInstance3D
var vent_t := 0
var vent_r := 0.0
var glow_m: MeshInstance3D
var melt := 0
var _n := 0


func start() -> void:
	vent_m = own(ring_node("ff8a3d", 0.95)) as MeshInstance3D
	vent_m.visible = false
	glow_m = own(Models.glow("ff6a2a", 10.0)) as MeshInstance3D
	glow_m.visible = false


func level() -> float:
	return 1.0 if melt > 0 else heat


func fire_every() -> int:
	return int(round(lerpf(SLOW_EVERY, FAST_EVERY, level())))


func fire() -> void:
	if jam > 0:
		return
	var sp: float = VShips.KITS.forge.shot_speed
	_n += 1
	# hotter: the stream wanders wider
	var a := sin(_n * 1.7) * 0.22 * level()
	g.shot(g.P.x + sin(_n * 2.3) * 2.0, g.P.y + 8, sin(a) * sp, cos(a) * sp, Models.M.pod_shot, 1, "ff8a3d")


func hold() -> void:
	if jam > 0 or melt > 0:
		return
	heat += HEAT
	if heat >= 1.0:
		heat = 0.0
		jam = JAM
		g.audio.play("alarm")
		g.shake = maxf(g.shake, 4.0)
		Diag.once("forge jam")


func lift() -> void:
	if jam > 0 or heat < VENT_MIN:
		return
	var r := VENT_R * heat
	var res := blast(g.P.x, g.P.y + 6.0, r, VENT_DMG * heat * heat)
	wipe(g.P.x, g.P.y + 6.0, r)
	gain(res[0] * HIT_GAIN * heat)
	vent_r = r
	vent_t = 12
	heat = 0.0
	g.audio.play("beam", 2)
	g.shake = maxf(g.shake, 2.0 + 4.0 * r / VENT_R)
	Diag.once("forge vent")


func ult() -> void:
	melt = MELT_T
	g.G.ult_t = MELT_T
	jam = 0
	heat = 0.0
	g.audio.play("ready", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if vent_t > 0:
		vent_t -= 1
	if jam > 0:
		jam -= 1
	if melt > 0:
		melt -= 1
	if not holding():
		heat = maxf(0.0, heat - COOL)


func reset() -> void:
	super.reset()
	heat = 0.0
	jam = 0
	melt = 0


func hint() -> String:
	if melt > 0:
		return "MELTDOWN: NO HEAT"
	if jam > 0:
		return "JAMMED: TOO HOT"
	if ready():
		return "FULL: LIFT FOR THE MELTDOWN"
	if heat > 0.8:
		return "HEAT %d%%: LIFT NOW TO VENT" % int(heat * 100.0)
	return "HEAT %d%%  ·  LIFT TO VENT IT" % int(heat * 100.0)


func sync() -> void:
	var h := level()
	glow_m.visible = g.P.alive and (h > 0.1 or jam > 0) and not g.G.has("run")
	if glow_m.visible:
		glow_m.position = Vector3(g.X(g.P.x), g.Y(g.P.y + 2.0), 3.0)
		var s := 8.0 + 20.0 * h
		if jam > 0:
			s = 10.0 + 3.0 * sin(g.tt * 0.8)
		elif h > 0.8:
			s *= 1.0 + 0.2 * sin(g.tt * 0.9)
		glow_m.scale = Vector3(s, s, 1)
	vent_m.visible = vent_t > 0
	if vent_t > 0:
		vent_m.position = Vector3(g.X(g.P.x), g.Y(g.P.y + 6.0), 3.0)
		vent_m.scale = Vector3.ONE * vent_r * (1.0 - vent_t / 16.0)

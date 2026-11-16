class_name Sim
extends RefCounted
## The whole Perigee game rules, ported one to one from the web prototype (web/index.html).
##
## Deterministic: it only moves forward in fixed steps of DT, and every random choice that
## changes the game comes from one seeded RandomNumberGenerator. The same seed and the same
## inputs at the same steps always give the same run (tests/sim_test.gd checks it), which the
## daily seeded run and replays will need. No nodes, no drawing, no sound: the view
## (scripts/main.gd) reads the state and drains `events` for effects.

const DT := 1.0 / 120.0
const START_RING := 110.0
const CAPTURE_LOCK := 0.15 ## a release this soon after a capture does not fling
const MAX_FLIGHT := 4.5 ## seconds in flight before you are lost
const RESTART_LOCK := 0.45 ## seconds after a death before a tap restarts
const TRAIL := 44 ## trail points (one per step, so about 0.37 s)


class Planet:
	var k := 0 ## running moon number in this run (0 = the first moon)
	var ox := 0.0 ## centre x without drift
	var x := 0.0
	var y := 0.0
	var pr := 20.0 ## body radius
	var ring := 100.0 ## capture ring radius
	var amp := 0.0 ## side-to-side drift amplitude (0 = still)
	var freq := 0.7
	var ph := 0.0
	var col := 0 ## palette index
	var visited := false
	var speed := 185.0 ## orbit speed around this moon
	var spin := 0.0
	var flash := 0.0


class Spark:
	var x := 0.0
	var y := 0.0
	var got := false


class Player:
	var x := 0.0
	var y := 0.0
	var px := 0.0 ## position at the previous step (for interpolated drawing)
	var py := 0.0
	var vx := 0.0
	var vy := 0.0
	var planet: Planet = null ## the moon being orbited, or null in flight
	var last: Planet = null ## the moon just left (ignored until we are clear of its ring)
	var ang := PI * 0.5
	var r := 54.0
	var r_target := 54.0
	var dir := 1
	var speed := 185.0
	var vr := 0.0 ## radial speed on the orbit
	var vt := 185.0 ## tangential speed on the orbit
	var fly_t := 0.0
	var cap_t := -9.0
	var trail: Array[Vector2] = []


var rng := RandomNumberGenerator.new()
var seed_value := 0
## The seed the next run uses when a tap restarts after a game over. The owner picks it.
var next_seed := 0

## Size of the visible play area in world units (the prototype's W and H). Leaving the
## screen kills, so this is part of the rules: keep it fixed for replays.
var W := 400.0
var H := 700.0

var state := "start" ## start, play or over
var steps := 0 ## steps since this run began
var t := 0.0
var score := 0
var hops := 0 ## moons reached in this run
var sparks_got := 0
var moons_made := 0 ## moons generated so far: the difficulty index (see make_planet)
var holding := false
var swallow := false ## the press that started a run must not also fling on release
var death_t := 0.0
var death_why := ""
var planets: Array[Planet] = []
var sparks: Array[Spark] = []
var player := Player.new()
var cam_x := 0.0
var cam_y := 0.0
var cam_px := 0.0 ## camera at the previous step
var cam_py := 0.0
var cam_w := 1.0
## What happened since the view last looked: {type, x, y, ...}. The view clears it.
var events: Array[Dictionary] = []


func _init(seed_in := 0, w := 400.0, h := 700.0) -> void:
	W = w
	H = h
	new_run(seed_in)
	state = "start"


# ---------- difficulty ----------

## The difficulty curve for moon number k: everything eases in over about 50 moons.
## Same numbers as the prototype's diff(k) (the drift amplitude, which is random, is rolled
## in make_planet so this stays a pure function).
static func curve(k: int) -> Dictionary:
	var s := clampf(k / 50.0, 0.0, 1.0)
	var e := s * s * (3.0 - 2.0 * s) * 0.6 + s * 0.4 # gentle start
	return {
		"ring": lerpf(104.0, 66.0, e),
		"gap": lerpf(160.0, 265.0, e),
		"speed": lerpf(185.0, 255.0, e),
	}


## Gravity assist strength after `hops` moons: strong early, fades to 0.3 by moon 22.
static func assist(hops_in: int) -> float:
	return lerpf(1.0, 0.3, clampf(hops_in / 22.0, 0.0, 1.0))


# ---------- world ----------

## Makes the next moon. Its difficulty comes from `moons_made`, a running counter.
## (The prototype used the length of the moon list, which shrinks as far moons are culled,
## so the index repeated and the difficulty stopped ramping after about 12 moons.)
func make_planet(prev: Planet) -> Planet:
	var k := moons_made
	moons_made += 1
	var d := curve(k)
	var p := Planet.new()
	p.k = k
	if prev != null:
		var gap: float = d.gap
		var a := rng.randf_range(-1.05, 1.05)
		p.ox = prev.ox + sin(a) * gap
		p.y = prev.y - cos(a) * gap
		if absf(p.ox) > 130.0:
			a = -a
			p.ox = prev.ox + sin(a) * gap
		p.ox = clampf(p.ox, -135.0, 135.0)
	p.x = p.ox
	p.pr = 24.0 if k == 0 else rng.randf_range(15.0, 25.0)
	p.ring = START_RING if k == 0 else float(d.ring)
	if k >= 12 and rng.randf() < clampf((k - 12) / 25.0, 0.35, 0.8):
		p.amp = minf(70.0, (k - 10) * 2.4)
	p.freq = rng.randf_range(0.55, 0.9)
	p.ph = rng.randf() * TAU
	p.col = k % 4
	p.speed = d.speed
	p.spin = rng.randf() * TAU
	if prev != null:
		# a spark near the midpoint, slightly off the straight line
		var mx := (prev.ox + p.ox) / 2.0
		var my := (prev.y + p.y) / 2.0
		var dx := p.ox - prev.ox
		var dy := p.y - prev.y
		var l := Vector2(dx, dy).length()
		var off := rng.randf_range(-26.0, 26.0)
		var s := Spark.new()
		s.x = mx - dy / l * off
		s.y = my + dx / l * off
		sparks.append(s)
	return p


func ensure_planets() -> void:
	while planets.is_empty() or planets[-1].y > cam_y - H * 1.2:
		planets.append(make_planet(null if planets.is_empty() else planets[-1]))
	# cull far below
	while planets.size() > 3 and planets[0].y > cam_y + H * 1.5 \
			and planets[0] != player.planet and planets[0] != player.last:
		planets.pop_front()
	while not sparks.is_empty() and sparks[0].y > cam_y + H * 1.5:
		sparks.pop_front()


## Starts a fresh run from `seed_in`, in the play state (a first launch sits in "start").
func new_run(seed_in: int) -> void:
	seed_value = seed_in
	next_seed = seed_in + 1
	rng.seed = seed_in
	planets.clear()
	sparks.clear()
	events.clear()
	steps = 0
	t = 0.0
	hops = 0
	score = 0
	sparks_got = 0
	moons_made = 0
	holding = false
	swallow = false
	cam_x = 0.0
	cam_w = 1.0
	var p0 := make_planet(null)
	p0.visited = true
	planets.append(p0)
	player = Player.new()
	player.planet = p0
	player.r = p0.pr + 30.0
	player.r_target = player.r
	player.speed = p0.speed
	player.vt = p0.speed
	player.x = p0.x + cos(player.ang) * player.r
	player.y = p0.y + sin(player.ang) * player.r
	player.px = player.x
	player.py = player.y
	cam_y = -H * 0.18
	cam_px = cam_x
	cam_py = cam_y
	ensure_planets()
	state = "play"


# ---------- input ----------

## The one button goes down (touch, click, Space or Enter).
func press() -> void:
	if state == "start":
		state = "play"
		holding = false
		swallow = true
		events.append({"type": "start"})
		return
	if state == "over":
		if t - death_t > RESTART_LOCK:
			new_run(next_seed)
			swallow = true
			events.append({"type": "start"})
		return
	holding = true


## The one button comes up.
func release() -> void:
	if swallow:
		swallow = false
		holding = false
		return
	holding = false
	if state != "play":
		return
	if player.planet != null and t - player.cap_t > CAPTURE_LOCK:
		launch()


## The press was cancelled (the app lost focus): let go without flinging.
func cancel() -> void:
	holding = false


func launch() -> void:
	var p := player
	# leave with the exact velocity we had on the orbit (radial + tangential), so there is no kink
	var v := orbit_velocity()
	var m := v.length()
	if m == 0.0:
		m = 1.0
	p.vx = v.x / m * p.speed
	p.vy = v.y / m * p.speed
	p.last = p.planet
	p.planet = null
	p.fly_t = 0.0
	events.append({"type": "launch", "x": p.x, "y": p.y})


## The ship's velocity while orbiting (radial plus tangential parts).
func orbit_velocity() -> Vector2:
	var p := player
	var c := cos(p.ang)
	var s := sin(p.ang)
	return Vector2(p.vr * c - s * p.dir * p.vt, p.vr * s + c * p.dir * p.vt)


func capture(pl: Planet) -> void:
	var p := player
	var dx := p.x - pl.x
	var dy := p.y - pl.y
	var d := Vector2(dx, dy).length()
	var cross := dx * p.vy - dy * p.vx
	p.dir = 1 if cross >= 0.0 else -1
	p.ang = atan2(dy, dx)
	p.r = d
	p.r_target = clampf(d, pl.pr + 16.0, pl.ring) # keep the altitude we arrived at
	# split the incoming velocity into radial and tangential parts; the orbit starts from them
	var ux := dx / (d if d != 0.0 else 1.0)
	var uy := dy / (d if d != 0.0 else 1.0)
	p.vr = p.vx * ux + p.vy * uy
	p.vt = absf(-uy * p.vx + ux * p.vy)
	p.planet = pl
	p.cap_t = t
	p.speed = pl.speed
	var first := not pl.visited
	if first:
		pl.visited = true
		hops += 1
		score += 1
	pl.flash = 1.0
	events.append({"type": "capture", "x": p.x, "y": p.y, "col": pl.col, "first": first, "hops": hops})


func die(why: String) -> void:
	if state != "play":
		return
	state = "over"
	death_t = t
	death_why = why
	holding = false
	events.append({"type": "die", "x": player.x, "y": player.y, "why": why})


# ---------- step ----------

## Moves the world one fixed step of DT.
func step() -> void:
	var dt := DT
	steps += 1
	t += dt
	var p := player
	p.px = p.x
	p.py = p.y
	cam_px = cam_x
	cam_py = cam_y
	for pl in planets:
		pl.x = planet_x(pl, t)
		pl.spin += dt * 0.3
		if pl.flash > 0.0:
			pl.flash = maxf(0.0, pl.flash - dt * 2.0)

	if state == "play" or state == "start":
		if p.planet != null:
			var pl := p.planet
			# radius: critically damped spring that starts from the incoming radial speed
			# (a smooth spiral in)
			var w0 := 5.0
			var sub := 2
			var h := dt / sub
			for i in sub:
				var acc := -w0 * w0 * (p.r - p.r_target) - 2.0 * w0 * p.vr
				p.vr += acc * h
				p.r += p.vr * h
				if p.r < pl.pr + 10.0:
					p.r = pl.pr + 10.0
					if p.vr < 0.0:
						p.vr = 0.0
			# tangential speed eases toward this moon's orbit speed
			var goal := p.speed * (0.8 if state == "start" else 1.0)
			p.vt = lerpf(p.vt, goal, 1.0 - exp(-dt * 3.0))
			p.ang += p.dir * p.vt / p.r * dt
			p.x = pl.x + cos(p.ang) * p.r
			p.y = pl.y + sin(p.ang) * p.r
		elif state == "play":
			_fly(dt)
		p.trail.append(Vector2(p.x, p.y))
		if p.trail.size() > TRAIL:
			p.trail.pop_front()

	# camera: blend the focus between "follow the ship" and "frame the moon" instead of
	# switching targets
	cam_w = lerpf(cam_w, 1.0 if p.planet != null else 0.0, 1.0 - exp(-dt * (2.2 if p.planet != null else 3.0)))
	var anchor: Planet = p.planet if p.planet != null else p.last
	var ship_y := p.y - H * 0.05
	var ty := lerpf(ship_y, anchor.y - H * 0.18, cam_w) if anchor != null else ship_y
	if state != "over":
		cam_y = lerpf(cam_y, ty, 1.0 - exp(-dt * 2.6))
		cam_x = lerpf(cam_x, 0.0, 1.0 - exp(-dt * 2.0))
	ensure_planets()


func _fly(dt: float) -> void:
	var p := player
	p.fly_t += dt
	# gentle gravity assist toward moons ahead: bends the path, keeps the speed
	var a0 := assist(hops)
	for pl in planets:
		if pl == p.last:
			continue
		var dx := pl.x - p.x
		var dy := pl.y - p.y
		var d := Vector2(dx, dy).length()
		var big_r := pl.ring * 1.7
		if d < big_r and d > 1.0:
			var a := a0 * 420.0 * (1.0 - d / big_r)
			p.vx += dx / d * a * dt
			p.vy += dy / d * a * dt
	var sp := Vector2(p.vx, p.vy).length()
	p.vx = p.vx / sp * p.speed
	p.vy = p.vy / sp * p.speed
	p.x += p.vx * dt
	p.y += p.vy * dt
	# capture / collision
	for pl in planets:
		var d := Vector2(p.x - pl.x, p.y - pl.y).length()
		if pl == p.last:
			if d > pl.ring + 6.0:
				p.last = null
			else:
				continue
		if d < pl.pr + 3.0:
			die("Crashed into a moon")
			return
		if holding and d < pl.ring:
			capture(pl)
			break
	# sparks
	for s in sparks:
		if not s.got and Vector2(p.x - s.x, p.y - s.y).length() < 20.0:
			s.got = true
			score += 1
			sparks_got += 1
			events.append({"type": "spark", "x": s.x, "y": s.y})
	# lost
	var sx := p.x - cam_x
	var sy := p.y - cam_y
	if absf(sx) > W / 2.0 + 50.0 or absf(sy) > H / 2.0 + 50.0 or p.fly_t > MAX_FLIGHT:
		die("Drifted off into the dark")


static func planet_x(pl: Planet, time: float) -> float:
	return pl.ox + (pl.amp * sin(time * pl.freq + pl.ph) if pl.amp != 0.0 else 0.0)


## The path a fling would take right now (with the assist), for the first hops' guide dots.
## Ends with a point marked hit=true when it crosses an unvisited moon's ring.
func predict() -> Array[Dictionary]:
	var p := player
	var pts: Array[Dictionary] = []
	if p.planet == null:
		return pts
	var x := p.x
	var y := p.y
	var v := orbit_velocity()
	var vx := v.x
	var vy := v.y
	var a0 := assist(hops)
	var dt := 1.0 / 30.0
	for i in 40:
		for pl in planets:
			if pl == p.planet:
				continue
			var dx := pl.x - x
			var dy := pl.y - y
			var d := Vector2(dx, dy).length()
			var big_r := pl.ring * 1.7
			if d < big_r and d > 1.0:
				var a := a0 * 420.0 * (1.0 - d / big_r)
				vx += dx / d * a * dt
				vy += dy / d * a * dt
			if d < pl.ring and not pl.visited:
				pts.append({"x": x, "y": y, "hit": true})
				return pts
		var sp := Vector2(vx, vy).length()
		vx = vx / sp * p.speed
		vy = vy / sp * p.speed
		x += vx * dt
		y += vy * dt
		if i % 2 == 0:
			pts.append({"x": x, "y": y, "hit": false})
	return pts


## A short fingerprint of the run so far, for the replay test.
func fingerprint() -> String:
	return "%s|%d|%d|%d|%d|%.3f|%.3f" % [state, steps, score, hops, moons_made, player.x, player.y]

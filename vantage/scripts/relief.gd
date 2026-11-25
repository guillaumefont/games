class_name Relief
extends RefCounted
## The lie of the land beyond the noise (Guillaume, 2026-11-24: "the ground is mostly flat and
## uneventful"). The course is cut into stretches of `SEG` m; each world takes its three set pieces
## in turn, then a gentler `stream` stretch (a shallow valley with a stream, or lava, winding down
## it) where the villages and landmarks have room:
## - `gorge` / `canyon`: a winding canyon along the course, terraced walls, a river (water, or lava
##   in the cinders) on its floor, ending in a horseshoe head with a waterfall (or a lava fall); the desert's canyon is a dry wadi.
## - `rift`: a chasm across the course, waterfalls pouring down its far wall.
## - `cliffs` / `shelf`: the sea (or lava) drops far below the land, so every shore is a cliff.
## - `mesas`: the desert floor sinks and leaves flat-topped buttes standing.
## - `crater`: a meteor crater in the dunes, a sinkhole lake on the ice, an erupting caldera in the
##   cinders.
## The land can't rise much (props must stay under the ship), so the drama goes down: canyon
## floors, lowered seas and craters reach `DEEP` below the plain. Cliff faces get strata in the
## ground shader (`Models.ground_mat`). The moving parts (waterfalls, flowing water and lava,
## eruptions, avalanches, geysers, spray) are built per chunk into one mesh, animated in shaders:
## no particles, no per-frame script. The city keeps its flat ground (its roads are laid on it).

const SEG := 150.0
## Where stretch 0 starts (the hangar looks at the land just past z = 0).
const START := 30.0
const DEEP := 9.0
const FEATURES := {
	"coast": ["gorge", "cliffs", "rift"],
	"dunes": ["canyon", "mesas", "crater"],
	"ice": ["shelf", "gorge", "crater"],
	"volcano": ["crater", "canyon", "cliffs"],
}
## The level being flown: each level takes the set pieces in its own order.
static var level := 0
static var _wob: FastNoiseLite
## The moving parts and liquid surfaces of the chunk being built (see `fx_mesh`).
static var fx: Array = []
static var liquid := PackedVector3Array()
static var liquid_flow := PackedVector2Array()


static func wob(x: float, z: float) -> float:
	if _wob == null:
		_wob = FastNoiseLite.new()
		_wob.seed = 77
		_wob.frequency = 0.09
		_wob.fractal_octaves = 2
	return _wob.get_noise_2d(x, z)


static func stretch_of(z: float) -> int:
	return floori((START - z) / SEG)


## The set piece of stretch n ("open" for none): the world's three in turn, then a `stream`,
## each level in its own order (`course`).
static func kind_of(n: int) -> String:
	if not FEATURES.has(Models.theme) or n < 0:
		return "open"
	var c := course()
	return c[n % c.size()]


static var _courses := {}


## The order of the set pieces for the world and level (cached): no two alike in a row, even
## where the hangar's stretches (always level 0's) meet the level's own.
static func course() -> Array:
	var key := "%s%d" % [Models.theme, level]
	if _courses.has(key):
		return _courses[key]
	var list: Array = FEATURES[Models.theme]
	var out := []
	for n in 64:
		var lv := level if n >= LEVEL_FROM else 0
		var cyc: Array = [list[lv % 3], list[(lv + 1) % 3], list[(lv + 2) % 3], "stream"]
		var k: String = cyc[n % 4]
		if not out.is_empty() and k == out[-1]:
			for alt: String in list + ["stream"]:
				if alt != out[-1] and alt != cyc[(n + 1) % 4]:
					k = alt
					break
		out.append(k)
	_courses[key] = out
	return out


## The level counts only past the land the hangar shows, so picking a level never rebuilds it.
const LEVEL_FROM := 2


static func lv_of(n: int) -> int:
	return level if n >= LEVEL_FROM else 0


## Distance into stretch n from its near end (0) to its far end (SEG).
static func local(z: float, n: int) -> float:
	return START - z - n * SEG


## The plain's height for a noise value (as it always was: a flat sea, low land).
static func base_y(h: float) -> float:
	return -0.4 if h < 0.0 else minf(h, 0.8) * 1.6


## A ramp of `n` flat ledges joined by steep steps, 0 to 1.
static func terrace(u: float, n: int) -> float:
	var v := clampf(u, 0.0, 1.0) * n
	var k := floorf(v)
	if k >= n:
		return 1.0
	return (k + smoothstep(0.45, 0.85, v - k)) / n


static func ease_in_out(zl: float, ramp: float) -> float:
	return smoothstep(0.0, ramp, zl) * smoothstep(SEG, SEG - ramp, zl)


static func h1(n: int, k: float) -> float:
	return Models.hash2(n * 3.17 + k, lv_of(n) * 1.91 + k * 0.37)


## The canyon's centre line (x) at z in stretch n: it winds within the screen.
static func canyon_x(z: float, n: int) -> float:
	return 4.5 * sin(z * 0.021 + h1(n, 1.0) * TAU) + 2.2 * sin(z * 0.057 + h1(n, 2.0) * TAU)


## Where the canyon's head is (distance into the stretch) and the far wall's lip.
const HEAD := SEG - 30.0


static func canyon_dims() -> Vector3:
	# top half width, floor half width, depth
	match Models.theme:
		"ice":
			return Vector3(7.0, 1.6, DEEP + 1.0)
		"volcano":
			return Vector3(8.0, 2.4, DEEP - 1.0)
	return Vector3(8.5, 2.3, DEEP)


static func rift_z(x: float, n: int) -> float:
	return START - n * SEG - SEG * 0.55 + 4.0 * sin(x * 0.07 + h1(n, 3.0) * TAU)


static func crater_c(n: int) -> Vector2:
	return Vector2((h1(n, 4.0) - 0.5) * 8.0, START - n * SEG - SEG * 0.5)


## Each world's town (Towns) stands on top of one of its set pieces (Guillaume, 2026-11-24: "on top of
## the existing evolutions, like cliffs in glass coast"): a headland above the sea cliffs, a great
## mesa above the sunken desert, an ice shelf above the cold sea, a basalt plateau above the lava.
const TOWN_HOST := {"coast": "cliffs", "dunes": "mesas", "ice": "shelf", "volcano": "cliffs"}


static func has_town(n: int) -> bool:
	return n >= 0 and kind_of(n) == TOWN_HOST.get(Models.theme, "")


## True inside a town's wall and just round it, where the land's own props keep out.
static func in_town(x: float, z: float) -> bool:
	var n := stretch_of(z)
	if not has_town(n):
		return false
	var c := town_c(n)
	return maxf(absf(x - c.x), absf(z - c.y)) < Towns.WALL + 6.0


## Where stretch n's town stands (its square's centre).
static func town_c(n: int) -> Vector2:
	return Vector2((h1(n, 20.0) - 0.5) * 4.0, START - n * SEG - SEG * 0.52)


const CRATER_R := 15.0
const CRATER_FLOOR := 5.0


## The ground at (x, z) for the noise value h: Vector4(y, h for colours and props, liquid, flow).
## liquid: 0 dry, 1 water, 2 lava. flow: 0 still, 1 along +z, 2 along +x.
static func at(x: float, z: float, h: float) -> Vector4:
	var v := shape(x, z, h)
	var n := stretch_of(z)
	if not has_town(n):
		return v
	# the town's plateau: level, its edge a cliff down to the set piece round it, and a causeway
	# carrying the avenue down to the land where it leaves the gate
	var c := town_c(n)
	var o := Vector2(x - c.x, z - c.y)
	var d := maxf(absf(o.x), absf(o.y)) * 0.8 + o.length() * 0.2 + wob(x, z) * 0.6
	var w := smoothstep(Towns.FLAT + 2.5, Towns.FLAT, d)
	if absf(o.x) < Towns.AVENUE + 1.2 + wob(x, z) * 0.3 and o.y > 0.0:
		w = maxf(w, smoothstep(Towns.AVENUE_TO + 8.0, Towns.AVENUE_TO, o.y))
	w *= ease_in_out(local(z, n), 20.0)
	if w <= 0.0:
		return v
	var hc: float = Towns.GROUND_H[Models.theme]
	return Vector4(lerpf(v.x, Towns.GROUND_Y, w), lerpf(v.y, hc, w) if w < 0.99 else hc, v.z if w < 0.5 else 0.0, v.w if w < 0.5 else 0.0)


## The set piece's own shape at (x, z), before any town on it: the stretch's set piece, with the
## crags carved into Glass Coast's rocky heights wherever the land is still at its plain.
static func shape(x: float, z: float, h: float) -> Vector4:
	var v := piece(x, z, h)
	if Models.theme != "coast" or h < CRAG_FROM or v.z > 0.0:
		return v
	var w := 1.0 - smoothstep(0.05, 0.6, absf(v.x - base_y(h)))
	if w <= 0.0:
		return v
	var c := crag(x, z, h)
	var wet := 1.0 if c.y > 0.0 and w > 0.95 else 0.0
	return Vector4(v.x + c.x * w, v.y, wet, 0.0)


## The plain the set pieces start from, crags and all: what the land is at a stretch's ends.
static func plain(x: float, z: float, h: float) -> float:
	if Models.theme != "coast" or h < CRAG_FROM:
		return base_y(h)
	return base_y(h) + crag(x, z, h).x


# ---------------------------------------------------------------- Glass Coast's crags
## Guillaume, 2026-11-24: "in the glass coast there are rocky areas that are still bland". Where
## the land turns to bare rock it breaks into crags: blocks of rock (cells of a jittered grid)
## standing at different heights with ledged faces, deep gullies along the joints between
## them, and now and then a block hollowed into a tarn. All of it cut down into the land, never
## up towards the ship.
const CRAG_FROM := 0.47
const CRAG_CELL := 11.0
const CRAG_GULLY := 3.4
const TARN_Y := -1.1


## (how far the crags lower the ground there, 1 in a tarn's water else 0)
static func crag(x: float, z: float, h: float) -> Vector2:
	var k := smoothstep(CRAG_FROM, CRAG_FROM + 0.09, h)
	if k <= 0.0:
		return Vector2.ZERO
	var g := CRAG_CELL
	var q := Vector2(x, z) / g
	var cx := floori(q.x)
	var cz := floori(q.y)
	var f1 := INF
	var f2 := INF
	var own := Vector2i.ZERO
	for i in range(-1, 2):
		for j in range(-1, 2):
			var gx := cx + i
			var gz := cz + j
			var p := Vector2(gx + 0.15 + 0.7 * Models.hash2(gx * 1.9, gz * 0.7), gz + 0.15 + 0.7 * Models.hash2(gz * 2.3, gx * 1.1)) * g
			var d := p.distance_to(Vector2(x, z))
			if d < f1:
				f2 = f1
				f1 = d
				own = Vector2i(gx, gz)
			elif d < f2:
				f2 = d
	var edge := (f2 - f1) * 0.5 + wob(x, z) * 0.35
	var r := Models.hash2(own.x * 3.7 + 0.5, own.y * 1.3 - 0.5)
	# each block's top sits on its own ledge, stepped down from the heights
	var top := -floorf(r * 4.0) * 0.4
	# the joints between blocks are gullies, steep-sided with a narrow floor
	var gully := (1.0 - smoothstep(0.5, 2.6, edge)) * CRAG_GULLY
	# the block's own face is a ledge or two down to the gully
	var y := top - gully - (1.0 - smoothstep(1.4, 2.6, edge)) * 0.5
	var wet := 0.0
	if r > 0.88 and f1 < 6.0:
		# a tarn: still water in a hollow of the block, a rim of rock round it
		var bowl := 1.0 - smoothstep(2.6, 4.2, f1 + wob(x, z) * 0.6)
		var floor_y := TARN_Y - base_y(h)
		y = minf(y, lerpf(top, floor_y, bowl))
		wet = 1.0 if bowl >= 1.0 else 0.0
	return Vector2(y * k, wet if k >= 1.0 else 0.0)


## The set piece's own shape at (x, z), before the crags: its cut, and the pools feeding its falls.
static func piece(x: float, z: float, h: float) -> Vector4:
	return fed(x, z, cut(x, z, h))


## The set piece's cut into the land at (x, z).
static func cut(x: float, z: float, h: float) -> Vector4:
	var n := stretch_of(z)
	var kind := kind_of(n)
	# what runs on a floor: lava in the cinders, water, and nothing in the desert (Guillaume,
	# 2026-11-24: "no waterfall in the sandy dunes, it's a desert after all"): dry wadis there
	var lava := 2.0 if Models.theme == "volcano" else (0.0 if Models.theme == "dunes" else 1.0)
	if kind == "open":
		return Vector4(base_y(h), h, lava if (h < 0.0 and lava == 2.0) else 0.0, 0.0)
	var zl := local(z, n)
	match kind:
		"stream":
			var e := ease_in_out(zl, 25.0)
			var d := absf(x - canyon_x(z, n)) + wob(x, z) * 0.8
			var u := clampf((7.0 - d) / 3.8, 0.0, 1.0)
			var f := smoothstep(0.0, 1.0, u) * e
			var y := lerpf(base_y(h), -1.6, f)
			if h < 0.0 and f < 0.01:
				return Vector4(y, h, lava if lava == 2.0 else 0.0, 0.0)
			var wet := lava if (u >= 1.0 and e > 0.6) else 0.0
			return Vector4(y, maxf(h, 0.06) if f > 0.01 else h, wet, 1.0 if wet > 0.0 else 0.0)
		"gorge", "canyon":
			var dims := canyon_dims()
			var head_z := START - n * SEG - HEAD
			var d: float
			if zl > HEAD:
				var cx := canyon_x(head_z, n)
				d = Vector2(x - cx, zl - HEAD).length()
			else:
				d = absf(x - canyon_x(z, n))
			d += wob(x, z) * 1.3
			var s := smoothstep(0.0, 45.0, zl)
			# the land rises round it, out of any sea
			var hl := h + 0.55 * smoothstep(dims.x + 18.0, dims.x + 4.0, d) * smoothstep(0.0, 30.0, zl)
			var u := clampf((dims.x - d) / (dims.x - dims.y), 0.0, 1.0)
			var f := terrace(u, 2 if Models.theme == "ice" else 3) * s
			var floor_y := 0.9 - dims.z
			var y := lerpf(base_y(hl), floor_y, f)
			var wet := 0.0
			if u >= 1.0 and s > 0.75 and Models.theme != "ice":
				wet = lava
			if hl < 0.0 and f < 0.01:
				return Vector4(y, hl, lava if lava == 2.0 else 0.0, 0.0)
			return Vector4(y, maxf(hl, 0.02) if f > 0.01 else hl, wet, 1.0 if wet > 0.0 else 0.0)
		"rift":
			var dims := Vector3(7.0, 1.8, DEEP)
			var d := absf(z - rift_z(x, n)) + wob(x, z) * 1.2
			var hl := h + 0.6 * smoothstep(dims.x + 22.0, dims.x + 4.0, d)
			var u := clampf((dims.x - d) / (dims.x - dims.y), 0.0, 1.0)
			var f := terrace(u, 3)
			var y := lerpf(base_y(hl), 0.9 - dims.z, f)
			if hl < 0.0 and f < 0.01:
				return Vector4(y, hl, 0.0, 0.0)
			var wet := 1.0 if u >= 1.0 else 0.0
			return Vector4(y, maxf(hl, 0.02) if f > 0.01 else hl, wet, 2.0 if wet > 0.0 else 0.0)
		"cliffs", "shelf":
			var e := ease_in_out(zl, 30.0)
			# about half land, half sea (far below) whatever the world's usual share
			var lift: float = {"coast": 0.3, "ice": -0.22, "volcano": -0.3}.get(Models.theme, 0.0)
			var hl := h + lift * e
			if hl >= 0.0:
				# no beaches on a cliff top
				return Vector4(base_y(hl), hl + 0.1 * e, 0.0, 0.0)
			# a wave-cut ledge, then the sea far below
			var drop := 6.6 if hl < -0.05 else 2.6
			return Vector4(-0.4 - drop * e, hl, lava if lava == 2.0 else 0.0, 0.0)
		"mesas":
			var e := ease_in_out(zl, 26.0)
			var m := butte(x, z)
			var t := terrace(m, 2)
			var y := base_y(h) - (DEEP - 1.5) * e * (1.0 - t)
			# the butte tops are red rock; the sunken floor is pale sand
			var hc := lerpf(clampf(h, 0.02, 0.5), 0.8, t) if e > 0.05 else h
			return Vector4(y, hc, 0.0, 0.0)
		"crater":
			var c := crater_c(n)
			var d := Vector2(x - c.x, z - c.y).length() + wob(x, z) * 1.6
			var R := CRATER_R
			# a raised rim, the land lifted round it
			var hl := h + 0.5 * smoothstep(R + 22.0, R + 6.0, d)
			var rim := smoothstep(R + 7.0, R + 1.0, d) * smoothstep(R - 3.0, R - 0.5, d)
			if rim > 0.0:
				hl = maxf(hl, 0.8 * rim)
			if d >= R:
				return Vector4(base_y(hl), hl, lava if (hl < 0.0 and lava == 2.0) else 0.0, 0.0)
			var u := clampf((R - d) / (R - CRATER_FLOOR), 0.0, 1.0)
			var f := terrace(u, 4)
			var y := lerpf(base_y(maxf(hl, 0.0)), 1.0 - DEEP, f)
			var wet := 0.0
			if u >= 1.0 and Models.theme != "dunes":
				wet = lava
			return Vector4(y, maxf(hl, 0.3), wet, 0.0)
	return Vector4(base_y(h), h, 0.0, 0.0)


## How much of a butte stands at (x, z): 1 on its top, 0 on the floor. Buttes sit on a jittered
## 24 m grid, most cells holding one, of their own size.
static func butte(x: float, z: float) -> float:
	var g := 24.0
	var cx := floorf(x / g)
	var cz := floorf(z / g)
	var best := 0.0
	for i in range(-1, 2):
		for j in range(-1, 2):
			var gx := cx + i
			var gz := cz + j
			var r := Models.hash2(gx * 1.3, gz * 2.7)
			if r < 0.15:
				continue
			var p := Vector2((gx + 0.2 + 0.6 * Models.hash2(gx, gz * 1.7)) * g, (gz + 0.2 + 0.6 * Models.hash2(gz, gx * 3.1)) * g)
			var rad := 4.5 + 5.0 * Models.hash2(gz * 0.7, gx * 0.9)
			var d := Vector2(x - p.x, (z - p.y) * (0.8 + 0.5 * r)).length() + wob(x, z) * 2.0
			best = maxf(best, clampf((rad - d) / 3.0, 0.0, 1.0))
	return best


## The ground's height there (as the chunk shows it).
static func y_at(noise: FastNoiseLite, x: float, z: float) -> float:
	return at(x, z, raw(noise, x, z)).x


static func raw(noise: FastNoiseLite, x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) + 0.35 * sin(x * 0.05 + z * 0.01) + Models.lift()


## True where a ground foe can stand: dry, and not on a cliff.
static func firm(noise: FastNoiseLite, x: float, z: float) -> bool:
	var v := at(x, z, raw(noise, x, z))
	if v.z > 0.0 or v.x < -0.5:
		return false
	var dx := y_at(noise, x + 1.0, z) - y_at(noise, x - 1.0, z)
	var dz := y_at(noise, x, z + 1.0) - y_at(noise, x, z - 1.0)
	return absf(dx) + absf(dz) < 1.2


# ---------------------------------------------------------------- set pieces that move
## Stretch n's falls: [lip, foot, width] each (lip and foot on the ground plan, y 0). The foot lies
## well inside the floor's river, whatever the wobble of the walls, so it lands on the water.
static func fall_lines(n: int) -> Array:
	var z0 := START - n * SEG
	match kind_of(n):
		"gorge", "canyon":
			if Models.theme in ["ice", "dunes"]:
				return []
			var dims := canyon_dims()
			var hz := z0 - HEAD
			var cx := canyon_x(hz, n)
			return [[Vector3(cx, 0, hz - dims.x - 1.5), Vector3(cx, 0, hz - dims.y + 1.5), FALL_W]]
		"rift":
			var out := []
			for k in 2:
				var xx := (-5.0 if k == 0 else 4.5) + (h1(n, k + 7.0) - 0.5) * 3.0
				var rz := rift_z(xx, n)
				out.append([Vector3(xx, 0, rz - 8.5), Vector3(xx, 0, rz - 0.4), FALL_W])
			return out
	return []


## True on and round a fall's course and the pool and stream feeding it, where no rock or tree
## may stand in the water.
static func near_fall(x: float, z: float) -> bool:
	var n := stretch_of(z)
	if n < 0:
		return false
	var q := Vector2(x, z)
	for line: Array in fall_lines(n):
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var p := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if p.distance_to(q) < line[2] * 0.5 + 4.5:
			return true
		var src := pool_c(a)
		p = Geometry2D.get_closest_point_to_segment(q, src, Vector2(a.x, a.z))
		if p.distance_to(q) < FEED_W + 3.5 or src.distance_to(q) < POOL_R + 4.0:
			return true
	return false


# ---------------------------------------------------------------- where the falls come from
## Guillaume, 2026-11-25: "there should not be any waterfall without a water body where it can
## come from". Every fall is fed: a pool (a lake, or a lava pool in the cinders) lies on the land
## behind its lip, and a stream runs from it over the lip, cut into the rim so the fall starts at
## the water's own level.
const POOL_R := 5.5
## How far behind the lip the pool's centre lies.
const POOL_BACK := 11.0
## The stream's half width on its flat bed: the fall's curtain is just as wide, so the stream pours
## over the lip whole.
const FEED_W := 1.6
const FALL_W := FEED_W * 2.0
## The flat, dry bank either side of the stream, at the water's level.
const BANK := 1.4
## The water's level in the pool and stream, below the plain.
const FEED_Y := -0.5
## How far past the lip the stream's notch runs into the wall.
const FEED_ON := 4.0


static func pool_c(lip: Vector3) -> Vector2:
	return Vector2(lip.x + 1.5 * signf(lip.x + 0.01), lip.z - POOL_BACK)


## The ground v at (x, z) with the pools and streams feeding stretch n's falls cut into it.
static func fed(x: float, z: float, v: Vector4) -> Vector4:
	var n := stretch_of(z)
	if n < 0 or not kind_of(n) in ["gorge", "canyon", "rift"]:
		return v
	var lines := fall_lines(n)
	if lines.is_empty():
		return v
	var q := Vector2(x, z)
	var wb := wob(x, z)
	# 0 on the dry land round them, 1 on their flat bed
	var f := 0.0
	var fs := 0.0
	var fp := 0.0
	for line: Array in lines:
		var lip: Vector3 = line[0]
		var foot: Vector3 = line[1]
		var src := pool_c(lip)
		var dl := Vector2(lip.x, lip.z)
		var end := dl + (Vector2(foot.x, foot.z) - dl).normalized() * FEED_ON
		var ds := Geometry2D.get_closest_point_to_segment(q, src, end).distance_to(q) + wb * 0.4
		# the bed runs a cell wider than the water, so the coarse ground grid never shuts the
		# stream's sheet (`pool_tris`) in its banks
		fs = maxf(fs, clampf((FEED_W - ds) * 8.0 + 1.0, 0.0, 1.0))
		f = maxf(f, clampf((FEED_W + BANK + 1.2 - ds) / 1.2, 0.0, 1.0))
		var dp := src.distance_to(q) + wb * 1.4
		fp = maxf(fp, clampf((POOL_R + 1.6 - dp) / 1.6, 0.0, 1.0))
		f = maxf(f, fp)
	if f <= 0.0:
		return v
	var y := lerpf(v.x, FEED_Y, smoothstep(0.0, 1.0, f))
	if y >= v.x:
		return v
	var liq := 2.0 if Models.theme == "volcano" else 1.0
	var wet := liq if (fs >= 1.0 or fp >= 1.0) else 0.0
	# the stream runs towards the lip (+z); the pool lies still
	return Vector4(y, maxf(v.y, 0.06), wet, 1.0 if wet > 0.0 and fs >= 1.0 else 0.0)


## The moving parts in [z_far, z_near): for each, a dictionary. "fall": a curtain draped down a
## wall (`path` of points, `w` wide, `lava`); "puffs": movers (see `MOVERS`) from `at`, `n` of
## them, heading `dir` (radians; downhill for an avalanche), `col`, size `r`, `burst` (phases
## clustered: they go off together).
static func events(z_near: float, z_far: float, noise: FastNoiseLite) -> Array:
	var out := []
	var n0 := stretch_of(z_near)
	var n1 := stretch_of(z_far - 0.01)
	for n in range(maxi(n0, 0), n1 + 1):
		for e: Dictionary in stretch_events(n, noise):
			var z: float = e.at.z
			if z <= z_near and z > z_far:
				out.append(e)
	return out


static func stretch_events(n: int, noise: FastNoiseLite) -> Array:
	var out := []
	var kind := kind_of(n)
	var z0 := START - n * SEG
	var th := Models.theme
	var lava := th == "volcano"
	var foam := Color8(0xf0, 0xfa, 0xff)
	var steam := Color8(0xe4, 0xe0, 0xdc)
	match kind:
		"gorge", "canyon":
			var dims := canyon_dims()
			var hz := z0 - HEAD
			var cx := canyon_x(hz, n)
			if th == "ice" or th == "dunes":
				# avalanches (snow, or sand slides in the dry canyon) spill off both rims now and then
				var col := Color8(0xf4, 0xfa, 0xff) if th == "ice" else Color8(0xe2, 0xbc, 0x84)
				for k in 3:
					var zz := z0 - 50.0 - k * 26.0
					var side := 1.0 if k % 2 == 0 else -1.0
					var xx := canyon_x(zz, n) + side * (dims.x + 0.5)
					var top := Vector3(xx, y_at(noise, xx, zz) + 0.3, zz)
					out.append({"t": "puffs", "m": "avalanche", "at": top, "n": 16, "dir": PI if side > 0 else 0.0,
						"col": col, "r": 0.9, "phase": h1(n, k)})
				if th == "dunes":
					# a dust devil wanders on the plain beside the canyon
					var dx := cx + (9.0 if cx < 0.0 else -9.0) + 7.0 * signf(cx + 0.01) * -1.0
					var dz := z0 - 60.0
					out.append({"t": "puffs", "m": "devil", "at": Vector3(dx, y_at(noise, dx, dz), dz), "n": 14, "dir": 0.0,
						"col": Color8(0xf0, 0xc8, 0x84), "r": 0.6, "phase": 0.0})
			else:
				# the fall at the head, and spray (or steam) where it lands
				var line: Array = fall_lines(n)[0]
				var lip: Vector3 = line[0]
				var foot: Vector3 = line[1]
				out.append({"t": "fall", "at": foot, "path": drape(noise, lip, foot, 14, FALL_W), "w": FALL_W, "lava": lava})
				out.append(sheet(line, 0.9 - dims.z, Vector2(0, 1)))
				var fy := y_at(noise, foot.x, foot.z) + 0.2
				# steam rolls in big puffs; spray is a cloud of fine white drops, not stones
				out.append({"t": "puffs", "m": "steam" if lava else "spray", "at": Vector3(foot.x, fy, foot.z + 1.0), "n": 16 if lava else 22,
					"dir": 0.0, "col": steam if lava else foam, "r": 0.42 if lava else 0.26, "phase": 0.0})
			if lava:
				# lava bombs out of the river now and then
				for k in 2:
					var zz := z0 - 60.0 - k * 30.0
					var xx := canyon_x(zz, n)
					out.append({"t": "puffs", "m": "bomb", "at": Vector3(xx, y_at(noise, xx, zz) + 0.2, zz), "n": 7, "dir": 0.0,
						"col": Color8(0xff, 0x9a, 0x2a), "r": 0.32, "phase": h1(n, k + 5.0)})
		"rift":
			# two falls pour down the far wall, spray at their feet
			for line: Array in fall_lines(n):
				var lip: Vector3 = line[0]
				var foot: Vector3 = line[1]
				out.append({"t": "fall", "at": foot, "path": drape(noise, lip, foot, 14, FALL_W), "w": FALL_W, "lava": false})
				out.append(sheet(line, 0.9 - DEEP, Vector2(1, 0)))
				out.append({"t": "puffs", "m": "spray", "at": Vector3(foot.x, y_at(noise, foot.x, foot.z) + 0.2, foot.z + 1.0),
					"n": 22, "dir": 0.0, "col": foam, "r": 0.26, "phase": 0.0})
		"crater":
			var c := crater_c(n)
			var bot := 1.0 - DEEP
			match th:
				"volcano":
					# the caldera erupts: bursts of lava bombs, a fountain, a column of smoke
					out.append({"t": "puffs", "m": "bomb", "at": Vector3(c.x, bot + 0.2, c.y), "n": 18, "dir": 0.0,
						"col": Color8(0xff, 0xa0, 0x30), "r": 0.42, "phase": 0.0})
					out.append({"t": "puffs", "m": "fountain", "at": Vector3(c.x, bot + 0.1, c.y), "n": 12, "dir": 0.0,
						"col": Color8(0xff, 0xd0, 0x50), "r": 0.5, "phase": 0.3})
					out.append({"t": "puffs", "m": "smoke", "at": Vector3(c.x + 1.0, bot + 1.0, c.y - 1.0), "n": 12, "dir": 0.0,
						"col": Color8(0x8a, 0x7c, 0x78), "r": 0.8, "phase": 0.0})
				"ice":
					# geysers round the sinkhole's lake
					for k in 3:
						var a := k * TAU / 3.0 + h1(n, 9.0) * TAU
						var p := Vector2(c.x, c.y) + Vector2(cos(a), sin(a)) * (CRATER_FLOOR + 1.6)
						out.append({"t": "puffs", "m": "geyser", "at": Vector3(p.x, y_at(noise, p.x, p.y) + 0.1, p.y), "n": 12,
							"dir": 0.0, "col": Color8(0xf0, 0xf8, 0xff), "r": 0.45, "phase": k / 3.0})
				"dunes":
					# the meteorite still smoulders at the bottom
					out.append({"t": "rock", "at": Vector3(c.x, bot, c.y)})
					out.append({"t": "puffs", "m": "smoke", "at": Vector3(c.x, bot + 1.2, c.y), "n": 9, "dir": 0.0,
						"col": Color8(0xa8, 0x98, 0x88), "r": 0.6, "phase": 0.0})
		"cliffs", "shelf":
			if th == "volcano":
				for k in 3:
					var xx := (k - 1) * 9.0 + (h1(n, k) - 0.5) * 4.0
					var zz := z0 - 40.0 - k * 30.0
					var v := at(xx, zz, raw(noise, xx, zz))
					if v.z == 2.0:
						out.append({"t": "puffs", "m": "bomb", "at": Vector3(xx, v.x + 0.2, zz), "n": 8, "dir": 0.0,
							"col": Color8(0xff, 0x9a, 0x2a), "r": 0.34, "phase": h1(n, k + 2.0)})
		"mesas":
			for k in 2:
				var xx := (h1(n, k + 11.0) - 0.5) * 12.0
				var zz := z0 - 50.0 - k * 45.0
				out.append({"t": "puffs", "m": "devil", "at": Vector3(xx, y_at(noise, xx, zz), zz), "n": 14, "dir": 0.0,
					"col": Color8(0xf0, 0xc8, 0x84), "r": 0.6, "phase": 0.0})
	return out


## The water a fall pours from and into, laid over the ground grid (which is too coarse to
## draw a 3 m stream true): the pool behind the lip, the stream from it to the lip as wide as
## the curtain, and a plunge pool where it lands on the floor (`floor_y`, the river there flowing
## `flow`). The ground's own wet cells lie under these, so they only ever show the same water.
## How far the sheets lie over the ground's own water (a hair over it would flicker).
const SHEET_UP := 0.12


static func sheet(line: Array, floor_y: float, flow: Vector2) -> Dictionary:
	return {"t": "pool", "at": line[1], "lip": line[0], "foot": line[1], "floor": floor_y, "flow": flow}


## Triangles of a pool/stream sheet (see `sheet`) into `dst` [vertices, flow].
static func pool_tris(dst: Array, e: Dictionary) -> void:
	var lip: Vector3 = e.lip
	var foot: Vector3 = e.foot
	var src := pool_c(lip)
	var top := FEED_Y + SHEET_UP
	# the pool lies a hair under its stream, so where they overlap the stream shows whole
	disc(dst, Vector3(src.x, top - 0.03, src.y), POOL_R + 0.5, Vector2.ZERO)
	# the stream: from the pool's edge to the lip, as wide as the curtain there
	var b := Vector3(lip.x, top, lip.z)
	var a := Vector3(src.x, top, src.y)
	a += (b - a).normalized() * (POOL_R - 0.5)
	var side := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized() * (FEED_W + 0.15)
	var q := [a - side, a + side, b + side, b - side]
	for t: Array in [[0, 2, 1], [0, 3, 2]]:
		for k: int in t:
			dst[0].append(q[k])
			dst[1].append(Vector2(0, 1))
	disc(dst, Vector3(foot.x, e.floor + SHEET_UP, foot.z + 0.6), FEED_W + 0.9, e.flow)


static func disc(dst: Array, c: Vector3, r: float, flow: Vector2) -> void:
	var k := 12
	for i in k:
		var a0 := TAU * i / k
		var a1 := TAU * (i + 1) / k
		for p: Vector3 in [c, c + Vector3(cos(a1), 0, sin(a1)) * r, c + Vector3(cos(a0), 0, sin(a0)) * r]:
			dst[0].append(p)
			dst[1].append(flow)


## A fall's path from `a` down to `b` (x, z), `k` steps: it pours over the rock's outline (the
## upper hull of the ground under the whole curtain, `w` wide), so it never runs into a ledge,
## and leaps clear of the steps on its way down.
static func drape(noise: FastNoiseLite, a: Vector3, b: Vector3, k: int, w := 3.2) -> PackedVector3Array:
	var dir := Vector2(b.x - a.x, b.z - a.z)
	var len := dir.length()
	var side := Vector2(-dir.y, dir.x).normalized() * w * 0.55
	var dense := maxi(k * 6, int(len / 0.25))
	var prof := PackedVector2Array()
	for i in dense + 1:
		var t := float(i) / dense
		var c := Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), t)
		var y := -INF
		for s in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var q: Vector2 = c + side * s
			y = maxf(y, y_at(noise, q.x, q.y))
		prof.append(Vector2(t * len, y))
	# the upper hull, lip to foot
	var hull := PackedVector2Array()
	for p in prof:
		while hull.size() >= 2:
			var o := hull[hull.size() - 2]
			var m := hull[hull.size() - 1]
			if (m.x - o.x) * (p.y - o.y) - (m.y - o.y) * (p.x - o.x) >= 0.0:
				hull.remove_at(hull.size() - 1)
			else:
				break
		hull.append(p)
	var out := PackedVector3Array()
	var j := 0
	var top := hull[0].y
	for i in k + 1:
		var d := len * float(i) / k
		while j < hull.size() - 2 and hull[j + 1].x < d:
			j += 1
		var h0 := hull[j]
		var h1 := hull[j + 1]
		var y := lerpf(h0.y, h1.y, clampf((d - h0.x) / maxf(h1.x - h0.x, 0.001), 0.0, 1.0))
		var p := a.lerp(b, float(i) / k)
		# it leaves the lip at the stream's own level and lands on the water below; in between
		# it leaps clear of the rock
		p.y = y + (SHEET_UP if i == k else lerpf(SHEET_UP, 0.3, smoothstep(0.0, 0.8, top - y)))
		out.append(p)
	return out


## The movers: period (s), share of it each is out (`duty`), gravity, speed up and out, spin.
## A burst clusters their phases, so they go off together.
const MOVERS := {
	"bomb": {"period": 5.0, "duty": 0.46, "grav": 14.0, "up": 16.0, "out": 3.2, "burst": true, "glow": true, "grow": 0.0},
	"fountain": {"period": 1.0, "duty": 1.0, "grav": 16.0, "up": 7.5, "out": 1.2, "burst": false, "glow": true, "grow": 0.0},
	"smoke": {"period": 6.0, "duty": 1.0, "grav": -0.1, "up": 1.8, "out": 0.5, "burst": false, "glow": false, "grow": 1.0},
	"steam": {"period": 3.0, "duty": 1.0, "grav": 0.0, "up": 1.6, "out": 0.6, "burst": false, "glow": false, "grow": 1.4},
	"spray": {"period": 1.2, "duty": 1.0, "grav": 4.0, "up": 2.8, "out": 1.8, "burst": false, "glow": true, "grow": 0.3},
	"geyser": {"period": 6.0, "duty": 0.4, "grav": 11.0, "up": 10.0, "out": 0.5, "burst": true, "glow": false, "grow": 0.9},
	"avalanche": {"period": 9.0, "duty": 0.45, "grav": 0.0, "up": -2.6, "out": 1.8, "burst": true, "glow": false, "grow": 1.6},
	"devil": {"period": 2.6, "duty": 1.0, "grav": 0.0, "up": 1.5, "out": 0.0, "burst": false, "glow": false, "grow": 0.5, "spin": 4.0},
}

## The highest any mover may reach: under the ship's flight plane.
const TOP_Y := 5.2


## The chunk's moving set pieces and liquid surfaces as one mesh (a surface per material), or null.
static func fx_mesh(noise: FastNoiseLite) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var wet := [liquid.duplicate(), liquid_flow.duplicate()]
	for e: Dictionary in fx:
		if e.t == "pool":
			pool_tris(wet, e)
	if not wet[0].is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = wet[0]
		arr[Mesh.ARRAY_TEX_UV] = wet[1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, lava_mat() if Models.theme == "volcano" else water_mat())
	var falls := {}
	var movers := {}
	for e: Dictionary in fx:
		if e.t == "fall":
			var key := "lava" if e.lava else "water"
			if not falls.has(key):
				falls[key] = [PackedVector3Array(), PackedVector2Array()]
			curtain(falls[key], e.path, e.w)
		elif e.t == "puffs":
			if not movers.has(e.m):
				movers[e.m] = [PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]
			puffs(movers[e.m], e)
	for key: String in falls:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = falls[key][0]
		arr[Mesh.ARRAY_TEX_UV] = falls[key][1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, fall_mat(key))
	for key: String in movers:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = movers[key][0]
		arr[Mesh.ARRAY_COLOR] = movers[key][1]
		arr[Mesh.ARRAY_TEX_UV] = movers[key][2]
		arr[Mesh.ARRAY_TEX_UV2] = movers[key][3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mover_mat(key))
	return mesh if mesh.get_surface_count() > 0 else null


## A curtain strip down `path`, `w` wide, across the path's heading; UV: (across 0..1, metres down).
static func curtain(dst: Array, path: PackedVector3Array, w: float) -> void:
	var down := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var side := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized() * w * 0.5
		if side == Vector3.ZERO:
			side = Vector3(w * 0.5, 0, 0)
		var seg := a.distance_to(b)
		# it narrows a little as it falls, then fans out at the foot
		var ka := 1.0 - 0.15 * float(i) / path.size()
		var kb := 1.0 - 0.15 * float(i + 1) / path.size()
		var q := [a - side * ka, a + side * ka, b + side * kb, b - side * kb]
		var uv := [Vector2(0, down), Vector2(1, down), Vector2(1, down + seg), Vector2(0, down + seg)]
		for t: Array in [[0, 2, 1], [0, 3, 2]]:
			for k: int in t:
				dst[0].append(q[k])
				dst[1].append(uv[k])
		down += seg


## `e.n` movers round e.at: little faceted balls, their centre in UV/UV2.x, phase in UV2.y and
## heading in COLOR.a (the shader moves them).
static func puffs(dst: Array, e: Dictionary) -> void:
	var m: Dictionary = MOVERS[e.m]
	var p: Vector3 = e.at
	for i in int(e.n):
		var ph: float = float(i) / e.n
		if m.burst:
			ph = fposmod(e.phase + float(i) / e.n * 0.12, 1.0)
		var sd := Models.hash2(p.x + i * 1.7, p.z - i * 0.9)
		var head: float = e.dir + (sd - 0.5) * 1.3 if e.m == "avalanche" else sd * TAU
		var r: float = e.r * (0.7 + 0.6 * Models.hash2(i * 2.3, p.x))
		var col: Color = e.col
		col = col.darkened(0.12 * Models.hash2(i, p.z))
		col.a = fposmod(head, TAU) / TAU
		var top := Vector3(0, r, 0)
		var ring := []
		var nr := 7 if not m.glow else 5
		for k in nr:
			var a := TAU * k / nr + sd * 3.0
			ring.append(Vector3(cos(a), 0, sin(a)) * r)
		for k in nr:
			var q0: Vector3 = ring[k]
			var q1: Vector3 = ring[(k + 1) % nr]
			for tri: Array in [[q0, top, q1], [q1, -top, q0]]:
				for v: Vector3 in [tri[0], tri[2], tri[1]]:
					dst[0].append(p + v)
					# the upper half lit, the lower in shade (they're unshaded)
					var c := col if v.y >= 0.0 else Color(col.r * 0.78, col.g * 0.78, col.b * 0.8, col.a)
					if v.y > 0.5 * r:
						c = Color(minf(col.r * 1.08, 1.0), minf(col.g * 1.08, 1.0), minf(col.b * 1.08, 1.0), col.a)
					dst[1].append(c)
					dst[2].append(Vector2(p.x, p.z))
					dst[3].append(Vector2(p.y, ph + sd * 0.001))


static var _mats := {}


static func shader_mat(key: String, code: String) -> ShaderMaterial:
	if not _mats.has(key):
		var sh := Shader.new()
		sh.code = code
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats[key] = m
	return _mats[key]


const NOISE_GLSL := """
float hsh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1, 0)), f.x), mix(hsh(i + vec2(0, 1)), hsh(i + vec2(1, 1)), f.x), f.y);
}
"""


## Lava: glowing rivers of it under a dark crust that drifts and cracks. UV is the flow.
static func lava_mat() -> ShaderMaterial:
	return shader_mat("lava", """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying vec3 wp;
varying vec2 flow;
%s
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV;
}
void fragment() {
	vec2 p = wp.xz - flow * TIME * 1.4 + vec2(TIME * 0.08, TIME * 0.05);
	float n = vn(p * 0.33) * 0.6 + vn(p * 0.9 + 7.0) * 0.3 + vn(p * 2.1 - 3.0) * 0.1;
	float crust = smoothstep(0.5, 0.62, n);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.7 + wp.x * 0.3 + wp.z * 0.2);
	vec3 hot = mix(vec3(1.0, 0.32, 0.04), vec3(1.0, 0.78, 0.22), smoothstep(0.42, 0.2, n) * (0.6 + 0.4 * pulse));
	vec3 col = mix(hot, vec3(0.16, 0.07, 0.05), crust);
	col = mix(col, vec3(1.0, 0.5, 0.1), smoothstep(0.5, 0.53, n) * (1.0 - smoothstep(0.53, 0.58, n)) * 0.8);
	ALBEDO = col;
}
""" % NOISE_GLSL)


## River water: deep in the middle, streaks of foam running with the flow.
static func water_mat() -> ShaderMaterial:
	var deep := "vec3(0.04, 0.22, 0.32)" if Models.theme != "dunes" else "vec3(0.05, 0.30, 0.30)"
	return shader_mat("water" + Models.theme, """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying vec3 wp;
varying vec2 flow;
%s
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV;
}
void fragment() {
	vec2 ax = length(flow) > 0.0 ? normalize(flow) : vec2(0.0, 1.0);
	vec2 sd = vec2(ax.y, -ax.x);
	vec2 q = vec2(dot(wp.xz, sd) * 1.6, dot(wp.xz, ax) * 0.3 - TIME * 1.1);
	float n = vn(q) * 0.7 + vn(q * 2.3 + 4.0) * 0.3;
	vec3 col = mix(%s, vec3(0.16, 0.52, 0.62), vn(wp.xz * 0.4) * 0.6);
	col = mix(col, vec3(0.85, 0.95, 1.0), smoothstep(0.66, 0.8, n) * 0.85);
	ALBEDO = col;
}
""" % [NOISE_GLSL, deep])


## A fall: bands rushing down (UV.y is metres down), fraying at the sides.
static func fall_mat(key: String) -> ShaderMaterial:
	var a: String = {"water": "vec3(0.55, 0.80, 0.92)", "lava": "vec3(1.0, 0.36, 0.05)"}[key]
	var b: String = {"water": "vec3(0.95, 0.99, 1.0)", "lava": "vec3(1.0, 0.86, 0.3)"}[key]
	return shader_mat("fall" + key, """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
%s
void fragment() {
	float n = vn(vec2(UV.x * 7.0, UV.y * 0.7 - TIME * 3.2)) * 0.7 + vn(vec2(UV.x * 15.0, UV.y * 1.6 - TIME * 4.5)) * 0.3;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	if (n * edge < 0.18) {
		discard;
	}
	ALBEDO = mix(%s, %s, smoothstep(0.45, 0.75, n));
}
""" % [NOISE_GLSL, a, b])


## Movers: each little ball (its centre in UV, UV2.x; phase UV2.y; heading COLOR.a) flies from its
## start for `duty` of the period, under gravity, growing (smoke) or not (bombs), then waits.
static func mover_mat(key: String) -> ShaderMaterial:
	var m: Dictionary = MOVERS[key]
	var code := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
varying float lit;
void vertex() {
	vec3 base = vec3(UV.x, UV2.x, UV.y);
	vec3 o = VERTEX - base;
	float sd = fract(UV2.y * 91.7 + base.x * 0.13);
	float life = fract(TIME / %f + UV2.y);
	float s = life / %f;
	float on = step(s, 1.0);
	s = min(s, 1.0);
	float t = s * %f * %f;
	float h = COLOR.a * 6.2832 + TIME * %f * (0.6 + sd);
	float sp = %f * (0.45 + 0.55 * fract(sd * 7.3));
	float rad = %f;
	vec3 p = vec3(cos(h) * sp * t, (%f * (0.7 + 0.3 * sd)) * t - 0.5 * %f * t * t, sin(h) * sp * t);
	if (rad > 0.0) {
		p.xz = vec2(cos(h), sin(h)) * (0.4 + 0.25 * p.y) * rad;
	}
	p.y = min(p.y, %f - base.y);
	float k = (1.0 + %f * s) * sin(3.1416 * min(s * 1.6, 1.0) * 0.5 + 0.0001) * (1.0 - smoothstep(0.75, 1.0, s));
	k = max(k, 0.0) * on;
	VERTEX = base + p + o * k;
	lit = 1.0 - s * 0.35;
}
void fragment() {
	ALBEDO = COLOR.rgb * %s;
}
"""
	var spin: float = m.get("spin", 0.0)
	var glow := "(1.25 + 0.4 * lit)" if m.glow else "lit"
	return shader_mat("mover" + key, code % [m.period, m.duty, m.duty, m.period, spin, m.out, 2.2 if spin > 0.0 else 0.0,
		m.up, m.grav, TOP_Y, m.grow, glow])

extends SceneTree
## The land's set pieces (relief.gd; Guillaume, 2026-11-24: "the ground is mostly flat and
## uneventful"): every world but the city has its canyons, cliffs, craters... in a level, deep
## below the plain; stretches meet without a wall; ground foes stand on the ground the chunks
## show and never in a river or on a cliff; the moving parts are built. Runs headless:
##   godot --headless --path . --script tests/relief_test.gd

const SAVE := "user://test_relief_save.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	return g


func course() -> void:
	print("course")
	for theme: String in Relief.FEATURES:
		Models.theme = theme
		for lv in 3:
			Relief.level = lv
			var seen := {}
			var prev := ""
			var repeats := 0
			# a level runs well past 8 stretches (1,200 m)
			for n in 8:
				var k := Relief.kind_of(n)
				seen[k] = true
				if k == prev:
					repeats += 1
				prev = k
			var all := true
			for f: String in Relief.FEATURES[theme]:
				all = all and seen.has(f)
			check(all and seen.has("stream") and repeats == 0, "%s level %d: every set piece, no two alike in a row %s" % [theme, lv, seen.keys()])
		# the land the hangar shows is the same for every level, so picking one never rebuilds it
		var same := true
		for n in Relief.LEVEL_FROM:
			Relief.level = 0
			var a := Relief.kind_of(n)
			Relief.level = 2
			same = same and a == Relief.kind_of(n)
		check(same, "%s: the hangar's land is the same for every level" % theme)
	Models.theme = "city"
	check(Relief.kind_of(3) == "open", "the city keeps its flat ground")
	Relief.level = 0


## Each stretch fades back to the plain at its ends: no wall where two stretches meet.
func seams(g: Game) -> void:
	print("seams")
	for theme: String in Relief.FEATURES:
		Models.theme = theme
		var worst := 0.0
		for n in 8:
			var z := Relief.START - n * Relief.SEG
			for z2 in [z - 0.01, z + 0.01]:
				for i in 25:
					var x := -40.0 + i * 3.3
					var h := Relief.raw(g.noise, x, z2)
					worst = maxf(worst, absf(Relief.at(x, z2, h).x - Relief.plain(x, z2, h)))
		check(worst < 0.1, "%s: stretches meet on the plain (off by %.2f)" % [theme, worst])


## Real relief: deep floors in every world, and still nothing near the ship.
func depth(g: Game) -> void:
	print("depth")
	for theme: String in Relief.FEATURES:
		Models.theme = theme
		var lo := INF
		var hi := -INF
		var steep := 0
		var liquid := 0
		var fx := {}
		var falls := 0
		var buried := 0.0
		var unfed := 0
		for k in 30:
			var m := Models.ground_chunk(g.noise, -k * Game.CHUNK, Vector2(Game.CHUNK_W, Game.CHUNK), 2.0)
			var arr := m.surface_get_arrays(m.get_surface_count() - 1)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
			for c: Color in cols:
				if c.a < 0.5:
					steep += 1
			liquid += Relief.liquid.size()
			var fm := Relief.fx_mesh(g.noise)
			for e: Dictionary in Relief.fx:
				fx[e.get("m", e.t)] = true
				if e.t == "fall":
					falls += 1
					buried = maxf(buried, fall_buried(g, e))
					if not fed(g, e) or not sheeted(e):
						unfed += 1
		check(lo < -6.0, "%s: the land drops far below the plain (%.1f m)" % [theme, lo])
		check(hi < Rules.PY - 3.0, "%s: and never rises near the ship (%.1f m)" % [theme, hi])
		check(steep > 200, "%s: steep faces are bare, layered rock (%d vertices)" % [theme, steep])
		var want: Array = {"coast": ["fall", "spray"], "dunes": ["avalanche", "devil", "rock", "smoke"], "ice": ["avalanche", "geyser"],
			"volcano": ["fall", "bomb", "fountain", "smoke", "steam"]}[theme]
		var have := true
		for w: String in want:
			have = have and fx.has(w)
		check(have, "%s: moving set pieces %s" % [theme, fx.keys()])
		if theme == "dunes":
			check(falls == 0 and liquid == 0, "dunes: a desert, no falls and no water (%d falls, %d wet vertices)" % [falls, liquid])
		elif theme != "ice":
			check(falls > 0 and buried < 0.05, "%s: its %d falls pour clear of the rock, never through a ledge (%.2f m under)" % [theme, falls, buried])
			check(unfed == 0, "%s: every fall is fed by a pool and a stream as wide as it, behind its lip, and lands in a plunge pool (%d of %d off)" % [theme, unfed, falls])
		check(theme in ["ice", "dunes"] or liquid > 0, "%s: rivers, lakes or lava flow (%d vertices)" % [theme, liquid])
	for key: String in Relief.MOVERS:
		check(Relief.mover_mat(key).shader.code.contains("min(p.y, %f" % Relief.TOP_Y), "%s: capped under the ship" % key)


## True when the water (or lava) runs unbroken from a pool behind the fall's lip to the lip, and
## the curtain starts at its level (Guillaume, 2026-11-25: "there should not be any waterfall
## without a water body where it can come from").
func fed(g: Game, e: Dictionary) -> bool:
	var path: PackedVector3Array = e.path
	var lip := path[0]
	var src := Relief.pool_c(lip)
	var wet := Relief.at(src.x, src.y, Relief.raw(g.noise, src.x, src.y)).z > 0.0
	var run := 0
	var from := Vector2(lip.x, lip.z)
	var steps := int(from.distance_to(src) / 0.5)
	for i in steps + 1:
		var q := from.lerp(src, float(i) / steps)
		var v := Relief.at(q.x, q.y, Relief.raw(g.noise, q.x, q.y))
		if v.z <= 0.0:
			return false
		run += 1
	var level := Relief.y_at(g.noise, lip.x, lip.z)
	return wet and run > 0 and absf(lip.y - Relief.SHEET_UP - level) < 0.1


## True when the fall's water is laid out whole round it (Guillaume, 2026-11-25: "waterfall is not
## aligned"): a stream sheet as wide as the curtain running into its top, at its level, and a
## plunge pool under its foot.
func sheeted(e: Dictionary) -> bool:
	var path: PackedVector3Array = e.path
	for o: Dictionary in Relief.fx:
		if o.t == "pool" and (o.lip as Vector3).is_equal_approx(Vector3(path[0].x, 0, path[0].z)):
			var dst := [PackedVector3Array(), PackedVector2Array()]
			Relief.pool_tris(dst, o)
			var top := path[0]
			var foot := path[path.size() - 1]
			var at_lip := 0
			var under := false
			for v: Vector3 in dst[0]:
				if Vector2(v.x - top.x, v.z - top.z).length() < e.w * 0.5 + 0.3 and absf(v.y - top.y) < 0.01:
					at_lip += 1
				if absf(v.y - foot.y) < 0.01 and Vector2(v.x - foot.x, v.z - foot.z).length() < 1.0:
					under = true
			return at_lip >= 2 and under and e.w >= Relief.FEED_W * 2.0
	return false


## How far a fall's curtain goes under the ground anywhere across it (Guillaume, 2026-11-24:
## "waterfall should not pass through the stones").
func fall_buried(g: Game, e: Dictionary) -> float:
	var worst := 0.0
	var path: PackedVector3Array = e.path
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var side: Vector3 = Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized() * e.w * 0.5
		for t in 5:
			var p := a.lerp(b, t / 4.0)
			for s in [-0.85, 0.0, 0.85]:
				var q: Vector3 = p + side * s
				worst = maxf(worst, Relief.y_at(g.noise, q.x, q.z) - q.y)
	return worst


## Ground foes stand on the ground the chunks show, and only where they can stand.
func footing(g: Game) -> void:
	print("footing")
	for theme: String in Relief.FEATURES:
		g.apply_theme(theme)
		var off := 0.0
		var bad := 0
		for k in 30:
			var m := Models.ground_chunk(g.noise, -k * Game.CHUNK, Vector2(Game.CHUNK_W, Game.CHUNK), 2.0)
			var vs: PackedVector3Array = m.surface_get_arrays(m.get_surface_count() - 1)[Mesh.ARRAY_VERTEX]
			for i in range(0, vs.size(), 37):
				var v := vs[i]
				# the open sea (y -0.4) counts as 0 for ground_y; land and the deep places match
				if absf(v.x) < 30.0 and (v.y > -0.39 or v.y < -0.45):
					off = maxf(off, absf(g.ground_y(v.x, v.z) - v.y))
			for i in 12:
				var at := Foes.dry_x(g, (i - 6) * 1.1, -k * Game.CHUNK - 10.0 - i * 2.0, null)
				var r := Relief.at(at.x, at.y, Relief.raw(g.noise, at.x, at.y))
				if g.land(at.x, at.y) > 0.0 and (r.z > 0.0 or not Relief.firm(g.noise, at.x, at.y)):
					bad += 1
		check(off < 0.05, "%s: ground foes stand on the ground shown (off by %.2f)" % [theme, off])
		check(bad == 0, "%s: never in a river, on lava or on a cliff (%d)" % [theme, bad])


## Guillaume (2026-11-24): "a pyramid in a city like structure with small houses around it". Each
## world's town: a level platform, its centrepiece on the square, houses facing it, a wall round it,
## and none of the land's loose props inside.
func towns(g: Game) -> void:
	print("towns")
	var centre := {"dunes": "pyramid", "coast": "church", "ice": "snowman", "volcano": "altar"}
	var homes := {"dunes": "adobe", "coast": "house", "ice": "igloo", "volcano": "hut"}
	for theme: String in Relief.FEATURES:
		Models.theme = theme
		var n := -1
		for k in 10:
			if Relief.has_town(k):
				n = k
				break
		check(n >= 0 and n < 4 and Relief.kind_of(n) == Relief.TOWN_HOST[theme], "%s: a town early in every level, on its %s (stretch %d)" % [theme, Relief.TOWN_HOST[theme], n])
		# it stands high over its set piece: the land drops away round the plateau
		var c0 := Relief.town_c(n)
		var below := INF
		for i in 16:
			var a := i * TAU / 16.0
			var q := c0 + Vector2(cos(a), sin(a)) * (Towns.FLAT + 9.0)
			below = minf(below, Relief.y_at(g.noise, q.x, q.y))
		check(below < -4.0, "%s: the town looks down on its %s (%.1f m below)" % [theme, Relief.TOWN_HOST[theme], below])
		var c := Relief.town_c(n)
		var worst := 0.0
		for i in 9:
			for j in 9:
				var x := c.x - 12.0 + i * 3.0
				var z := c.y - 12.0 + j * 3.0
				worst = maxf(worst, absf(Relief.y_at(g.noise, x, z) - Towns.GROUND_Y))
		check(worst < 0.05, "%s: the town stands on level ground (off by %.2f)" % [theme, worst])
		Models.scenery.clear()
		Models.marks.clear()
		var z0 := ceilf((c.y + 40.0) / Game.CHUNK) * Game.CHUNK
		for k in 3:
			Models.ground_chunk(g.noise, z0 - k * Game.CHUNK, Vector2(Game.CHUNK_W, Game.CHUNK), 2.0)
		var kinds := {}
		for m: Dictionary in Models.marks:
			kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
		var have: int = Models.scenery.get(centre[theme], 0)
		check(have == 1, "%s: one %s at its heart" % [theme, centre[theme]])
		var houses: int = Models.scenery.get(homes[theme], 0) + Models.scenery.get("cabin", 0)
		check(houses >= 25, "%s: %d %s round it" % [theme, houses, homes[theme]])
		check(Models.scenery.get("paving", 0) >= 2, "%s: a paved square and avenue" % theme)
		check(Models.scenery.get("town wall", 0) + Models.scenery.get("hedge", 0) + Models.scenery.get("fence", 0) > 20, "%s: a wall round it" % theme)
		var stray := 0
		for m: Dictionary in Models.marks:
			if Relief.in_town(m.pos.x, m.pos.z) and m.kind not in ["pyramid", "snowman", "house", "stone head"]:
				stray += 1
		check(stray == 0, "%s: no stray landmarks inside" % theme)


## The city is a calm backdrop: its colours in a narrow, muted band and few fires, so foes and
## bullets stand out (Guillaume, 2026-11-24: "the city landscape is too messy... not very easy to
## see the enemies on the very heavy background").
func city(g: Game) -> void:
	print("city")
	g.apply_theme("city")
	var n := 0
	var out := 0
	var sat := 0.0
	var fires := 0
	var top := -INF
	var glows := 0
	var neons := 0
	var shots_like := 0
	for k in 10:
		var m := Models.ground_chunk(g.noise, -k * Game.CHUNK, Vector2(Game.CHUNK_W, Game.CHUNK), 2.0)
		fires += City.fires.size()
		glows += City.glows.size()
		for gl: Array in City.glows:
			var gc: Color = gl[1]
			neons += 1 if gl[2] else 0
			# never the foes' magenta nor the player's blue
			if (gc.r > 0.6 and gc.b > 0.5 and gc.g < 0.5) or (gc.b > gc.r + 0.15):
				shots_like += 1
		for s in m.get_surface_count():
			for v: Vector3 in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				top = maxf(top, v.y)
			for c: Color in m.surface_get_arrays(s)[Mesh.ARRAY_COLOR]:
				n += 1
				var l := c.get_luminance()
				if l < 0.2 or l > 0.7:
					out += 1
				sat += c.s
	check(n > 0 and out < n * 0.03, "city: its colours stay in a calm mid band (%d of %d outside)" % [out, n])
	check(sat / n < 0.12, "city: muted colours (saturation %.2f)" % (sat / n))
	check(fires > 0 and fires <= 80, "city: a few fires, not everywhere (%d in 10 chunks)" % fires)
	# Guillaume (2026-11-26): a few dim lit windows and neon signs, warm accents in the grey
	check(glows > 200 and neons > 10 and neons < glows / 4, "city: lit windows (%d) and the odd neon sign (%d)" % [glows - neons, neons])
	check(shots_like == 0, "city: no light looks like a shot (%d)" % shots_like)
	# Guillaume (2026-11-26): "the city world is very flat... it doesn't go as high as a city should".
	# Its streets lie deep, so its towers rise far from them, and still under the ship
	var street := g.ground_y(3.0, -30.0)
	check(street < -City.SINK + 1.0, "city: the streets lie deep (%.1f m)" % street)
	check(top - street > 9.0 and top < Rules.PY - 0.5, "city: towers rise %.1f m over the streets, under the ship (top %.1f)" % [top - street, top])
	var peak := 0.0
	var low := 1.0
	for i in 40:
		var t := City.skyline(0.0, -i * 6.0)
		peak = maxf(peak, t)
		low = minf(low, t)
	check(peak > 0.8 and low < 0.2, "city: the skyline climbs to a downtown and falls away (%.2f..%.2f)" % [low, peak])
	# Guillaume (2026-11-26): "I want 80% of blocks to be high towers": blocks away from the
	# downtowns raise towers near downtown's height, a few stay low
	var mid_tall := 0
	var mid_low := 0
	for k in 20:
		for m in 20:
			var t := City.midtown(k - 10, m - 10)
			mid_tall += 1 if t >= 0.8 else 0
			mid_low += 1 if t == 0.0 else 0
	check(mid_tall >= 300 and mid_tall <= 340 and mid_low > 40, "city: high towers on about 80%% of blocks (%d of 400), a few blocks low (%d)" % [mid_tall, mid_low])
	# towers cast soft shadows over the streets: a street behind a tower (from the sun) lies in its
	# shade, one on its sunny side doesn't, and a low roof's shadow is short
	var cx := City.Ctx.new()
	cx.casters[Vector2i(0, 0)] = [[2.0, 6.0, 2.0, 6.0, 4.0]]
	var sl := Models.sun_slide.length()
	var dir := City.to_local(-Models.sun_slide.x / sl, -Models.sun_slide.y / sl)
	var mid := Vector2(4.0, 4.0)
	var behind := City.cast_at(cx, mid - dir * 4.0, -City.SINK, dir, sl, City.CAST_REACH)
	var sunny := City.cast_at(cx, mid + dir * 4.0, -City.SINK, dir, sl, City.CAST_REACH)
	cx.casters[Vector2i(0, 0)] = [[2.0, 6.0, 2.0, 6.0, -City.SINK + 0.5]]
	var low_far := City.cast_at(cx, mid - dir * 4.0, -City.SINK, dir, sl, City.CAST_REACH)
	check(behind > 0.99 and sunny == 0.0 and low_far == 0.0, "city: towers shade the streets behind them (%.2f, %.2f, %.2f)" % [behind, sunny, low_far])


## Baked shadows (Guillaume, 2026-11-24: "bake shadows... even for moving objects"): the land
## shades the ground below its cliffs and rims, never the open plain; a shadow cast into a canyon
## lands on its floor.
func shadows(g: Game) -> void:
	print("shadows")
	for theme: String in ["dunes", "volcano"]:
		g.apply_theme(theme)
		var gh := func(x: float, z: float) -> float: return Relief.y_at(g.noise, x, z)
		var shaded := 0
		var plain := 0
		var deep := INF
		for k in 30:
			for i in 30:
				var x := -28.0 + i * 2.0
				var z := -k * Game.CHUNK - 10.0
				var y: float = gh.call(x, z)
				var sh := Models.sun_shade(gh, Vector3(x, y, z))
				if sh > 0.5:
					shaded += 1
				if y > -0.1 and sh > 0.0:
					plain += 1
				if y < deep:
					deep = y
		check(shaded > 5 and plain == 0, "%s: the land shades the ground under its walls (%d spots), never the plain (%d)" % [theme, shaded, plain])
		# a ground foe down in the deepest place casts its shadow on that floor, not up on the plain
		var lowest := Vector2.ZERO
		var lo := INF
		for k in 40:
			for i in 20:
				var p := Vector2(-15.0 + i * 1.5, -k * 7.0 - 20.0)
				var y := Relief.y_at(g.noise, p.x, p.y)
				if y < lo:
					lo = y
					lowest = p
		var src := Vector3(lowest.x, lo + 0.6, lowest.y)
		var land := g.land_shadow_y(src)
		check(land < -3.0 and absf(land - lo) < 1.5, "%s: a shadow cast into the depths lands on the floor (%.1f m, floor %.1f m)" % [theme, land, lo])


func _initialize() -> void:
	print("Vantage relief test")
	var g := make_game()
	await process_frame
	course()
	seams(g)
	depth(g)
	footing(g)
	city(g)
	shadows(g)
	towns(g)
	Models.theme = "coast"
	g.queue_free()
	await process_frame
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)

extends SceneTree
## Explosions (blasts.gd): what a blast is made of by size, that pieces clear away and go back
## to the pool, the budget under heavy fire, chains, the light cap, blasts keeping up with the
## chase, and the screen shake easing off. Runs headless:
##   godot --headless --path . --script tests/blasts_test.gd

const SAVE := "user://test_blasts_save.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func kinds(b: Blasts) -> Dictionary:
	var out := {}
	for p in b.parts:
		out[p.kind] = int(out.get(p.kind, 0)) + 1
	return out


func run(b: Blasts, secs: float) -> void:
	for i in int(secs / DT):
		b.step(DT)


func pieces() -> void:
	print("pieces")
	var b := Blasts.new()
	root.add_child(b)
	await process_frame
	b.rng.seed = 1
	b.explode(Vector3.ZERO, 0.4, Models.CYAN)
	var k := kinds(b)
	check(k.has("flash") and k.has("ember") and not k.has("fire") and not k.has("chunk"), "a spark is a flash and a few embers")
	b.clear()
	b.explode(Vector3.ZERO, 1.3)
	k = kinds(b)
	check(k.get("fire", 0) >= 3 and k.has("chunk") and not k.has("ring"), "a light foe: a fireball and some debris (%s)" % k)
	b.clear()
	b.rng.seed = 1
	b.explode(Vector3.ZERO, 4.0)
	k = kinds(b)
	check(k.get("fire", 0) >= 6 and k.get("smoke", 0) >= 3 and k.get("chunk", 0) >= 4 and k.has("ring"), "a boss part: fireball, smoke, chunks and a shockwave (%s)" % k)
	check(b.lights.any(func(l: Blasts.Light) -> bool: return l.node.visible), "a big blast lights up the scene")
	run(b, 4.0)
	check(b.parts.is_empty() and not b.busy(), "every piece is gone after a few seconds")
	check(b.lights.all(func(l: Blasts.Light) -> bool: return not l.node.visible), "and the light is out")
	var made := b.get_child_count()
	b.rng.seed = 1
	b.explode(Vector3.ZERO, 4.0)
	run(b, 4.0)
	check(b.get_child_count() == made, "the same blast again reuses pooled pieces (%d nodes, was %d)" % [b.get_child_count(), made])
	b.clear()
	for i in 10:
		b.explode(Vector3(i, 0, 0), 3.0)
	check(b.lights.filter(func(l: Blasts.Light) -> bool: return l.node.visible).size() <= Blasts.LIGHTS, "never more than %d lights" % Blasts.LIGHTS)
	for i in 60:
		b.explode(Vector3(i, 0, 0), 4.0)
	check(b.parts.size() <= Blasts.CAP + 60 * 2, "heavy fire stays near the budget (%d pieces)" % b.parts.size())
	b.clear()
	b.chain([Vector3.ZERO, Vector3(2, 0, 0), Vector3(4, 0, 0)], 2.0, 0.5, Vector3.ZERO, 5.0)
	check(b.parts.is_empty() and b.pending.size() == 4, "a chain waits to go off (3 blasts and a finale)")
	run(b, 0.3)
	check(not b.parts.is_empty() and b.pending.size() < 4, "and goes off one after another")
	run(b, 0.6)
	check(b.pending.is_empty(), "the finale goes off last")
	b.clear()
	b.splash(Vector3.ZERO, 9.0)
	k = kinds(b)
	check(k.get("spout", 0) >= 3 and k.has("ring"), "hitting the sea throws up water spouts and a foam ring")
	b.clear()
	b.explode(Vector3.ZERO, 3.0, Models.AMBER, Vector3(0, 0, -18))
	run(b, 0.4)
	var mean := Vector3.ZERO
	for p in b.parts:
		mean += p.pos
	mean /= b.parts.size()
	check(absf(mean.z + 18.0 * 0.4) < 2.5, "a carried blast keeps up with what blew up (z %.1f)" % mean.z)
	b.queue_free()
	await process_frame


func in_game() -> void:
	print("in the game")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	await process_frame
	g.launch()
	for i in 30:
		g.step(DT)
	var f := g.new_foe("dart", Models.dart())
	f.pos = Vector3(0, Rules.PY, g.frame_z - 8)
	f.rel = true
	g.kill(f)
	check(g.blasts.busy(), "a foe going down blows up")
	var c := g.fx_carry()
	check(c.z < 0.0 and c.z > -Rules.SCROLL - 0.01, "in the stage, air blasts drift with the scroll")
	check(g.fx_carry(true) == Vector3.ZERO, "and ground blasts stay on the ground")
	# nothing else on screen to blow up while the shake eases
	g.wave_i = g.waves.size()
	g.queue.clear()
	for o in g.foes:
		if o != f:
			o.dead = true
	g.shake = 1.0
	var before := g.cam.global_transform
	g.step(DT)
	check(not g.cam.global_transform.is_equal_approx(before), "a big blast shakes the camera")
	for i in int(2.0 / DT):
		g.step(DT)
	check(g.shake == 0.0, "the shake eases off")
	g.clear_all()
	check(not g.blasts.busy(), "a new run starts with no explosions about")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage blasts test")
	await pieces()
	await in_game()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)

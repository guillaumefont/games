extends ShipKit
## Echo, the replay: the ship remembers the last TAPE ticks of its flight while the thumb is
## down. Lifting leaves an echo behind: a ghost of the ship that flies that same path again,
## firing as you did, while you fly a new one. You never steer it; it fades when its tape runs
## out. Two echoes at most. Echo shots that land load the Chorus: four echoes at once, each
## replaying the tape a beat apart.

const TAPE := 150         ## ticks remembered: 2.5 s
const MIN_TAPE := 30
const MAX_ECHOES := 2
const HIT_GAIN := 1.0 / 70.0
const CHORUS := 4

var tape: Array = []      ## Vector2, oldest first
var echoes: Array = []    ## {tape, i, m, wait}


func fire() -> void:
	var sp: float = VShips.KITS.echo.shot_speed
	g.shot(g.P.x - 2.2, g.P.y + 8, 0, sp, Models.M.shot, 1)
	g.shot(g.P.x + 2.2, g.P.y + 8, 0, sp, Models.M.shot, 1)


func hold() -> void:
	tape.append(Vector2(g.P.x, g.P.y))
	while tape.size() > TAPE:
		tape.pop_front()


func lift() -> void:
	if tape.size() < MIN_TAPE:
		tape = []
		return
	if echoes.size() >= MAX_ECHOES:
		_drop(echoes[0])
		echoes.remove_at(0)
	_spawn(tape.duplicate(), 0)
	tape = []
	g.audio.play("pod")
	Diag.once("echo")


func _spawn(t: Array, wait: int) -> void:
	var model := VShips.model("echo")
	Progress.apply_paint(model, g.prog.paint_of("echo"))
	if model.has_meta("flame"):
		model.get_meta("flame").visible = false
	var m := VShips.upright(model)
	m.add_child(Models.glow("b38cff", 16.0))
	m.visible = false
	g.world.add_child(m)
	echoes.append({tape = t, i = 0, m = m, wait = wait})


func _drop(e: Dictionary) -> void:
	e.m.queue_free()
	g.glow_fx("b38cff", e.tape[mini(e.i, e.tape.size() - 1)].x, e.tape[mini(e.i, e.tape.size() - 1)].y, 3, 12.0, 10)


func ult() -> void:
	var t: Array = tape.duplicate() if tape.size() >= MIN_TAPE else []
	if t.is_empty():
		# no tape yet: the echoes sweep the screen from where the ship is
		for k in TAPE:
			t.append(Vector2(clampf(g.P.x + sin(k * 0.06) * 45.0, 8, g.W - 8), g.P.y + 10.0 + k * 0.2))
	for e in echoes:
		_drop(e)
	echoes = []
	for k in CHORUS:
		_spawn(t.duplicate(), k * 14)
	tape = []
	g.G.ult_t = TAPE + CHORUS * 14
	g.audio.play("ready", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	var every: int = int(VShips.KITS.echo.fire_every)
	var sp: float = VShips.KITS.echo.shot_speed
	for e in echoes:
		if e.wait > 0:
			e.wait -= 1
			continue
		e.i += 1
		if e.i >= e.tape.size():
			_drop(e)
			continue
		if e.i % every == 0 and not g.G.has("run"):
			var p: Vector2 = e.tape[e.i]
			for x in [-2.2, 2.2]:
				g.shot(p.x + x, p.y + 8, 0, sp, Models.M.shot, 1, "b38cff")
				g.G.pb.back().kit = true
	echoes = echoes.filter(func(e): return e.i < e.tape.size())


func on_hit(_b: Dictionary) -> void:
	gain(HIT_GAIN)


func reset() -> void:
	super.reset()
	tape = []


func clear() -> void:
	for e in echoes:
		e.m.queue_free()
	echoes = []
	super.clear()


func hint() -> String:
	if ready():
		return "FULL: LIFT FOR THE CHORUS"
	if holding() and tape.size() >= MIN_TAPE:
		return "LIFT: AN ECHO FLIES THIS PATH AGAIN"
	return "HOLD: YOUR FLIGHT IS REMEMBERED"


func sync() -> void:
	for e in echoes:
		e.m.visible = e.wait == 0 and not g.G.has("run")
		if e.m.visible:
			var p: Vector2 = e.tape[mini(e.i, e.tape.size() - 1)]
			e.m.position = Vector3(g.X(p.x), g.Y(p.y), -1.0)

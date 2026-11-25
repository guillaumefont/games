extends SceneTree
## The game: rules (hulls, caps, spending, saves), the joystick, broadside fire, the green aim
## stick, defending alone only when disconnected, the AI's manoeuvre, sinking and being sunk, treasure maps and the port. Runs headless:
##   godot --headless --path . --script tests/game_test.gd

const SAVE := "user://test_save.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func rules() -> void:
	print("rules")
	var s := Rules.fresh()
	check(s.coins == 2000 and s.maps == 10 and s.ship == "chaloupe", "a new game starts with 2 000 coins, 10 maps, a chaloupe")
	check(not s.has("diamonds"), "no diamonds")
	var m := Rules.migrate({"coins": 50, "diamonds": 3, "ship": "nope", "up": {"rameurs": 9, "voiles": 4}})
	check(m.vault == 300 and not m.has("diamonds"), "old diamonds come back as 100 coins each, in the coffre")
	check(m.ship == "chaloupe" and m.up.rameurs == 3 and m.up.voiles == 1, "unknown hull reset, upgrades clamped to the hull's caps")
	check(Rules.migrate("garbage").coins == 2000, "a broken save starts a new game")
	# stats
	var st := Rules.ship_stats("chaloupe", {"rameurs": 3, "voiles": 1, "capitaine": 1, "coque": 2}, 4)
	check(is_equal_approx(st.speed, 6 + 2.4 + 1.6), "rowers +0.8 and sails +1.6 knots")
	check(st.max_hp == 180 and st.crew_cap == 9, "hull +40, captain +3 crew places")
	var gal := Rules.ship_stats("galion", {}, 0)
	var bats := Rules.batteries(gal)
	check(bats.size() == 4, "the galion has broadsides and bow and stern chasers")
	check(Rules.guns_in_arcs(bats, PI / 2) == 5 and Rules.guns_in_arcs(bats, -PI / 2) == 5, "five guns a side")
	check(Rules.guns_in_arcs(Rules.batteries(Rules.ship_stats("chaloupe", {}, 0)), PI) == 0, "nothing fires astern of a chaloupe: get behind it")
	check(is_equal_approx(Rules.rel_bearing(0, 0, 0, 10, 0), PI / 2), "a target to +x is abeam to port of a ship heading +z")
	# money
	s = Rules.fresh()
	s.coins = 100
	s.vault = 500
	check(Rules.spend(s, 300) and s.coins == 0 and s.vault == 300, "purchases take coins on board first, then the coffre")
	check(not Rules.spend(s, 301), "can't spend more than you have")
	s = Rules.fresh()
	check(not Rules.can_upgrade(s, "voiles"), "sails need all the rowers first")
	for i in 3:
		Rules.buy_upgrade(s, "rameurs")
	check(s.up.rameurs == 3 and not Rules.buy_upgrade(s, "rameurs"), "upgrades stop at the hull's cap")
	check(Rules.can_upgrade(s, "voiles"), "then sails can be bought")
	s.coins = 9000
	s.crew.sabre = 7
	check(Rules.buy_hull(s, "sloop") and s.ship == "sloop" and s.up.rameurs == 0, "a new hull starts with no upgrades")
	check(Rules.crew_count(s) == 7 and s.coins == 5500, "the sloop keeps its crew (8 places) and costs 3 500")
	s.crew.sabre = 8
	check(Rules.buy_hull(s, "fregate") and Rules.crew_count(s) == 8, "a bigger hull keeps everyone")
	check(Rules.yard_list(s) == ["sloop", "fregate", "galion"], "the starting boat leaves the shipyard once sold")
	s.coins = 1001
	check(Rules.defeat_loss(s) == 500 and s.coins == 501, "being sunk costs half the coins on board")
	s = Rules.fresh()
	s.coins = 5000
	check(Rules.deposit(s) == 3000 and s.vault == 3000, "the coffre holds 3 000 per level")
	check(Rules.buy_base(s, "coffre") and Rules.vault_cap(s) == 6000, "a bigger coffre")
	check(Rules.islands().size() == 19 and Rules.islands() == Rules.islands(), "the same 18 islands around the port every time")
	check(Rules.enemy_build(5).hull == "galion" and Rules.enemy_build(1).up.canons == 0, "enemy levels pick hull and upgrades")
	check(Rules.fmt(1234567) == "1 234 567", "French number format")
	Rules.save_game(s, SAVE)
	check(Rules.load_game(SAVE) == Rules.migrate(s), "saves and loads")


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 3
	return g


func run(g: Game, secs: float) -> void:
	for i in int(secs * 60):
		g.step(1.0 / 60)


## Sends a mouse event to the screen (as a finger would, with touch emulation).
func touch(pos: Vector2, pressed: bool, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


## A finger with its own index, sent the way the OS does (Godot also makes up mouse events
## from the first finger, which the sticks must ignore).
func finger(i: int, pos: Vector2, pressed: bool, drag := false) -> void:
	var ev: InputEvent
	if drag:
		ev = InputEventScreenDrag.new()
		ev.index = i
	else:
		ev = InputEventScreenTouch.new()
		ev.index = i
		ev.pressed = pressed
	ev.position = pos
	root.push_input(ev, true)
	if i == 0:
		# what Godot's touch emulation adds for the first finger
		var m: InputEventMouse
		if drag:
			m = InputEventMouseMotion.new()
			m.button_mask = MOUSE_BUTTON_MASK_LEFT
		else:
			m = InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = pressed
		m.device = InputEvent.DEVICE_ID_EMULATION
		m.position = pos + Vector2(400, 0)
		m.global_position = m.position
		root.push_input(m, true)


func clear_sea(g: Game) -> void:
	for e in g.enemies:
		e.node.position = Vector3(-200, 0, -200) + Vector3(g.enemies.find(e) * 12, 0, 0)
		e.aggro_cd = 999


func game() -> void:
	print("game")
	var g := make_game()
	await process_frame
	clear_sea(g)
	g.step(1.0 / 60)
	check(g.P.xz().distance_to(Vector2(Rules.DOCK.x, Rules.DOCK.z)) < 0.1, "starts at the port's jetty")
	check(g.hud.action_labels().has("Entrer au port"), "the port can be entered from the jetty")

	# the joystick: appears under the thumb, its direction is the heading and its reach the speed
	var c := Vector2(360, 900)
	touch(c, true)
	await process_frame
	check(g.hud.joy_active, "a thumb on the sea shows the joystick")
	touch(c + Vector2(90, 0), true, true)
	await process_frame
	run(g, 3)
	check(absf(Rules.wrap_a(g.P.h - PI / 2)) < 0.05, "stick to the right: the ship turns east")
	check(g.throttle > 0.95 and g.P.v > 5, "full reach: full speed")
	touch(c + Vector2(30, 0), true, true)
	await process_frame
	run(g, 0.5)
	check(g.throttle > 0.1 and g.throttle < 0.35, "a short reach: slow")
	touch(c + Vector2(30, 0), false)
	await process_frame
	var thr := g.throttle
	run(g, 1)
	check(not g.hud.joy_active and is_equal_approx(g.throttle, thr), "lifting the thumb keeps the sail as it was")

	# broadside: an enemy abeam is fired at, one ball per battery volley
	g.P.node.position = Vector3(100, 0, -120)
	g.P.h = 0
	g.P.v = 0
	g.throttle = 0
	var e: Game.Boat = g.enemies[0]
	e.node.position = Vector3(112, 0, -120)
	e.h = 0
	e.v = 0
	var balls: int = g.s.balls
	g.start_combat(e, "fight")
	g.shoot_batteries(g.P, e, 0.016, g._pay_ball)
	check(g.s.balls == balls - 1 and g.balls.size() >= 1, "an enemy abeam takes a broadside")
	var hp := e.hp
	for i in 120:
		g._update_balls(1.0 / 60)
	check(e.hp < hp, "the balls hit")
	# an enemy dead astern: the chaloupe has no stern gun
	e.node.position = Vector3(100, 0, -132)
	g.P.rl = {}
	balls = g.s.balls
	check(g.shoot_batteries(g.P, e, 0.016, g._pay_ball).is_empty() and g.s.balls == balls, "no shot at a ship dead astern")

	# connected, the guns wait for the green stick: nothing fires on its own
	var isles_saved := g.isles
	g.isles = []
	e.node.position = Vector3(112, 0, -120)
	e.aggro_cd = 999
	g.P.rl = {}
	g.balls.clear()
	balls = g.s.balls
	var ehp := e.hp
	for i in 180:
		e.node.position = Vector3(g.P.pos().x + 12, 0, g.P.pos().z)
		e.v = 0
		g.step(1.0 / 60)
	check(g.s.balls == balls and g.balls.is_empty(), "connected: the ship never fires by itself")
	check(g.hud._aim.visible and g.can_aim(), "the green aim stick shows in a fight")
	# aim at the enemy (12 m to +x = right on screen) and let go
	var ac := g.hud.aim_center()
	touch(ac, true)
	await process_frame
	check(g.hud.aim_active and not g.hud.joy_active, "a thumb on the green stick aims, it doesn't steer")
	touch(ac + Vector2(Hud.AIM_R * 0.4, 0), true, true)
	await process_frame
	g.step(1.0 / 60)
	var at := g.aim_point()
	var ray := g.aim_ray()
	check(ray.boat == e and absf(float(ray.dist) - (12 - Game.HIT_R)) < 0.3, "the red line runs until it meets the enemy")
	check(absf(at.x - (g.P.pos().x + 12)) < 0.3 and absf(at.z - g.P.pos().z) < 0.3, "the balls go for the ship the line meets")
	check(g.aim_mark.visible and g._aim_ring.visible and absf(g._aim_line.scale.z - float(ray.dist)) < 0.3, "the red line shows on the water and stops at the enemy")
	touch(ac + Vector2(Hud.AIM_R, 0), true, true)
	await process_frame
	g.step(1.0 / 60)
	check(g.aim_point().distance_to(at) < 0.3, "pushing the stick further doesn't change the target")
	touch(ac + Vector2(Hud.AIM_R, 0), false)
	await process_frame
	check(g.s.balls == balls - 1 and g.balls.size() >= 1 and not g.hud.aim_active, "letting go fires the battery that bears")
	var b0: Dictionary = g.balls[0]
	check(float(b0.dur) < 0.4, "the balls are fast: under 0.4 s for 12 m")
	for i in 120:
		e.node.position = Vector3(g.P.pos().x + 12, 0, g.P.pos().z)
		g.step(1.0 / 60)
	check(e.hp < ehp, "the aimed broadside hits")
	# a miss: aiming at empty sea on the other side
	g.P.rl = {}
	balls = g.s.balls
	ehp = e.hp
	touch(ac, true)
	touch(ac + Vector2(-Hud.AIM_R, 0), true, true)
	touch(ac + Vector2(-Hud.AIM_R, 0), false)
	await process_frame
	for i in 120:
		e.node.position = Vector3(g.P.pos().x + 12, 0, g.P.pos().z)
		g.step(1.0 / 60)
	check(g.s.balls == balls - 1 and is_equal_approx(e.hp, ehp), "aimed away, the balls miss")
	# nothing in the way: the red line runs on into the fog
	touch(ac, true)
	touch(ac + Vector2(-Hud.AIM_R, 0), true, true)
	await process_frame
	g.step(1.0 / 60)
	check(g.aim_ray().boat == null and is_equal_approx(float(g.aim_ray().dist), Game.LINE_LEN) and not g._aim_ring.visible, "nothing in the way: an endless red line")
	# an island in the way: the line stops on it and the guns fire at it
	g.isles = [{"x": g.P.pos().x - 15, "z": g.P.pos().z, "r": 5.0}]
	g.step(1.0 / 60)
	ray = g.aim_ray()
	check(ray.isle and absf(float(ray.dist) - 10) < 0.5, "the red line stops on an island")
	g.P.rl = {}
	balls = g.s.balls
	touch(ac + Vector2(-Hud.AIM_R, 0), false)
	await process_frame
	check(g.s.balls == balls - 1 and g.balls.size() >= 1, "the guns fire at the island")
	check(g.on_island(g.balls[0].to) or Vector2(g.balls[0].to.x - ray.point.x, g.balls[0].to.z - ray.point.z).length() < 1.8, "the balls fall on the island's shore")
	# too far: the line meets an island beyond the guns' range
	g.isles = [{"x": g.P.pos().x - 60, "z": g.P.pos().z, "r": 5.0}]
	g.P.rl = {}
	balls = g.s.balls
	touch(ac, true)
	touch(ac + Vector2(-Hud.AIM_R, 0), true, true)
	touch(ac + Vector2(-Hud.AIM_R, 0), false)
	await process_frame
	check(g.s.balls == balls, "an obstacle beyond range: no shot")
	g.isles = []
	# straight astern: the chaloupe has no gun there
	g.P.rl = {}
	balls = g.s.balls
	touch(ac, true)
	touch(ac + Vector2(0, -Hud.AIM_R), true, true)
	touch(ac + Vector2(0, -Hud.AIM_R), false)
	await process_frame
	check(g.s.balls == balls, "no gun bears astern: nothing fires")
	# let go in the middle: cancelled
	touch(ac, true)
	touch(ac + Vector2(8, 0), true, true)
	touch(ac + Vector2(8, 0), false)
	await process_frame
	check(g.s.balls == balls, "letting go in the middle cancels the shot")
	# two thumbs: one steers while the other aims
	finger(0, Vector2(200, 700), true)
	finger(1, ac, true)
	finger(0, Vector2(290, 700), false, true)
	finger(1, ac + Vector2(Hud.AIM_R, 0), false, true)
	await process_frame
	check(g.hud.joy_active and g.hud.aim_active, "two fingers: steering and aiming together")
	check(g.hud.joy_vec.x > 0.9 and g.hud.aim_vec.x > 0.9, "each stick follows its own finger")
	finger(1, ac + Vector2(Hud.AIM_R, 0), false)
	await process_frame
	check(g.hud.joy_active and not g.hud.aim_active and g.s.balls == balls - 1, "lifting the aiming finger fires, the other still steers")
	finger(0, Vector2(290, 700), false)
	await process_frame
	check(not g.hud.joy_active, "and the steering finger lifts")
	g.isles = isles_saved

	# disconnected: the ship defends itself, manoeuvring and firing alone
	g.P.rl = {}
	g.balls.clear()
	balls = g.s.balls
	g.throttle = 0
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not g.connected, "leaving the game disconnects")
	for i in 240:
		g.step(1.0 / 60)
	check(g.s.balls < balls, "disconnected: the ship fires on its own")
	check(absf(g.P.v) > 0.5, "and manoeuvres on its own")
	check(not g.hud._aim.visible, "no green stick while away")
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	g.step(1.0 / 60)
	check(g.connected and g.hud._aim.visible, "back in the game: the guns are yours again")
	g.P.rl = {}
	balls = g.s.balls
	for i in 120:
		g.step(1.0 / 60)
	check(g.s.balls == balls, "and they stop firing alone")
	# the AI looks for a heading that brings its guns to bear and keeps out of ours
	# (from a fixed spot: the enemy dead astern of us, both heading +z)
	g.P.node.position = Vector3(100, 0, -120)
	g.P.h = 0
	e.node.position = Vector3(100, 0, -132)
	e.h = 0
	var r := Rules.ai_choose(e.view(), e.st, g.P.view(), g.P.st, 1.0, g.isles)
	var rel := Rules.rel_bearing(e.pos().x, e.pos().z, r[0], g.P.pos().x, g.P.pos().z)
	check(Rules.guns_in_arcs(Rules.batteries(e.st), rel) > 0 or absf(Rules.wrap_a(r[0] - e.h)) > 0.3, "the AI turns to bring a battery to bear")
	# sinking an enemy pays and replaces it later
	var coins: int = g.s.coins
	var n := g.enemies.size()
	g.hurt(e, 9999, true)
	check(e.state == "sink" and g.s.coins == coins + e.coins and g.combat.is_empty(), "a sunk enemy pays its coins and ends the fight")
	run(g, 4)
	check(g.enemies.size() == n - 1, "the wreck goes down")
	run(g, 12)
	check(g.enemies.size() == n, "a new ship comes 15 s later")

	# an attack: the prompt waits 6 s, but a connected player's ship never defends itself
	clear_sea(g)
	var a: Game.Boat = g.enemies[1]
	a.node.position = g.P.pos() + Vector3(14, 0, 0)
	g.P.v = 0
	g.throttle = 0
	g.P.hp = 9999
	balls = g.s.balls
	g.start_combat(a, "pending")
	check(g.hud.prompt_visible(), "being attacked asks: fight back or flee")
	run(g, 6.2)
	check(not g.hud.prompt_visible() and g.combat.get("mode", "") == "fight", "no answer: the prompt goes, the fight is on")
	run(g, 6)
	check(absf(g.P.v) < 0.2 and g.s.balls == balls, "connected: the ship neither manoeuvres nor fires by itself")
	g.P.hp = g.P.max_hp
	g.on_flee()
	check(g.combat.mode == "flee" and g.auto_flee, "flee runs away")

	# being sunk: half the coins on board, the coffre is safe, back at the port
	g.s.coins = 1000
	g.s.vault = 700
	g.hurt(g.P, 9999, false)
	check(not g.alive and g.s.coins == 500 and g.s.vault == 700, "sunk: half the coins on board lost, the coffre is intact")
	run(g, 3)
	check(g.alive and g.P.pos().distance_to(Rules.DOCK) < 1 and g.P.hp == g.P.max_hp, "back at the jetty, repaired")

	# treasure
	clear_sea(g)
	var maps: int = g.s.maps
	g.use_map()
	check(g.s.maps == maps - 1 and not g.treasure.is_empty(), "a map shows where the treasure is")
	g.use_map()
	check(g.s.maps == maps - 1, "one map at a time")
	coins = g.s.coins
	var gold: int = g.treasure.gold
	g.P.node.position = g.treasure.pos
	g.step(1.0 / 60)
	check(g.treasure.is_empty() and g.s.coins == coins + gold, "sailing onto the X digs it up")

	# the port
	g.P.node.position = Rules.DOCK
	g.step(1.0 / 60)
	check(g.hud.press_action("Entrer au port") and g.hud.port_open(), "entering the port opens it")
	run(g, 0.5)
	check(g.P.v == 0, "the ship waits at the port")
	g.s.coins = 20000
	g.hud._tab = "bateau"
	g.hud.refresh_port()
	await process_frame
	check(g.hud.preview_hull() == "chaloupe", "the shipyard shows your ship")
	g.hud._pv_idx = 3
	g.hud.refresh_port()
	await process_frame
	check(g.hud.preview_hull() == "galion", "and the hulls for sale")
	var buy := find_button(g.hud._body, "Acheter")
	check(buy != null and not buy.disabled, "the galion can be bought")
	buy.pressed.emit()
	await process_frame
	check(g.s.ship == "galion" and g.P.max_hp == 380, "bought: you sail a galion")
	check(Rules.load_game(SAVE).ship == "galion", "and it is saved")
	var sheet: Control = g.hud._port.get_node("Sheet")
	var size := sheet.size
	for t in ["coffre", "equipage", "base", "bateau"]:
		g.hud._tab = t
		g.hud.refresh_port()
		await process_frame
		await process_frame
		check(sheet.size == size, "the port keeps its size on tab " + t)
	g.hud.close_port()
	check(not g.hud.port_open(), "cast off")
	g.queue_free()
	await process_frame


func find_button(n: Node, prefix: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text.begins_with(prefix):
			return c
		var f := find_button(c, prefix)
		if f:
			return f
	return null


func _initialize() -> void:
	print("Mer des Brumes game test")
	rules()
	await game()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	print("game test: ", "PASS" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)

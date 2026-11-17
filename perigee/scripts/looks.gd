class_name Looks
extends RefCounted
## Draws the cosmetics from the unlock track (ships and trails), for the game view and for the
## previews in the hangar. Looks only: nothing here may feed back into the sim.

const INK := Color("f3ecdf")
const SAND := Color("f2c879")
const CORAL := Color("ff8a6b")
const TEAL := Color("6fd6c5")


## The ship at `pos`, heading along `dir` (a unit vector, or zero when unknown).
static func draw_ship(ci: CanvasItem, id: String, pos: Vector2, dir: Vector2, t: float) -> void:
	match id:
		"ship_dart":
			var d := dir if dir.length() > 0.01 else Vector2.UP
			var side := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([pos + d * 9.0, pos - d * 6.0 + side * 6.0,
				pos - d * 3.0, pos - d * 6.0 - side * 6.0]), INK)
		"ship_laurel":
			# the Cradle all-stars reward: a gold ship in a wreath of leaves
			ci.draw_circle(pos, 4.5, SAND, true, -1.0, true)
			for side in [-1.0, 1.0]:
				for i in 4:
					var a: float = PI / 2.0 + side * (0.55 + i * 0.5)
					var at := pos + Vector2(cos(a), sin(a)) * 8.5
					ci.draw_circle(at, 1.7, Color(SAND, 0.9), true, -1.0, true)
		"ship_lantern":
			# the Lantern all-stars reward: a pulsar's core that beats, in a lit ring
			var beat := 0.5 + 0.5 * sin(t * 5.0)
			ci.draw_circle(pos, 9.0 + beat * 2.0, Color(Color("b49cff"), 0.18 + 0.12 * beat), true, -1.0, true)
			ci.draw_arc(pos, 7.5, 0, TAU, 24, Color("b49cff"), 1.6, true)
			ci.draw_circle(pos, 3.6 + beat * 0.8, INK, true, -1.0, true)
		"ship_halo":
			ci.draw_circle(pos, 4.0, INK, true, -1.0, true)
			ci.draw_arc(pos, 8.5 + sin(t * 3.0) * 0.8, 0, TAU, 28, SAND, 1.5, true)
		_:
			ci.draw_circle(pos, 5.5, INK, true, -1.0, true)


## The trail through `pts` (oldest first) up to `head`. `palette` gives the ribbon its colours.
static func draw_trail(ci: CanvasItem, id: String, pts: Array, head: Vector2, palette: Array, t: float) -> void:
	var n := pts.size()
	for i in range(2, n, 2):
		var f := float(i) / n
		var a: Vector2 = pts[i - 2]
		var b: Vector2 = head if i >= n - 2 else pts[i]
		match id:
			"trail_comet":
				ci.draw_line(a, b, Color(CORAL.lerp(SAND, f), f * 0.8), maxf(f * 8.0, 0.5), true)
			"trail_ribbon":
				var col: Color = palette[(i / 6) % palette.size()]
				ci.draw_line(a, b, Color(col, f * 0.85), maxf(f * 4.5, 0.8), true)
			"trail_eddy":
				# the Backwash all-stars reward: a teal wake that curls back on itself
				var d: Vector2 = (b - a)
				var side := Vector2(-d.y, d.x).normalized() if d.length() > 0.01 else Vector2.ZERO
				var curl := side * sin(i * 0.7 + t * 4.0) * 5.0 * f
				ci.draw_line(a, b, Color(TEAL, f * 0.6), maxf(f * 3.5, 0.5), true)
				ci.draw_circle(b + curl, 0.8 + 1.4 * f, Color(TEAL.lerp(INK, f), f * 0.9), true, -1.0, true)
			"trail_sparkle":
				ci.draw_line(a, b, Color(INK, f * 0.35), maxf(f * 2.5, 0.5), true)
				if i % 8 == 0:
					var tw := 0.5 + 0.5 * sin(t * 9.0 + i)
					ci.draw_circle(b, 1.2 + 1.6 * f * tw, Color(SAND, f), true, -1.0, true)
			_:
				ci.draw_line(a, b, Color(INK, f * 0.5), maxf(f * 5.0, 0.5), true)

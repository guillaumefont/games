extends SceneTree
## Prints each fortress's plan (headless): its length, and for each section its lane, where it
## sits on the hull, how many of its guns the lane sees, how many of the next section's it already
## sees in range, and whether the glide there keeps clear of the hull.
##   godot --headless --path . --script tools/fortress_plan.gd [id]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for id: String in Rules.FORTRESSES:
		if args.size() > 0 and args[0] != id:
			continue
		var f: Dictionary = Rules.FORTRESSES[id]
		print("%s  L %.0f  hull segments %d  deck %.0f" % [id, Rules.fortress_len(id), Capital.hull_count(id), Rules.deck_of(id)])
		var prev := Vector3(0, -0.5, -40.0)
		for i in f.sections.size() - 1:
			var l := Capital.lane(id, i)
			var to := Vector3(l.x, l.y, l.along)
			var pts := Capital.glide(id, prev, to)
			var hits := Capital.glide_hits(id, pts, prev.z, to.z)
			prev = to
			var own := 0
			for g: Array in f.sections[i].guns:
				own += 1 if seen(id, l, Rules.gun_at(id, i, g)) else 0
			var nxt := 0
			var near := 1e9
			if i + 1 < f.sections.size() - 1:
				for g: Array in f.sections[i + 1].guns:
					var at := Rules.gun_at(id, i + 1, g)
					var dist := -at.z - float(l.along)
					if dist <= 62.0 and dist > 5.0 and seen(id, l, at):
						nxt += 1
					near = minf(near, dist)
			print("  %-20s %-6s at %5.1f along %6.1f x %6.1f y %6.1f  own %d/%d  next seen %d (nearest %.0f)  glide %.1fs%s" % [
				f.sections[i].name, l.route, Rules.section_at(id, i), l.along, l.x, l.y, own, f.sections[i].guns.size(), nxt, near,
				Capital.glide_time(pts), "  HITS %d" % hits if hits else ""])
	quit()


## Whether a point is seen from anywhere the drag takes the ship in a lane.
static func seen(id: String, l: Dictionary, at: Vector3) -> bool:
	var r: Vector4 = l.reach
	for p: Vector2 in [Vector2.ZERO, Vector2(r.x, 0), Vector2(r.y, 0), Vector2(0, r.z), Vector2(0, r.w)]:
		if Capital.sees(id, at, Vector3(l.x + p.x, l.y + p.y, -float(l.along))):
			return true
	return false
